"""Stop named controlled TD jobs when an old runner has accepted but ignored cancel."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import TERMINAL, atomic_json, contained, identifier, jobs_directory, read_json
from process_control import same_process, signal_session


def stop_job(root, job_id):
    root = Path(root).resolve()
    config = read_json(root / 'config.json')
    job = contained(jobs_directory(root, config), identifier(job_id))
    if not job.is_dir():
        raise ValueError('Unknown owned job: ' + job_id)
    result = read_json(job / 'result.json', {})
    if result.get('state') in TERMINAL:
        return dict(job=job_id, state='ALREADY_TERMINAL', result=result['state'])
    record = read_json(job / 'td-process.json', {}).get('process')
    current = same_process(record)
    if not current:
        return dict(job=job_id, state='ALREADY_EXITED_OR_IDENTITY_CHANGED')
    script = str(job / 'build.tcl')
    if script not in record.get('argv', []) or not (job / 'build.tcl').is_file():
        raise ValueError('TD identity is not bound to this job build.tcl')
    if not (job / 'CANCEL').exists():
        atomic_json(job / 'CANCEL', dict(reason='User-requested controlled-job stop before update'))
    changed = current.get('argv') != record.get('argv')
    sent = signal_session(record, signal.SIGTERM)
    deadline = time.monotonic() + 10
    while same_process(record) and time.monotonic() < deadline:
        time.sleep(.2)
    if same_process(record):
        signal_session(record, signal.SIGKILL)
    return dict(job=job_id, state='STOP_SENT' if sent else 'ALREADY_EXITED',
                pid=record['pid'], argv_changed_after_launch=changed,
                results='Preserved; original worker records terminal state and archives logs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--jobs', required=True, nargs='+')
    arguments = parser.parse_args()
    if os.name != 'posix' or os.getuid() == 0:
        raise ValueError('Run as the ordinary server user on Linux')
    for job_id in arguments.jobs:
        print(json.dumps(stop_job(arguments.root, job_id), ensure_ascii=False), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
