"""Seal actual candidate production bytes; test repeated RX/RT faults in both modes."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compact(body):
    return re.sub(r'\s+', '', re.sub(r'/\*.*?\*/|//[^\n]*', '', body, flags=re.S))


def expression(body, name):
    found = re.search(r'\bassign\s+' + re.escape(name) + r'\s*=\s*(.*?);', body, re.S)
    if not found:
        raise RuntimeError('missing production trace assignment: ' + name)
    return compact(found.group(1))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source-root', type=Path, required=True)
    ap.add_argument('--output-root', type=Path, required=True)
    ap.add_argument('--name', required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        ap.error('new lowercase run name required')
    source_root = args.source_root.resolve()
    run = args.output_root.resolve() / args.name
    run.mkdir(parents=True, exist_ok=False)
    result = dict(status='IN_PROGRESS', simulation='IN_PROGRESS', source_root=str(source_root),
                  inputs=[], commands=[], structural_checks=[], modes=[],
                  synthesis='NOT_RUN', place_route='NOT_RUN', timing='NOT_RUN',
                  bitgen='NOT_RUN', electrical='NOT_RUN', board='NOT_RUN',
                  production_edits=0, server_actions=0, board_actions=0,
                  scope='Digital deserialized bytes, real alignment, parser, RX snapshot and RT RAM/SYS mailbox; settled calibration. No full UART serialization or electrical/board claim.')
    started = time.monotonic()

    def freeze(src, relative):
        dest = run / 'inputs' / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(src.read_bytes())
        result['inputs'].append(dict(original=str(src.resolve()), path=str(dest), sha256=sha(dest)))
        return dest

    def call(cwd, label, exe, words, timeout=60):
        argv = [str(args.modelsim_bin / exe), *map(str, words)]
        row = dict(argv=argv, cwd=str(cwd), timeout_seconds=timeout)
        result['commands'].append(row)
        proc = subprocess.run(argv, cwd=cwd, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, errors='replace', timeout=timeout,
                              creationflags=subprocess.CREATE_NO_WINDOW)
        row['exit_code'] = proc.returncode
        (cwd / (label + '.console.log')).write_text(proc.stdout, encoding='utf-8')
        if proc.returncode:
            raise RuntimeError(label + ': ' + proc.stdout[-6000:])

    try:
        names = ['rtl/csi_rx_byte_align_observed.v', 'rtl/csi_rx_word_align_observed.v',
                 'ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v',
                 'rtl/physical_csi_word_core.v', 'rtl/rx_first_loss_trace.v', 'rtl/cfg_diag_snapshot.v']
        sources = [freeze(source_root / 'src_fpga' / name, Path(name)) for name in names]
        receiver = freeze(source_root / 'src_fpga/rtl/real_hdr_physical_csi_rx.v', Path('bound/real_hdr_physical_csi_rx.v'))
        observer = freeze(source_root / 'src_fpga/rtl/uart_status_observer.v', Path('bound/uart_status_observer.v'))
        bench = freeze(HERE / 'tb_trace_recovery.sv', Path('testbench/tb_trace_recovery.sv'))
        freeze(Path(__file__), Path('testbench/run_trace_recovery.py'))
        real = receiver.read_text(errors='replace')
        test = bench.read_text(errors='replace')
        for name in ('o_rx_trace_sample', 'o_rx_trace_cohort_n', 'o_rx_trace_enable'):
            if expression(real, name) != expression(test, name):
                raise RuntimeError('TB/production trace expression mismatch: ' + name)
            result['structural_checks'].append(dict(assignment=name, status='PASS'))
        if 'cfg_diag_snapshot#(.DATA_WIDTH(128))u_snapshot(' not in compact(observer.read_text(errors='replace')):
            raise RuntimeError('production RX mailbox type/width changed')
        core = sources[3].read_text(errors='replace')
        if 'parameterintegerFRAME_RESYNC_ENABLE=0' not in compact(core):
            raise RuntimeError('strict default no longer zero')
        result['structural_checks'] += [dict(check='actual_RX_cfg_diag_snapshot_DATA_WIDTH_128', status='PASS'),
                                        dict(check='strict_default_FRAME_RESYNC_ENABLE_0', status='PASS')]
        for mode, define, expected in [('recovery', ['+define+RECOVERY_TRACE'], 1), ('strict_default', [], 0)]:
            work = run / mode
            work.mkdir()
            row = dict(mode=mode, expected_recovery=expected, explicit_override=bool(define), status='IN_PROGRESS')
            result['modes'].append(row)
            call(work, 'version', 'vsim.exe', ['-version'])
            call(work, 'vmap', 'vmap.exe', ['-c'])
            call(work, 'vlib', 'vlib.exe', ['work'])
            call(work, 'compile', 'vlog.exe', ['-quiet', '-sv', *define, '-l', 'compile.log', *sources, bench])
            (work / 'run.do').write_text('onerror {quit -code 1}\nonbreak {quit -code 1}\nrun -all\nquit -code 0 -f\n', encoding='utf-8')
            call(work, 'run', 'vsim.exe', ['-c', 'work.tb_trace_recovery', '-gEXPECT_RECOVERY=' + str(expected),
                                         '-l', 'run.log', '-do', 'run.do'])
            body = (work / 'run.log').read_text(errors='replace')
            if 'RESULT: PASS' not in body or re.search(r'\*\*\s+(Error|Fatal):', body):
                raise RuntimeError(mode + ': ' + body[-8000:])
            first = re.findall(r'TRACE_FIRST index=(\d+) mailbox=([0-9a-fA-F]{80})', body)
            final = re.findall(r'TRACE_FINAL index=(\d+) mailbox=([0-9a-fA-F]{80})', body)
            if len(first) != 40 or first != final or [int(item[0]) for item in first] != list(range(40)):
                raise RuntimeError(mode + ': incomplete or changed 40-slot chronological readback')
            slots = [dict(index=int(index), mailbox=word, sample=word[16:], generation=int(word[12:16], 16)) for index, word in first]
            (work / 'TRACE_READBACK.json').write_text(json.dumps(slots, indent=2) + '\n', encoding='utf-8')
            warnings = [line for p in (work / 'compile.log', work / 'run.log')
                        for line in p.read_text(errors='replace').splitlines() if '** Warning:' in line]
            if warnings:
                raise RuntimeError(mode + ': unexpected warning: ' + warnings[0])
            row.update(status='PASS', slots_unchanged=40, warnings=0,
                       observations=[line.strip('# ') for line in body.splitlines() if 'CASE ' in line or 'RESULT: PASS' in line])
        for item in result['inputs']:
            if sha(Path(item['original'])) != item['sha256'] or sha(Path(item['path'])) != item['sha256']:
                raise RuntimeError('original/compiled input changed: ' + item['original'])
        result.update(status='PASS', simulation='PASS', input_hashes_stable=True)
    except Exception as exc:
        result.update(status='FAIL', simulation='FAIL', error=str(exc))
        raise
    finally:
        result['elapsed_seconds'] = round(time.monotonic() - started, 3)
        (run / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(dict(run=str(run), status=result['status'], error=result.get('error'))))


if __name__ == '__main__':
    main()
