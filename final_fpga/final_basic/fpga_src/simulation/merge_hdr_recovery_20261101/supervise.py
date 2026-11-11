"""One HDR recovery, bounded by the original six-hour deadline and a new preflight."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import os
import subprocess
import sys
import time
import traceback

import psutil
from binding import authorities, atomic, read, sha, verify

EXT = Path(__file__).resolve().parent
PROJECT = EXT.parents[2]
REGISTRY = PROJECT / 'tmp/extended_hdr_recovery_20261101'
ORIGINAL_START=1793512651.7473004
ORIGINAL_DEADLINE=1793534251.7473004
STATE = REGISTRY / 'STATE.json'
PYTHON = Path(sys.executable).resolve()
TD = 'D:/App/TD_Release_2026.2.210.850'
MODELSIM = 'D:/App/modelsim/win64'
CASES = ('hdr',)
TERMINAL = {'PASS', 'PASS_PREFLIGHT', 'FAIL', 'TIMEOUT', 'SOURCE_DRIFT', 'WORKER_LOST', 'PLAN_TIMEOUT'}


def utc(epoch=None):
    return datetime.fromtimestamp(time.time() if epoch is None else epoch, timezone.utc).isoformat()


def identity(pid):
    try:
        process = psutil.Process(pid)
        created = process.create_time()
        result = dict(pid=pid, create_time_epoch=created, create_time_utc=utc(created))
        for key, function in [('name', process.name), ('command', process.cmdline)]:
            try:
                result[key] = function()
            except psutil.AccessDenied:
                result[key] = None
        return result
    except psutil.NoSuchProcess:
        return None


def alive(record):
    if not record:
        return False
    current = identity(record['pid'])
    return bool(current and abs(current['create_time_epoch'] - record['create_time_epoch']) < 0.01)


def children(record):
    if not alive(record):
        return []
    try:
        return [row for process in psutil.Process(record['pid']).children(recursive=True)
                if (row := identity(process.pid))]
    except psutil.NoSuchProcess:
        return []


def kill_owned(record):
    if not alive(record):
        return
    owned = children(record) + [record]
    for row in reversed(owned):
        if alive(row):
            try:
                psutil.Process(row['pid']).terminate()
            except psutil.NoSuchProcess:
                pass
    pending = [psutil.Process(row['pid']) for row in owned if alive(row)]
    _, remaining = psutil.wait_procs(pending, timeout=4)
    for process in remaining:
        row = next(row for row in owned if row['pid'] == process.pid)
        if alive(row):
            process.kill()


def commands(case, phase, attempt):
    stem = f'{case}_recovery_r{attempt}'
    name = stem + ('_preflight' if phase == 'PREFLIGHT' else '_full')
    run = REGISTRY / name
    base = [str(PYTHON), '-B', '-u']
    mode = 'hdr' if case == 'hdr' else 'sdr'
    case_dir = EXT / ('hdr_startup' if case == 'hdr' else 'sdr_he')
    simulation = base + [str(case_dir / 'run.py'), '--mode', mode, '--name', name,
                         '--readonly-uart', '--td-root', TD, '--modelsim-bin', MODELSIM]
    if phase == 'PREFLIGHT':
        return [dict(stage='PREFLIGHT', command=simulation + ['--compile-only'],
                     result=str(run / 'qualification.json'), expected='PASS_ELABORATION_ONLY')], run
    oracle = base + [str(case_dir / 'oracle.py'), '--run-directory', str(run),
                     '--output-directory', str(run / 'oracle')]
    if case == 'hdr':
        oracle += ['--mode', 'hdr']
    return [dict(stage='SIMULATION', command=simulation, result=str(run / 'qualification.json'),
                 expected='PASS_HDR_MAIN' if case == 'hdr' else 'PASS_SDR_MAIN'),
            dict(stage='ORACLE', command=oracle, result=str(run / 'oracle/RESULTS.json'), expected='PASS')], run


def worker(case, phase, attempt, plan_deadline, lock_sha):
    bound = authorities(lock_sha)
    folder = REGISTRY / 'workers' / f'{case}_{phase.lower()}_r{attempt}'
    folder.mkdir(parents=True, exist_ok=False)
    path = folder / 'STATE.json'
    started = time.time()
    deadline = min(started + 10800, plan_deadline)
    stages, run = commands(case, phase, attempt)
    record = dict(schema=1, case=case, phase=phase, attempt=attempt, status='PREPARING',
                  stage='VERIFY_START', worker=identity(os.getpid()), started_epoch=started,
                  started_utc=utc(started), deadline_epoch=deadline, deadline_utc=utc(deadline),
                  wall_limit_seconds=10800, state_path=str(path), run_directory=str(run),
                  test_lock_sha256=lock_sha, source_seal_sha256=bound['source_seal_sha256'],
                  commands=stages, events=[], synthesis='NOT_RUN', physical='NOT_RUN', board='NOT_RUN')
    process = None

    def save():
        record.update(heartbeat_utc=utc(), updated_epoch=time.time(), elapsed_seconds=round(time.time()-started, 3))
        atomic(path, record)

    save()
    try:
        verify(bound, folder / 'INPUTS_START.json')
        for index, stage in enumerate(stages):
            verify(bound, folder / f'{index}_{stage["stage"]}_INPUTS_START.json')
            record.update(stage=stage['stage'], status='PREPARING' if phase == 'PREFLIGHT' else 'RUNNING',
                          stage_started_utc=utc())
            record['events'].append(dict(event='START', stage=stage['stage'], time=utc(), command=stage['command']))
            log = folder / (stage['stage'].lower() + '.console.log')
            record['current_log'] = str(log)
            env = dict(os.environ, HDR_MERGE_TEST_LOCK_SHA256=lock_sha)
            with log.open('w', encoding='utf-8') as output:
                process = subprocess.Popen(stage['command'], cwd=PROJECT, stdout=output,
                                           stderr=subprocess.STDOUT, env=env,
                                           creationflags=subprocess.CREATE_NO_WINDOW)
                record['current_process'] = identity(process.pid)
                save()
                while process.poll() is None:
                    if time.time() >= deadline:
                        kill_owned(record['current_process'])
                        raise TimeoutError('Complete case including oracle exceeded10800 seconds')
                    tree = children(record['current_process'])
                    record['child_processes'] = tree
                    record['modelsim_processes'] = [row for row in tree if (row.get('name') or '').lower() in {'vsim.exe', 'vsimk.exe'}]
                    with log.open('rb') as stream:
                        stream.seek(max(0, log.stat().st_size-4096))
                        record['last_output'] = stream.read().decode('utf-8', errors='replace').splitlines()[-8:]
                    save()
                    time.sleep(2)
                exit_code = process.returncode
            verify(bound, folder / f'{index}_{stage["stage"]}_INPUTS_END.json')
            record['events'].append(dict(event='EXIT', stage=stage['stage'], time=utc(), exit_code=exit_code, log=str(log)))
            if exit_code:
                raise RuntimeError(f'{stage["stage"]} exit{exit_code}; retain {log}')
            result = read(stage['result'])
            if result.get('status') != stage['expected']:
                raise RuntimeError(f'{stage["stage"]} status {result.get("status")} != {stage["expected"]}')
            record[stage['stage'].lower() + '_result'] = dict(path=stage['result'], sha256=sha(stage['result']), status=result['status'])
            save()
        record.update(status='PASS_PREFLIGHT' if phase == 'PREFLIGHT' else 'PASS', stage='COMPLETE')
    except Exception as error:
        record.update(status='TIMEOUT' if isinstance(error, TimeoutError) else 'FAIL', error=str(error), traceback=traceback.format_exc())
        if process and process.poll() is None:
            kill_owned(record.get('current_process'))
    finally:
        try:
            verify(bound, folder / 'INPUTS_END.json')
        except Exception as error:
            record.update(status='SOURCE_DRIFT', source_end_error=str(error))
        record.update(finished_utc=utc(), child_processes=[], modelsim_processes=[])
        save()
    return 0 if record['status'] in {'PASS', 'PASS_PREFLIGHT'} else 1


def supervise(mode, lock_sha):
    bound = authorities(lock_sha)
    verify(bound)
    if time.time() >= ORIGINAL_DEADLINE:raise RuntimeError('Original six-hour campaign deadline has expired')
    REGISTRY.mkdir(parents=True, exist_ok=True)
    if STATE.exists():
        state = read(STATE)
        if state['test_lock_sha256'] != lock_sha:
            raise RuntimeError('Retained campaign lock differs; do not adopt or overwrite')
        if alive(state.get('controller')):
            print(dict(status='ALREADY_RUNNING', controller=state['controller']), flush=True)
            return 0
    else:
        if mode != 'preflight':
            raise RuntimeError('Run --preflight before --launch')
        state = dict(schema=1, test_lock_sha256=lock_sha, source_seal_sha256=bound['source_seal_sha256'],
                     max_parallel=1, case_wall_limit_seconds=10800, total_wall_limit_seconds=21600,
                     phase='PREFLIGHT', preflight_started_epoch=time.time(),
                     plan_deadline_epoch=min(time.time()+10800, ORIGINAL_DEADLINE), cases={case:dict(case=case, status='QUEUED', attempt=1) for case in CASES})
    if mode == 'launch':
        if state.get('status') != 'READY_TO_LAUNCH':
            raise RuntimeError('Actual HDR compile/elaboration gate must PASS before launch')
        state['preflight_cases'] = state['cases']
        for case, entry in state['preflight_cases'].items():
            result = entry['preflight_result']
            if entry['status'] != 'PASS_PREFLIGHT' or sha(result['path']) != result['sha256'] or read(result['path'])['status'] != 'PASS_ELABORATION_ONLY':
                raise RuntimeError('Preflight result drift: ' + case)
        state.update(phase='FULL', plan_started_epoch=ORIGINAL_START, recovery_started_epoch=time.time(), plan_deadline_epoch=ORIGINAL_DEADLINE,
                     cases={case:dict(case=case, status='QUEUED', attempt=1) for case in CASES})
    elif mode == 'preflight' and state.get('phase') != 'PREFLIGHT':
        raise RuntimeError('Campaign already launched; preflight cannot replace live/full results')
    state.update(controller=identity(os.getpid()), registry_path=str(STATE), status='PREPARING')
    atomic(STATE, state)
    held = []
    try:
        while True:
            for case, entry in list(state['cases'].items()):
                if entry.get('state_path') and Path(entry['state_path']).exists():
                    state['cases'][case] = read(entry['state_path'])
                entry = state['cases'][case]
                if entry['status'] not in TERMINAL | {'QUEUED'} and entry.get('worker') and not alive(entry['worker']):
                    entry.update(status='WORKER_LOST', error='Worker PID/create-time no longer alive; no success inferred')
            active = sum(entry['status'] not in TERMINAL | {'QUEUED'} and alive(entry.get('worker')) for entry in state['cases'].values())
            for case, entry in state['cases'].items():
                if entry['status'] == 'QUEUED' and active < 1:
                    phase = state['phase']
                    attempt = entry['attempt']
                    path = REGISTRY / 'workers' / f'{case}_{phase.lower()}_r{attempt}/STATE.json'
                    log = REGISTRY / f'{case}_{phase.lower()}_r{attempt}.worker.log'
                    output = log.open('a', encoding='utf-8')
                    held.append(output)
                    command = [str(PYTHON), '-B', '-u', str(Path(__file__).resolve()), '--worker', case,
                               '--phase', phase, '--attempt', str(attempt), '--plan-deadline', str(state['plan_deadline_epoch']),
                               '--lock-sha256', lock_sha]
                    process = subprocess.Popen(command, cwd=PROJECT, stdout=output, stderr=subprocess.STDOUT,
                                               creationflags=subprocess.CREATE_NO_WINDOW)
                    entry.update(status='PREPARING', worker=identity(process.pid), state_path=str(path),
                                 launch_command=command, worker_log=str(log))
                    active += 1
            state.update(active_count=active, heartbeat_utc=utc(), updated_epoch=time.time())
            statuses = [entry['status'] for entry in state['cases'].values()]
            if all(status == ('PASS_PREFLIGHT' if state['phase'] == 'PREFLIGHT' else 'PASS') for status in statuses):
                state['status'] = 'READY_TO_LAUNCH' if state['phase'] == 'PREFLIGHT' else 'PASS'
            elif all(status in TERMINAL for status in statuses):
                state['status'] = 'COMPLETE_WITH_FAILURE'
            else:
                state['status'] = 'RUNNING' if state['phase'] == 'FULL' else 'PREFLIGHT_RUNNING'
            atomic(STATE, state)
            if state['status'] in {'READY_TO_LAUNCH', 'PASS', 'COMPLETE_WITH_FAILURE'}:
                break
            if time.time() >= state['plan_deadline_epoch']:
                for entry in state['cases'].values():
                    if entry['status'] not in TERMINAL:
                        kill_owned(entry.get('worker'))
                        entry.update(status='PLAN_TIMEOUT', error='Six-hour total plan bound')
                state['status'] = 'COMPLETE_WITH_FAILURE'
                atomic(STATE, state)
                break
            time.sleep(2)
    finally:
        for output in held:
            output.close()
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group()
    for name in ('preflight', 'launch', 'resume', 'status'):
        mode.add_argument('--' + name, action='store_true')
    ap.add_argument('--lock-sha256', required=True)
    ap.add_argument('--worker', choices=CASES)
    ap.add_argument('--phase', choices=['PREFLIGHT', 'FULL'])
    ap.add_argument('--attempt', type=int, default=1)
    ap.add_argument('--plan-deadline', type=float)
    args = ap.parse_args()
    if args.status:
        import json
        if not STATE.exists():
            print(json.dumps(dict(status='NOT_RUN', state_path=str(STATE))))
            return 0
        state = read(STATE)
        if state['test_lock_sha256'] != args.lock_sha256:
            raise RuntimeError('Requested status lock differs from retained campaign')
        print(json.dumps(dict(status=state['status'], phase=state['phase'], heartbeat_utc=state.get('heartbeat_utc'),
                              controller=state.get('controller'), controller_alive=alive(state.get('controller')),
                              cases={case:{key:entry.get(key) for key in ['status','stage','worker','modelsim_processes','run_directory','current_log','elapsed_seconds','error']}
                                     for case,entry in state['cases'].items()}), indent=2))
        return 0
    if args.worker:
        return worker(args.worker, args.phase, args.attempt, args.plan_deadline, args.lock_sha256)
    selected = 'preflight' if args.preflight else 'launch' if args.launch else 'resume' if args.resume else None
    if selected is None:
        ap.error('Select --preflight, --launch, --resume or --status')
    return supervise(selected, args.lock_sha256)


if __name__ == '__main__':
    raise SystemExit(main())
