"""Exercise real CFG FIFOs/RAM and compare DIAG-enabled USER BAR with e0c4."""
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
    parser.add_argument('--td-root', type=Path, required=True)
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

    reference = run/'cfg_diag_e0c4_bar.v'
    reference.write_text(frozen(PREFIX+'rtl/mono_config_bar_v2.v').replace(
        'module mono_config_bar_v2 #(', 'module cfg_diag_e0c4_bar #('), newline='\n')
    bench = frozen(PREFIX+'simulation/control/tb_f04_config_service.sv')
    bench = bench.replace('module tb_f04_config_service;', 'module tb_cfg_diag_service;\n    wire [447:0] diag_domains;')
    bench = bench.replace('mono_config_service_v2 #(.EXT_SUPPORTED', 'mono_config_service_v2 #(.CFG_DIAG_ENABLE(1),.EXT_SUPPORTED')
    bench = bench.replace('.active_config(active_config),.active_schema2()',
        '.diag_observer_rst_n({2{rst_n}}),.diag_source_fs(1\'b0),.diag_source_gates(16\'d0),\n        .diag_domains(diag_domains),.diag_domain_reset_n(),.active_config(active_config),.active_schema2()')
    extra = HERE/'cfg_diag_service_events.vh'
    seam = '    initial begin\n        #100;'
    if bench.count(seam) != 1:
        raise RuntimeError('test insertion seam')
    bench = bench.replace(seam, extra.read_text()+'\n'+seam)
    seam = '        $display("RESULT: PASS F04 service'
    if bench.count(seam) != 1:
        raise RuntimeError('test finish seam')
    bench = bench.replace(seam,
        '        check(diag_prepares==12&&diag_presents==6&&diag_copies==6&&diag_publications==6&&diag_copy_cycles>100, "all six real USER publish sequences observed");\n'
        '        $display("RESULT: PASS cfg_diag_service_events prepares=%0d presents=%0d copies=%0d publications=%0d copy_cycles=%0d miter_checks=%0d",diag_prepares,diag_presents,diag_copies,diag_publications,diag_copy_cycles,diag_miter_checks);\n'+seam)
    benchpath = run/'cfg_diag_service_tb.sv'
    benchpath.write_text(bench, newline='\n')
    rtl, ip = PROJECT/'src_fpga/rtl', PROJECT/'src_fpga/ip'
    includes = [PROJECT/path for path in json.loads((PROJECT/'SOURCE_MANIFEST.json').read_text())['include_dirs']]
    headers = [path for directory in includes for path in directory.glob('*.vh')]
    models = [args.td_root/'sim_release'/name for name in ['common/al_phy_glbl.v',
        'ph1/ph1_logic_eram.v', 'ph1/ph1_logic_fifo.v', 'ph1/ph1_logic_ramfifo.v',
        'ph1/ph1_phy_eram.v', 'ph1/ph1_phy_fifoctrl.v']]
    sources = [args.td_root/'sim_release/ph1/ph1_phy_gsr.v']+[ip/name for name in [
        'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v',
        'camera_control_fifo_40x512/camera_control_fifo_40x512.v']]
    sources += [rtl/name for name in ['td_sdp_ram40.v', 'reset_release_sync.v', 'control_fifo_40x512.v',
        'control_message_fifo_ip.v', 'mono_config_byte_store_v2.v', 'mono_config_legacy_scan_v1.v',
        'mono_config_scan_v2.v', 'cfg_diag_user.v', 'cfg_diag_pixel.v', 'mono_config_bar_v2.v',
        'mono_config_engine_v2.v', 'mono_config_service_v2.v']]
    inputs = models+sources+headers+[extra, Path(__file__)]
    identity = [{'path': str(path), 'sha256': sha(path)} for path in inputs]
    result = {'status': 'IN_PROGRESS', 'baseline': baselines, 'inputs': identity,
        'modelsim_bin': str(args.modelsim_bin), 'td_root': str(args.td_root),
        'defines': ['PH1', 'C15_F23_FULLHEIGHT_PROFILE=1'],
        'synthesis': 'NOT_RUN', 'physical': 'NOT_RUN', 'timing': 'NOT_RUN', 'board': 'NOT_RUN'}

    def execute(label, exe, words):
        completed = subprocess.run([str(args.modelsim_bin/exe)]+list(map(str, words)), cwd=run,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace')
        (run/(label+'.console.log')).write_text(completed.stdout)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-12000:])

    try:
        execute('vmap', 'vmap.exe', ['-c'])
        execute('work', 'vlib.exe', ['work'])
        execute('ph1', 'vlib.exe', ['ph1'])
        execute('models', 'vlog.exe', ['-quiet', '-work', 'ph1', '-l', 'models.log']+models)
        definitions = ['+define+PH1', '+define+C15_F23_FULLHEIGHT_PROFILE=1']
        inc = ['+incdir+'+str(directory) for directory in includes]
        execute('rtl', 'vlog.exe', ['-quiet', '-l', 'rtl.log']+definitions+inc+sources+[reference])
        execute('bench', 'vlog.exe', ['-quiet', '-sv', '-l', 'bench.log']+definitions+inc+[benchpath])
        execute('run', 'vsim.exe', ['-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl', 'work.tb_cfg_diag_service',
            '-l', 'run.log', '-do', 'onerror {quit -code 1}; run -all; quit -f'])
        body = (run/'run.log').read_text(errors='replace')
        if 'RESULT: PASS cfg_diag_service_events' not in body or 'RESULT: PASS F04 service' not in body:
            raise RuntimeError(body[-12000:])
        warnings = []
        for path in run.glob('*.log'):
            if path.name.endswith('.console.log'):
                continue
            lines = path.read_text(errors='replace').splitlines()
            for index, line in enumerate(lines):
                if re.search(r'\*\* (Error|Fatal):', line):
                    raise RuntimeError(path.name+': '+line)
                if '** Warning:' not in line:
                    continue
                ecc_compile = re.search(r'ram40_sdp_fixed.v\(69\).*ecc_[sd]biterrinj', line)
                ecc_runtime = (re.search(r"\(vsim-3015\).*port 'ecc_[sd]biterrinj'.*ph1_logic_eram.v\(52\)", line)
                    and index+1 < len(lines) and '/src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v Line: 69'
                    in lines[index+1].replace('\\', '/'))
                init_bound = re.search(r'ph1_logic_eram.v\(1287\).*INIT_FILE.*out of bounds', line)
                if not (ecc_compile or ecc_runtime or init_bound):
                    raise RuntimeError('unclassified warning '+path.name+': '+line)
                warnings.append({'log': path.name, 'line': index+1, 'message': line})
        for row in identity:
            if sha(Path(row['path'])) != row['sha256']:
                raise RuntimeError('input changed '+row['path'])
        result.update(status='PASS', metrics=[line.strip('# ') for line in body.splitlines() if 'RESULT: PASS' in line],
            accepted_vendor_warnings=warnings)
        print('\n'.join(result['metrics']))
    except Exception as error:
        result.update(status='FAIL', error=str(error))
        raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result, indent=2)+'\n')
    print(run/'RESULTS.json')


if __name__ == '__main__':
    main()
