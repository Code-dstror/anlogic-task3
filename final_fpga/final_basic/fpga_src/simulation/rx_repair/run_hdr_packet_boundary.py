"""Focused real byte/word aligner + gearbox + HDR parser; no board/build access."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = '2528a9ff43422574561f820ac671e9cbc6d85702'
ORIGIN = 'refactor/hdr_jpeg_timing/'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--name', required=True)
    p.add_argument('--modelsim-bin', type=Path, required=True)
    p.add_argument('--baseline', action='store_true')
    a = p.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', a.name):
        p.error('unsafe run name')
    run = PROJECT / 'tmp/hdr_packet_boundary' / a.name
    run.mkdir(parents=True, exist_ok=False)
    rel = ['src_fpga/ip/vendor/anlogic_camera/phy/' + n for n in
           ['csi_rx_byte_align.v', 'csi_rx_word_align.v', 'csi_rx_word_gear_box.v']]
    rel += ['src_fpga/rtl/' + n for n in ['real_hdr_csi_word_core.v', 'real_hdr_csi_dual_word_rx.v']]
    sources = []
    for name in rel:
        if a.baseline:
            dest = run / 'fixed_inputs' / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(subprocess.check_output(['git', 'show', f'{BASE}:{ORIGIN}{name}'], cwd=REPO))
            sources.append(dest)
        else:
            sources.append(PROJECT / name)
    tb_snapshot = run / 'fixed_inputs/tb_hdr_packet_boundary.sv'
    tb_snapshot.parent.mkdir(parents=True, exist_ok=True)
    tb_snapshot.write_bytes((HERE / 'tb_hdr_packet_boundary.sv').read_bytes())
    sources.append(tb_snapshot)
    bound = sources + [Path(__file__)]
    if not a.baseline:
        bound += [PROJECT / 'src_fpga/rtl' / n for n in ['real_hdr_physical_csi_rx.v', 'real_hdr_csi_capture_stream.v']]
        receiver = bound[-2].read_text()
        assert 'hdr_packet_done && !hdr_packet_continue' in receiver
        assert receiver.count('.I_packet_done(phy_packet_done)') == 2
    identity = [dict(path=str(x), sha256=sha(x)) for x in bound]
    result = dict(status='IN_PROGRESS', baseline_commit=BASE if a.baseline else None,
                  simulation='NOT_RUN', synthesis='NOT_RUN', place_route='NOT_RUN', timing='NOT_RUN', board='NOT_RUN',
                  inputs=identity, contract='four lanes; packet headers start lane0; CRC-tail unused lanes are filler',
                  command=[sys.executable]+sys.argv, modelsim_bin=str(a.modelsim_bin),
                  td_models='NOT_USED: the focused test uses unmodified soft vendor byte/word aligners only',
                  limit='No PHY EoT input. ffffffff tail tested; ECC-valid idle/header collision cannot be distinguished.')

    def call(exe, args):
        r = subprocess.run([str(a.modelsim_bin / exe)] + list(map(str, args)), cwd=run,
                           capture_output=True, text=True, errors='replace')
        if r.returncode:
            raise RuntimeError(r.stdout[-10000:] + r.stderr[-2000:])

    try:
        call('vmap.exe', ['-c'])
        call('vlib.exe', ['work'])
        call('vmap.exe', ['work', 'work'])
        call('vlog.exe', ['-quiet', '-sv', '-l', 'compile.log'] + (['+define+BASELINE'] if a.baseline else []) + sources)
        (run / 'run.do').write_text('onerror {quit -code 1}\nrun -all\nquit -f\n')
        call('vsim.exe', ['-c', 'work.tb_hdr_packet_boundary', '-l', 'run.log', '-do', 'run.do'])
        body = (run / 'run.log').read_text(errors='replace')
        if re.search(r'\*\*\s+(Error|Fatal):', body) or 'RESULT: PASS' not in body:
            raise RuntimeError(body[-12000:])
        for row in identity:
            assert sha(Path(row['path'])) == row['sha256'], row['path']
        result.update(status='PASS', simulation='PASS', observations=[x for x in body.splitlines() if 'PASS' in x or 'TWO_FS' in x])
    except Exception as error:
        result.update(status='FAIL', simulation='FAIL', error=str(error))
        raise
    finally:
        (run / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(dict(run=str(run), status=result['status'], error=result.get('error'))))


if __name__ == '__main__':
    main()
