"""Compare DIAG on/off engines with fixed e0c4 and verify real CFG milestones."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = 'e0c4cf496d0d1f44575d702c06a8e0218e85feda'
PREFIX = 'refactor/hdr_jpeg_timing/src_fpga/'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}', args.name):
        parser.error('unsafe name')
    run = REPO/'tmp/a_cfgobs_20261027/cause'/args.name
    run.mkdir(parents=True, exist_ok=False)
    baselines = []

    def frozen(path):
        body = subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=REPO)
        baselines.append({'commit': BASE, 'path': path, 'sha256': hashlib.sha256(body).hexdigest()})
        return body.decode().replace('\r\n', '\n')

    reference = run/'cfg_diag_e0c4_reference.v'
    reference.write_text(frozen(PREFIX+'rtl/mono_config_engine_v2.v').replace(
        'module mono_config_engine_v2 #(', 'module timing_config_engine_reference #('), newline='\n')
    base = frozen('refactor/hdr_jpeg/src_fpga/simulation/control/tb_mono_config_ack_pipeline.sv')
    substitutions = {
        'module tb_mono_config_ack_pipeline;': 'module timing_config_base #(parameter integer TRUSTED_COMMANDS=0)(output reg done=0);',
        'mono_config_engine_v2 #(.V2_SUPPORTED_MODES': 'mono_config_engine_v2 #(.CFG_DIAG_ENABLE(1),.TRUSTED_COMMANDS(TRUSTED_COMMANDS),.V2_SUPPORTED_MODES',
        '    reg rst_n=0;': '    reg rst_n=0;\n    reg diag_observer_rst_n=0,diag_source_fs=0;\n    reg [15:0] diag_source_gates=0;\n    wire [223:0] diag_data;\n    initial begin #9;diag_observer_rst_n=1;end',
        "extension[191:128]=64'h800000019abcdef0;": "extension[191:128]=64'h000000009abcdef0;",
        '$finish;': 'done=1;',
    }
    for old, new in substitutions.items():
        if base.count(old) != 1:
            raise RuntimeError('fixed base seam '+old)
        base = base.replace(old, new)
    basepath = run/'cfg_diag_base.sv'
    basepath.write_text(base, newline='\n')
    bench = frozen(PREFIX+'simulation/control/tb_timing_config_control.sv')
    # Use the same inputs for the new disabled specialization as both other engines.
    declaration = bench[bench.index('    wire ref_command_ready'):bench.index('    timing_config_engine_reference #(')]
    instance = bench[bench.index('    timing_config_engine_reference #('):bench.index('    integer checks=')]
    off_instance = instance.replace('timing_config_engine_reference #(', 'mono_config_engine_v2 #(.CFG_DIAG_ENABLE(0),').replace('reference_dut(', 'diag_off_dut(').replace('ref_', 'off_')
    off_instance = off_instance.replace('.active_processing_enables(off_active_processing_enables));',
        '.active_processing_enables(off_active_processing_enables),\n        .diag_observer_rst_n(base.diag_observer_rst_n),.diag_source_fs(base.diag_source_fs),\n        .diag_source_gates(base.diag_source_gates),.diag_data());')
    bench = bench.replace('    integer checks=', declaration.replace('ref_', 'off_')+off_instance+'    integer checks=', 1)
    start = bench.index('            check({base.command_ready')
    end = bench.index('            check(base.dut.frame_apply_eligible===', start)
    compare = bench[start:end].replace('ref_', 'off_').replace('fixed f3fc9adb', 'new disabled DIAG')
    bench = bench[:end]+compare+bench[end:]
    extra = HERE/'cfg_diag_engine_cases.vh'
    collision = HERE/'r4_config_tx_cases.vh'
    # The old artificial seam mutates matching internal authorities in all three engines.
    collision_text = collision.read_text().replace('reference_dut.', 'reference_dut.')
    lines = []
    for line in collision_text.splitlines():
        lines.append(line)
        if 'reference_dut.' in line and '=' in line and 'check(' not in line:
            # Multiple statements may share one line: mirror each reference assignment only.
            for match in re.finditer(r'reference_dut\.\w+\s*=\s*[^;]+;', line):
                lines.append('                '+match.group().replace('reference_dut.', 'diag_off_dut.'))
    collision_text = '\n'.join(lines)
    seam = '    initial begin\n        wait(base_done);'
    if bench.count(seam) != 1:
        raise RuntimeError('test task seam')
    bench = bench.replace(seam, collision_text+'\n'+extra.read_text()+'\n'+seam)
    seam = '        check(eligible_cycles>10&&wait_entries>=11&&wait_exits>=11&&response_stalls>100,'
    bench = bench.replace(seam, '        r4_extra_tests();\n        cfg_diag_extra_tests();\n'+seam)
    bench = bench.replace('fixed f3fc9adb', 'fixed e0c4')
    benchpath = run/'cfg_diag_miter_tb.sv'
    benchpath.write_text(bench, newline='\n')
    manifest = PROJECT/'SOURCE_MANIFEST.json'
    includes = [PROJECT/path for path in json.loads(manifest.read_text())['include_dirs']]
    sources = [PROJECT/'src_fpga/rtl'/name for name in ['mono_config_legacy_scan_v1.v',
        'mono_config_scan_v2.v', 'cfg_diag_pixel.v', 'mono_config_engine_v2.v']]
    headers = [path for directory in includes for path in directory.glob('*.vh')]
    inputs = sources+headers+[extra, collision, Path(__file__)]
    identity = [{'path': str(path), 'sha256': sha(path)} for path in inputs]
    result = {'status': 'IN_PROGRESS', 'baseline': baselines, 'inputs': identity,
        'fixture_adaptation': 'Only legal F04 delta high32, new DIAG ports, extra miter/events; fixed test sequence retained',
        'modelsim_bin': str(args.modelsim_bin), 'synthesis': 'NOT_RUN',
        'physical': 'NOT_RUN', 'timing': 'NOT_RUN', 'board': 'NOT_RUN'}

    def execute(exe, words):
        argv = [str(args.modelsim_bin/exe)]+list(map(str, words))
        completed = subprocess.run(argv, cwd=run, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (run/(exe+'.console.log')).write_text(completed.stdout, errors='replace')
        if completed.returncode:
            raise RuntimeError(completed.stdout[-12000:])

    try:
        execute('vmap.exe', ['-c'])
        execute('vlib.exe', ['work'])
        execute('vmap.exe', ['work', 'work'])
        inc = ['+incdir+'+str(directory) for directory in includes]
        execute('vlog.exe', ['-quiet', '-l', 'rtl.log']+inc+sources+[reference])
        execute('vlog.exe', ['-quiet', '-sv', '-l', 'bench.log']+inc+[basepath, benchpath])
        execute('vsim.exe', ['-c', 'work.tb_timing_config_control', '-l', 'run.log', '-do',
            'onerror {quit -code 1}; run -all; quit -f'])
        body = (run/'run.log').read_text()
        if 'RESULT: PASS timing_config_control_all' not in body or body.count('RESULT: PASS cfg_diag_engine_events') != 2:
            raise RuntimeError(body[-12000:])
        for name in ['rtl.log', 'bench.log', 'run.log']:
            if re.search(r'\*\*\s+(Warning|Error|Fatal):', (run/name).read_text()):
                raise RuntimeError('unclassified diagnostic '+name)
        for row in identity:
            if sha(Path(row['path'])) != row['sha256']:
                raise RuntimeError('input changed '+row['path'])
        result['status'] = 'PASS'
        result['metrics'] = [line.strip('# ') for line in body.splitlines() if 'RESULT: PASS' in line]
        print('\n'.join(result['metrics']))
    except Exception as error:
        result.update(status='FAIL', error=str(error))
        raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result, indent=2)+'\n')
    print(run/'RESULTS.json')


if __name__ == '__main__':
    main()
