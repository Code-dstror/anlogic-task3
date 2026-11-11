"""R3 source-bound miter for pre-BUFG cleanup data masks, with official BUFG."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = '946d970c2f660eaf7dad85eea91931ec76c12200'
REL = 'refactor/hdr_jpeg_timing/src_fpga/rtl/hdr_pair_product_abort_drain4.v'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    a = ap.parse_args()
    if not re.fullmatch(r'r4_[a-z0-9_]+', a.name):
        ap.error('run name must start r4_')
    run = PROJECT / 'tmp/r4_reset_data' / a.name
    run.mkdir(parents=True, exist_ok=False)
    leaf = PROJECT / 'src_fpga/rtl/hdr_pair_product_abort_drain4.v'
    boundary = PROJECT / 'src_fpga/rtl/stream_reset_boundary2.v'
    top = PROJECT / 'src_fpga/rtl/anlogic2026.v'
    tb = HERE / 'r4_reset_data_tb.sv'
    model = a.td_root.resolve() / 'sim_release/ph1/ph1_logic_clk.v'
    raw = subprocess.check_output(['git', 'show', BASE + ':' + REL], cwd=REPO)
    old = raw.decode().replace('\r\n', '\n')
    new = leaf.read_text()
    # No state/process, original reset equation or clear equation changed.
    assert new[new.index('    generate'): ] == old[old.index('    generate'): ]
    assert 'assign o_local_rst_n=rst_n && !applied_clear;' in new
    canonical = new[new.index('    localparam'):new.index('    generate')]
    canonical = canonical.replace('    wire data_reset_n=SEPARATE_DATA_RESET!=0 ? i_data_reset_n : rst_n;\n', '')
    canonical = canonical.replace('    assign o_local_data_rst_n=data_reset_n && !applied_clear;\n', '')
    assert canonical == old[old.index('    localparam'):old.index('    generate')]
    assert not re.search(r'always\s*@\s*\([^)]*(?:posedge|negedge)\s+async_n', boundary.read_text())
    t = re.sub(r'\s+', '', top.read_text())
    for instance, legacy, data in [('u_cleanup', 'physical_processing_rst_n', 'physical_processing_data_rst_n'),
                                   ('u_pp_cleanup', 'private_pp_reset_n', 'private_pp_data_rst_n')]:
        start = t.index('hdr_pair_product_abort_drain4#(.SYNC_CLEAR_ENABLE(1),.SEPARATE_DATA_RESET(1))' + instance + '(')
        ports = t[start:t.index(');', start)]
        assert '.rst_n(pixel_rst_n)' in ports
        assert '.i_data_reset_n(pixel_reset_local_n)' in ports
        assert f'.o_local_rst_n({legacy})' in ports
        assert f'.o_local_data_rst_n({data})' in ports
    assert 'wireprocessing_data_async_n=private_processing_selected?private_pp_data_rst_n:physical_processing_data_rst_n;' in t
    assert 'wireboundary_async_n=f21_core_async_reset_n&&processing_data_async_n;' in t
    assert 'wireprocessing_async_n=private_processing_selected?private_pp_reset_n:physical_processing_rst_n;' in t
    assert 'always@(posedgepixel_clk)processing_run<=f21_core_reset_n&&processing_async_n;' in t
    reference = run / 'r4_abort_reference.v'
    reference.write_text(old.replace('module hdr_pair_product_abort_drain4 #(', 'module r4_abort_reference #(', 1), newline='\n')
    inputs = [{'path': str(p.resolve()), 'sha256': sha(p)} for p in [leaf, boundary, top, tb, model, reference, Path(__file__)]]
    report = {'status': 'IN_PROGRESS', 'baseline': {'commit': BASE, 'path': REL, 'sha256': hashlib.sha256(raw).hexdigest()},
              'td_root': str(a.td_root.resolve()), 'modelsim_bin': str(a.modelsim_bin.resolve()),
              'inputs': inputs, 'new_state_bits': 0, 'latency_change_cycles': 0,
              'all_existing_leaf_state_processes': 'BYTE_IDENTICAL', 'boundary_sequential_ASR_inputs': [],
              'top_ASR': 'original pixel_rst_n and both original o_local_rst_n outputs retained',
              'physical_model': 'Official PH1_LOGIC_BUFG logical model; no routed delay or physical recovery claim',
              'synthesis': 'NOT_RUN', 'physical_timing': 'NOT_RUN', 'board': 'NOT_RUN'}
    started = time.monotonic()

    def command(name, executable, words):
        result = subprocess.run([str(a.modelsim_bin / executable)] + [str(w) for w in words], cwd=run,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace')
        (run / (name + '.console.log')).write_text(result.stdout)
        if result.returncode:
            raise RuntimeError(name + ' failed: ' + result.stdout[-7000:])
    try:
        command('map', 'vmap.exe', ['-c'])
        command('lib', 'vlib.exe', ['work'])
        command('model', 'vlog.exe', ['-quiet', '-l', 'model.log', model])
        command('rtl', 'vlog.exe', ['-quiet', '-l', 'rtl.log', leaf, boundary, reference])
        command('bench', 'vlog.exe', ['-quiet', '-sv', '-l', 'bench.log', tb])
        command('run', 'vsim.exe', ['-c', 'work.r4_reset_data_tb', '-l', 'run.log', '-do', 'run -all; quit -f'])
        log = (run / 'run.log').read_text()
        assert 'RESULT: PASS r4_reset_data_all' in log, log[-7000:]
        for filename in ['model.log', 'rtl.log', 'bench.log', 'run.log']:
            assert not re.search(r'\*\* (Warning|Error|Fatal):', (run / filename).read_text()), filename
        for row in inputs:
            assert sha(row['path']) == row['sha256'], 'Executed source drift: ' + row['path']
        report.update(status='PASS', metrics=[line.strip('# ') for line in log.splitlines() if 'RESULT: PASS' in line])
        print('\n'.join(report['metrics']))
    except Exception as error:
        report.update(status='FAIL', error=str(error))
        raise
    finally:
        report['elapsed_seconds'] = round(time.monotonic() - started, 3)
        (run / 'RESULTS.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Results:', run / 'RESULTS.json')


if __name__ == '__main__':
    main()
