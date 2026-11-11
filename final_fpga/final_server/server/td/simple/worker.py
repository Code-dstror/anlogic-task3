"""An independent job process survives controller and network restarts."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import FileLock, Store, atomic_json, identifier, jobs_directory, load_config, process_identity, read_json
from flow import build_script, stage_status, timing_status
from checkpoints import copy_checkpoint
from logs import finalize_logs
from reports import collect_reports


def execute(root, job_id, lease_fd=None):
    root = Path(root).resolve()
    config = load_config(root)
    store = Store(root)
    job = jobs_directory(root, config) / identifier(job_id)
    lease = FileLock(job / 'worker.lock')
    if lease_fd is not None:
        lease.stream = os.fdopen(lease_fd, 'a+b')
    with lease:
        spec = read_json(job / 'spec.json')
        started = time.time()
        atomic_json(job / 'worker.json', process_identity(os.getpid()))
        store.state(job_id, 'RUNNING')
        result = dict(id=job_id, source_commit=spec['source_commit'], seed=spec['seed'],
                      project=spec['project'], started=started, state='FAILED', board='NOT_RUN', simulation='NOT_RUN')
        if spec.get('resume'):
            result['resume'] = spec['resume']
        try:
            if (job / 'CANCEL').exists():
                result['state'] = 'CANCELLED'
            else:
                if spec.get('resume') and not (job / 'checkout').exists():
                    copy_checkpoint(jobs_directory(root, config), job, spec)
                project_file, run_root = build_script(job / 'checkout', spec, job / 'build.tcl')
                atomic_json(job / 'paths.json', dict(project=str(project_file), run_root=str(run_root)))
                command = [sys.executable, '-I', '-B', str(Path(__file__).parent / 'tools/run_td.py'),
                           str(job / 'build.tcl'), '--td-root', config['td_root'],
                           '--workdir', str(project_file.parent), '--log', str(job / 'td.log'),
                           '--record', str(job / 'td-process.json'), '--cancel', str(job / 'CANCEL')]
                inherited = ()
                if os.name == 'posix':
                    command += ['--lease-fd', str(lease.stream.fileno())]
                    inherited = (lease.stream.fileno(),)
                atomic_json(job / 'command.json', command)
                environment = dict(os.environ, **config.get('environment', {}))
                process = subprocess.Popen(command, stdin=subprocess.DEVNULL, pass_fds=inherited, env=environment)
                exit_code = process.wait()
                text = (job / 'td.log').read_text(encoding='utf-8', errors='replace')
                cancelled = (job / 'CANCEL').exists()
                result['state'] = ('CANCELLED' if cancelled else
                                   'DONE' if exit_code == 0 and 'TD_SIMPLE_COMPLETE' in text else 'FAILED')
                selected_run = 'syn_1' if spec['project']['target'] == 'synth' else 'phy_1'
                result.update(exit_code=exit_code, stages=stage_status(job / 'td.log'),
                              timing=timing_status(run_root, selected_run, started))
                result['reports'] = collect_reports(job, spec, run_root, project_file, started)
                if result['state'] == 'FAILED':
                    result['error'] = 'TD did not complete normally; see td.log and the native run logs'
        except Exception as error:
            result['error'] = str(error)
        try:
            result['log_capture'] = finalize_logs(job, result['state'])
        except Exception as error:
            result['log_capture'] = dict(state='ERROR', error=str(error), warning_inventory_complete=False)
        result.setdefault('stages', stage_status(job / 'td.log'))
        result.setdefault('timing', {'state': 'NOT_RUN'})
        result['finished'] = time.time()
        atomic_json(job / 'result.json', result)
        store.state(job_id, result['state'], result.get('error'))
        return 0 if result['state'] == 'DONE' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--job', required=True)
    parser.add_argument('--lease-fd', type=int)
    arguments = parser.parse_args()
    return execute(arguments.root, arguments.job, arguments.lease_fd)


if __name__ == '__main__':
    raise SystemExit(main())
