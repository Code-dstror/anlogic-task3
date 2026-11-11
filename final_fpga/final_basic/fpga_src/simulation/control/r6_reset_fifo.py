"""R6 stopped-clock reset cohorts and stream integrity, with official TD FIFO models."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch(r'r6_reset_[a-z0-9_]+', args.name):
        ap.error('independent run name must start r6_reset_')
    run = PROJECT / 'tmp' / args.name
    run.mkdir(parents=True, exist_ok=False)
    rtl, ip = PROJECT / 'src_fpga/rtl', PROJECT / 'src_fpga/ip'
    models = [args.td_root / 'sim_release' / p for p in [
        'common/al_phy_glbl.v', 'ph1/ph1_logic_dram.v', 'ph1/ph1_logic_eram.v',
        'ph1/ph1_logic_fifo.v', 'ph1/ph1_logic_ramfifo.v', 'ph1/ph1_phy_eram.v',
        'ph1/ph1_phy_fifoctrl.v']]
    sources = [args.td_root / 'sim_release/ph1/ph1_phy_gsr.v'] + [ip / p for p in [
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v',
        'camera_control_fifo_40x512/camera_control_fifo_40x512.v',
        'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v', 'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v',
        'camera_packet_fifo_147x512/camera_packet_fifo_147x512.v']]
    sources += [rtl / p for p in ['control_fifo_40x512.v', 'control_message_fifo_ip.v',
        'axis_frame_fifo_ip.v', 'record_format_bar.v', 'record_format_service.v']]
    benches = [HERE / p for p in ['r6_reset_fifo_tb.sv', 'r6_record_reset_tb.sv']]
    include = rtl / 'include/04_include/pcie_protocol_v1.vh'
    identity = [{'path': str(p.resolve()), 'sha256': sha(p)}
                for p in models + sources + benches + [include, Path(__file__)]]
    result = {'status': 'IN_PROGRESS', 'inputs': identity,
              'modelsim_bin': str(args.modelsim_bin), 'td_root': str(args.td_root),
              'commands': [], 'synthesis': 'NOT_RUN', 'physical_timing': 'NOT_RUN', 'board': 'NOT_RUN',
              'state_bits_delta_per_wrapper': -2,
              'stream_contract': 'opaque 147-bit axis words; captured147/borrowed617-bit control messages; LSB-first40-bit flits; reset flushes the cohort',
              'cdc': ['sink_reset_release_pipe[2] -> source_peer_release[0] -> [1] on i_source_clk',
                      'source_reset_release_pipe[2] -> sink_peer_release[0] -> [1] on i_sink_clk'],
              'new_async_reset_registers': [], 'metrics': []}
    started = time.monotonic()

    def command(name, exe, words):
        argv = [str(args.modelsim_bin / exe)] + list(map(str, words))
        result['commands'].append(argv)
        proc = subprocess.run(argv, cwd=run, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, errors='replace', timeout=60)
        (run / (name + '.console.log')).write_text(proc.stdout, encoding='utf-8')
        if proc.returncode:
            raise RuntimeError(name + ' failed: ' + proc.stdout[-10000:])

    try:
        command('map', 'vmap.exe', ['-c'])
        for lib in ['work', 'ph1']:
            command(lib, 'vlib.exe', [lib])
        command('models', 'vlog.exe', ['-quiet', '-work', 'ph1', '-l', 'models.log', *models])
        command('rtl', 'vlog.exe', ['-quiet', '+define+PH1', '+incdir+' + str(include.parent),
                '-l', 'rtl.log', *sources])
        command('bench', 'vlog.exe', ['-quiet', '-sv', '+incdir+' + str(include.parent), '-l', 'bench.log', *benches])
        for top in ['r6_reset_fifo_tb', 'r6_record_reset_tb']:
            command(top, 'vsim.exe', ['-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                    'work.' + top, '-l', top + '.log', '-do', 'run -all; quit -f'])
            log = (run / (top + '.log')).read_text(errors='replace')
            assert 'RESULT: PASS ' + top in log, log[-12000:]
            result['metrics'] += [line.strip('# ') for line in log.splitlines() if 'RESULT:' in line]
        for log in run.glob('*.log'):
            if re.search(r'\*\* (Warning|Error|Fatal):', log.read_text(errors='replace')):
                raise RuntimeError('unexpected ModelSim diagnostic: ' + log.name)
        for row in identity:
            assert sha(Path(row['path'])) == row['sha256'], 'executed source drift: ' + row['path']
        result['status'] = 'PASS'
        print('\n'.join(result['metrics']))
    except Exception as error:
        result.update(status='FAIL', error=str(error))
        raise
    finally:
        result['elapsed_seconds'] = round(time.monotonic() - started, 3)
        (run / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('Results:', run / 'RESULTS.json')


if __name__ == '__main__':
    main()
