"""Run the first-job control matrix against current candidate RTL and TD FIFO models."""
from pathlib import Path
import argparse
import hashlib
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
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    a = ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,47}', a.name):
        ap.error('name must be a unique lowercase run identifier')
    run = ROOT / 'tmp/first_job_r1' / a.name
    run.mkdir(parents=True, exist_ok=False)
    td = a.td_root.resolve()
    ms = a.modelsim_bin.resolve()
    models = [td / 'sim_release' / p for p in (
        'common/al_phy_glbl.v', 'ph1/ph1_logic_eram.v', 'ph1/ph1_logic_fifo.v',
        'ph1/ph1_logic_ramfifo.v', 'ph1/ph1_phy_eram.v', 'ph1/ph1_phy_fifoctrl.v')]
    sources = [td / 'sim_release/ph1/ph1_phy_gsr.v'] + [ROOT / p for p in (
        'src_fpga/ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        'src_fpga/ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v',
        'src_fpga/ip/camera_control_fifo_40x512/camera_control_fifo_40x512.v',
        'src_fpga/rtl/control_fifo_40x512.v', 'src_fpga/rtl/reset_release_sync.v',
        'src_fpga/rtl/control_message_fifo_ip.v', 'src_fpga/rtl/raw_pair_replay_scheduler.v',
        'src_fpga/rtl/raw_job_ticket_context_cdc.v', 'src_fpga/rtl/raw_pair_processing_context_ticket.v',
        'src_fpga/rtl/single_slot_credit_cdc.v', 'src_fpga/rtl/jpeg_frame_admission.v')]
    sources.append(HERE / 'tb_first_job.sv')
    paths = models + sources + [Path(__file__).resolve()]
    identity = [{'path': p.as_posix(), 'sha256': sha(p)} for p in paths]
    (run / 'SOURCE_START.json').write_text(json.dumps(identity, indent=2) + '\n')
    q = dict(status='RUNNING', td_root=td.as_posix(), modelsim_bin=ms.as_posix(),
             simulation='RUNNING', synthesis='NOT_RUN', physical='NOT_RUN', timing='NOT_RUN', board='NOT_RUN',
             scope='real normal scheduler/ticket control FIFO/credit/admission; owner, DDR, ISP pixels, JPEG arithmetic and B are BFMs')
    started = time.monotonic()

    def command(words):
        (run / 'commands.jsonl').open('a').write(json.dumps([str(w) for w in words]) + '\n')
        result = subprocess.run([str(w) for w in words], cwd=run, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, errors='replace', timeout=90)
        with (run / 'console.log').open('a', encoding='utf-8') as out:
            out.write(result.stdout)
        if result.returncode:
            raise RuntimeError(f'{words[0].name} exit {result.returncode}: {result.stdout[-5000:]}')

    try:
        command([ms / 'vlib.exe', 'work'])
        command([ms / 'vlib.exe', 'ph1'])
        command([ms / 'vmap.exe', 'work', 'work'])
        command([ms / 'vmap.exe', 'ph1', 'ph1'])
        command([ms / 'vlog.exe', '-quiet', '-work', 'ph1', '-l', 'models.log'] + models)
        command([ms / 'vlog.exe', '-sv', '-quiet', '+define+PH1', '-work', 'work', '-l', 'compile.log'] + sources)
        command([ms / 'vsim.exe', '-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                 'work.tb_first_job', '-l', 'run.log', '-do', 'run -all; quit -f'])
        body = (run / 'run.log').read_text(errors='replace')
        all_logs = '\n'.join((run / p).read_text(errors='replace') for p in ('models.log', 'compile.log', 'run.log'))
        if re.search(r'\*\* (Warning|Error|Fatal):', all_logs):
            raise RuntimeError('unclassified ModelSim diagnostic; inspect raw logs')
        match = re.search(r'RESULT: PASS FIRST_JOB_CONTROL[^\r\n]+', body)
        if not match:
            raise RuntimeError('missing self-checking PASS marker')
        after = [{'path': p.as_posix(), 'sha256': sha(p)} for p in paths]
        (run / 'SOURCE_END.json').write_text(json.dumps(after, indent=2) + '\n')
        if after != identity:
            q['status'] = 'STALE'
            raise RuntimeError('test input changed while running')
        q.update(status='PASS', simulation='PASS', result=match.group(0), warnings=0,
                 input_hash_recheck='PASS', board_root_cause='NOT_ESTABLISHED')
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
