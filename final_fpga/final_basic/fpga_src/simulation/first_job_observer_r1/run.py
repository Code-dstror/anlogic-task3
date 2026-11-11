"""Extract the original TOP first-job monitor and qualify its local and UART behavior."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    a = ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,47}', a.name):
        ap.error('unique lowercase run name required')
    run = ROOT / 'tmp/first_job_observer_r1' / a.name
    run.mkdir(parents=True, exist_ok=False)
    top = ROOT / 'src_fpga/rtl/anlogic2026.v'
    original = top.read_bytes()
    begin = b'            // First stereo job watch. STOP leaves the last live sample intact;'
    end = b'        end else begin:g_no_status_uart'
    if original.count(begin) != 1 or original.count(end) != 1:
        raise ValueError('TOP extraction anchors are not unique')
    monitor = original[original.index(begin):original.index(end)]
    if monitor.count(b'uart_status_observer #(') != 1 or monitor.count(b'always @(posedge') != 2:
        raise ValueError('unexpected production monitor boundary')
    included = run / 'production_job_watch.vh'
    included.write_bytes(monitor)
    sources = [ROOT / 'src_fpga/rtl' / (name + '.v') for name in
               ('reset_release_sync', 'uart_observer_snapshot', 'cfg_diag_snapshot', 'uart_status_observer')]
    bench = HERE / 'tb.sv'
    decoder_path = ROOT / 'tools/uart_observer.py'
    paths = [top, included, *sources, bench, decoder_path, Path(__file__).resolve()]
    before = [{'path': p.as_posix(), 'sha256': sha(p)} for p in paths]
    identity = dict(inputs=before, extraction=dict(start_anchor=begin.decode(), end_anchor=end.decode(),
                    start_byte=original.index(begin), end_byte=original.index(end),
                    exact_bytes=True, sha256=sha(included)),
                    fixture='explicit independent DFI/PIX domain inputs; common-time values advanced logically, no business RTL stimulus/root-cause claim',
                    simulation_overrides=dict(UART_DIV=8, SNAPSHOT_TIMEOUT_CYCLES=64, READONLY_UART_REPORT_CYCLES=2048))
    (run / 'SOURCE_START.json').write_text(json.dumps(identity, indent=2) + '\n')
    q = dict(status='RUNNING', simulation='RUNNING', modelsim_bin=a.modelsim_bin.as_posix(),
             synthesis='NOT_RUN', physical='NOT_RUN', timing='NOT_RUN', board='NOT_RUN',
             production_top_simulation='NOT_RUN_EXTRACTED_MONITOR_ONLY')
    started = time.monotonic()

    def command(words):
        with (run / 'commands.jsonl').open('a') as out:
            out.write(json.dumps([str(w) for w in words]) + '\n')
        result = subprocess.run([str(w) for w in words], cwd=run, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, errors='replace', timeout=90)
        with (run / 'console.log').open('a', encoding='utf-8') as out:
            out.write(result.stdout)
        if result.returncode:
            raise RuntimeError(f'{words[0].name} exit {result.returncode}: {result.stdout[-5000:]}')

    try:
        ms = a.modelsim_bin.resolve()
        command([ms / 'vlib.exe', 'work'])
        command([ms / 'vlog.exe', '-sv', '-quiet', f'+incdir+{run.as_posix()}', '-l', 'compile.log', *sources, bench])
        command([ms / 'vsim.exe', '-c', '-l', 'run.log', 'work.tb_first_job_observer', '-do', 'run -all; quit -f'])
        logs = (run / 'compile.log').read_text(errors='replace') + (run / 'run.log').read_text(errors='replace')
        if re.search(r'\*\* (Warning|Error|Fatal):', logs):
            raise RuntimeError('unclassified ModelSim diagnostic')
        match = re.search(r'RESULT: PASS TOP_JOB_WATCH[^\r\n]+', logs)
        if not match:
            raise RuntimeError('missing self-checking pass marker')
        spec = importlib.util.spec_from_file_location('actual_job_uart_decoder', decoder_path)
        decoder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(decoder)
        wire = (run / 'top_job_uart.bin').read_bytes()
        parser = decoder.FrameDecoder()
        frames = parser.feed(wire)
        jobs = [row for row in frames if row.get('frame_type') == 'job']
        marks = re.findall(r'WIRE_MARK phase=(\w+) round=(\d+) expected_fresh=(\d+) dfi=([0-9a-fA-F]{56}) pix=([0-9a-fA-F]{56})', logs)
        if len(marks) != 4 or len(wire) != len(jobs)*161 or len(frames) != len(jobs)*3:
            raise AssertionError('wire/phase coverage mismatch')
        selected = {}
        for phase, ordinal, fresh, dfi_hex, pix_hex in marks:
            row = jobs[int(ordinal)-1]
            if row['fresh_mask'] != int(fresh) or row['reset_n_mask'] != 3:
                raise AssertionError(f'{phase}: freshness/reset mask mismatch')
            packet = b'DJ\x01\x01\x44\x00' + row['sequence'].to_bytes(2, 'little') + bytes((int(fresh), 3)) + int(dfi_hex, 16).to_bytes(28, 'little') + int(pix_hex, 16).to_bytes(28, 'little')
            packet += decoder.crc16(packet).to_bytes(2, 'little')
            if decoder.decode_job_frame(packet) != row:
                raise AssertionError(f'{phase}: transmitted pages do not match original TOP monitor fields')
            selected[phase] = row
        old = selected['STOP_STALLED']
        assert old['dfi']['sequence'] == 0x12345678 and old['dfi']['generation'] == 0x10203040
        assert old['dfi']['camera'] == 1 and old['dfi']['slot'] == 2 and old['dfi']['stalled'] == 1
        assert old['pixel']['stalled'] == 1 and old['pixel']['first_admission'] == 0
        for phase in ('DFI_REOPEN_PIX_STOPPED', 'PIX_RESUMED_OLD_FREEZE'):
            row = selected[phase]
            assert row['dfi']['sequence'] == 0xdeadbeef and row['dfi']['generation'] == 0x55667788
            assert row['dfi']['stalled'] == 0 and row['dfi']['watching'] == 1
            assert {k:v for k,v in row['pixel'].items() if k!='hdr_sof_seen'} == {
                k:v for k,v in old['pixel'].items() if k!='hdr_sof_seen'}
        final = selected['NEW_RUN_SUCCESS']
        assert final['dfi']['watching'] == 0 and final['dfi']['stalled'] == 0
        assert final['pixel']['stalled'] == 0 and final['pixel']['first_admission'] == 1
        assert final['pixel']['admission_state'] == 1 and final['pixel']['ticket_flags'] == 14
        (run / 'DECODED_PHASES.json').write_text(json.dumps(selected, indent=2) + '\n')
        after = [{'path': p.as_posix(), 'sha256': sha(p)} for p in paths]
        (run / 'SOURCE_END.json').write_text(json.dumps(after, indent=2) + '\n')
        if before != after or included.read_bytes() != top.read_bytes()[identity['extraction']['start_byte']:identity['extraction']['end_byte']]:
            q['status'] = 'STALE'
            raise RuntimeError('source or byte-exact extraction changed during test')
        q.update(status='PASS', simulation='PASS', result=match.group(0), warnings=0,
                 exact_top_monitor_extract='PASS', input_hash_recheck='PASS', wire_decode='PASS',
                 wire_bytes=len(wire), uart_rounds=len(jobs), selected_phases=list(selected),
                 logical_pixel_stall_elapsed_ns=109440512, logical_refreshed_dfi_stall_elapsed_ns=117440512,
                 freeze_scope='first identity/control fields freeze; per-run job/FS/RAW counters remain live until STOP',
                 production_elapsed_time_simulation='LOGICAL_COMMON_TIME_INPUTS')
        print(q['result'], flush=True)
    except Exception as error:
        q.update(status=q['status'] if q['status'] == 'STALE' else 'FAIL', simulation='FAIL', error=str(error))
        raise
    finally:
        q['elapsed_seconds'] = round(time.monotonic() - started, 3)
        (run / 'RESULTS.json').write_text(json.dumps(q, indent=2) + '\n')
        print(json.dumps({'run': run.as_posix(), 'status': q['status'], 'elapsed_seconds': q['elapsed_seconds']}), flush=True)


if __name__ == '__main__':
    main()
