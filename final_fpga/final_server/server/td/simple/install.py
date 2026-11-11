"""Manual FinalShell installation and retirement of the previous controllers."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (COMMAND_BRANCH, REMOTE, RESOURCE_DEFAULTS, RETIRED_CPU_POLICY, RESULT_BRANCH, SOURCE_BRANCH, Store, TD_ENVIRONMENT, VERSION, atomic_json,
                    jobs_directory, load_config, locked, process_identity, read_json, TD_THREAD_VALUES, nonnegative_integer)


def owned_directory(path, create=False):
    path = Path(path).absolute()
    home = Path.home().resolve()
    if path.is_symlink() or not path.resolve().is_relative_to(home) or path.resolve() == home:
        raise ValueError('Use an ordinary owned subdirectory of ' + str(home))
    if create:
        path.mkdir(parents=True, exist_ok=True)
    if not path.is_dir() or path.stat().st_uid != os.getuid():
        raise ValueError('Missing or differently owned directory: ' + str(path))
    return path.resolve()


def matches_record(record):
    actual = process_identity(record.get('pid'))
    return actual and all(actual[key] == record.get(key) for key in ('pid', 'start', 'uid', 'argv'))


def retire_legacy(root, farm):
    root = Path(root)
    if not root.exists():
        return dict(state='ABSENT')
    root = owned_directory(root)
    config = read_json(root / 'config.json', {})
    farm = owned_directory(config.get('farm', farm))
    for path in (root / 'STOP', root / 'controller_stop', farm / 'PAUSE'):
        if path.is_symlink():
            raise ValueError('Unexpected symlink stop marker: ' + str(path))
        path.touch(mode=0o600, exist_ok=True)
    records = []
    for name in ('ha/primary-process.json', 'ha/reserve-process.json', 'ha/broker.json',
                 'ha/updater.json', 'controller.json'):
        record = read_json(root / name, {})
        if not matches_record(record):
            continue
        arguments = record['argv']
        entries = [Path(argument) for argument in arguments if argument.endswith('.py')]
        if len(entries) != 1 or '--root' not in arguments or str(root) not in arguments:
            raise ValueError('Unrecognized old control process; no signal sent: ' + name)
        entry = entries[0]
        if (not entry.resolve().is_relative_to(root) or
                entry.name not in ('guardian.py', 'td_operator.py', 'updater.py')):
            raise ValueError('Old control entry is outside its own service directory')
        expected = ('controller' if name == 'controller.json' else 'run' if name == 'ha/broker.json' else None)
        if expected and (entry.name != 'td_operator.py' or expected not in arguments):
            raise ValueError('Old control record is not a broker/controller command')
        records.append(record)
        os.kill(record['pid'], signal.SIGTERM)
    deadline = time.monotonic() + 20
    while any(matches_record(record) for record in records) and time.monotonic() < deadline:
        time.sleep(0.2)
    for record in records:
        if matches_record(record):
            os.kill(record['pid'], signal.SIGKILL)
    return dict(state='RETIRED', root=str(root), farm=str(farm),
                stopped_control_pids=[record['pid'] for record in records], existing_workers='KEEP_RUNNING')


def cron_update(root, legacy_root):
    environment = dict(os.environ, LC_ALL='C')
    old = subprocess.run(['crontab', '-l'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    if old.returncode not in (0, 1):
        raise ValueError(old.stderr.decode(errors='replace'))
    if old.returncode == 1 and 'no crontab' not in old.stderr.decode(errors='replace').lower():
        raise ValueError(old.stderr.decode(errors='replace'))
    lines = old.stdout.decode().splitlines()
    tag = '# td-simple-build-server'
    old_entries = (legacy_root.as_posix() + '/supervisor.py', legacy_root.as_posix() + '/ha/core/guardian.py')
    retained = [line for line in lines if tag not in line and
                not (any(entry in line for entry in old_entries) and not line.lstrip().startswith('#'))]
    command = ' '.join(shlex.quote(value) for value in
                       (sys.executable, '-I', '-B', str(root / 'app/service.py'), 'supervise', '--root', str(root)))
    retained.append('@reboot ' + command + ' >> ' + shlex.quote(str(root / 'boot.log')) + ' 2>&1 ' + tag)
    updated = subprocess.run(['crontab', '-'], input=('\n'.join(retained) + '\n').encode(),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    if updated.returncode:
        raise ValueError(updated.stderr.decode(errors='replace'))


def default_config(arguments, retirement):
    manifest = read_json(Path(__file__).with_name('projects.example.json'))
    return dict(schema=1, remote=REMOTE, source_branch=SOURCE_BRANCH, command_branch=COMMAND_BRANCH,
                result_branch=RESULT_BRANCH, project_manifest='server/td/projects.json',
                poll_seconds=60, td_root=str(arguments.td_root.resolve()), max_parallel=0, **RESOURCE_DEFAULTS,
                jobs_root=str(arguments.projects_root.resolve() / 'builds'),
                environment={name: os.environ[name] for name in TD_ENVIRONMENT if os.environ.get(name)},
                legacy_farm=retirement.get('farm'), seed_repo=str(arguments.seed_repo.resolve()) if arguments.seed_repo else None,
                fallback_projects=manifest['projects'])


def upgrade_config(config, max_parallel=None):
    config = dict(config)
    previous_policy = config.get('resource_policy_version', 0)
    if previous_policy < 2:
        for key, value in RESOURCE_DEFAULTS.items():
            config.setdefault(key, value)
        config['min_free_memory_gib'] = max(64, config['min_free_memory_gib'])
    if previous_policy < 3:
        if config.get('max_threads_per_job', 8) == 8:
            config['max_threads_per_job'] = 32
        config['resource_policy_version'] = 3
    if previous_policy < 4:
        config['cpu_growth_factor'] = 1
        config['max_total_threads'] = 64
        if config.get('max_synth_parallel', 4) == 4:
            config['max_synth_parallel'] = 8
        config['resource_policy_version'] = 4
    if previous_policy < 5:
        config['memory_per_job_gib'] = 16
        config['max_parallel'] = 0
        config['max_synth_parallel'] = 0
        config['resource_policy_version'] = 5
    if previous_policy < 6:
        if config.get('max_total_threads', 64) == 64:
            config['max_total_threads'] = 128
        if config.get('memory_per_job_gib', 16) == 16:
            config['memory_per_job_gib'] = 12
        if config.get('memory_growth_factor', 1.5) == 1.5:
            config['memory_growth_factor'] = 1.25
        config.update(resource_policy_version=6, max_td_cpu_percent=50,
                      cpu_growth_factor=1.25, start_interval_seconds=30)
    if max_parallel is not None:
        config['max_parallel'] = max_parallel
    return config


def upgrade_resource_overrides(overrides, previous_policy):
    result = {key: value for key, value in overrides.items() if key not in RETIRED_CPU_POLICY}
    if previous_policy < 4:
        result.pop('max_total_threads', None)
        if result.get('max_synth_parallel') == 4:
            result.pop('max_synth_parallel')
    if previous_policy < 5:
        result.pop('memory_per_job_gib', None)
        result.pop('max_parallel', None)
        result.pop('max_synth_parallel', None)
    if previous_policy < 6:
        for key, default in (('max_total_threads', 64), ('memory_per_job_gib', 16), ('memory_growth_factor', 1.5)):
            if result.get(key) == default:
                result.pop(key)
    return result


def drain_for_update(root, config, wait_idle=False):
    def busy():
        return any(locked(path) for path in jobs_directory(root, config).glob('*/worker.lock'))
    if busy() and not wait_idle:
        raise ValueError('TD jobs are running; no controller was stopped. Use --wait-idle to drain new starts and keep publishing until they finish')
    store = Store(root)
    was_paused = store.get('paused', False)
    running = locked(root / 'service.lock')
    store.put('paused', True)
    try:
        if running:
            requested = time.time()
            deadline = time.monotonic() + 60
            while True:
                status = read_json(root / 'status.json', {})
                if status.get('generated_at', 0) >= requested and status.get('admission') == 'PAUSED':
                    break
                if not locked(root / 'service.lock'):
                    break
                if time.monotonic() >= deadline:
                    raise ValueError('Controller did not acknowledge draining; existing programs and TD jobs are unchanged')
                time.sleep(1)
        while busy():
            if not wait_idle:
                raise ValueError('A TD job started before draining; no controller was stopped. Rerun with --wait-idle')
            print('WAITING_FOR_TD_IDLE: existing TD jobs and minute-based uploads continue; no build timeout', flush=True)
            time.sleep(60)
        return was_paused
    except BaseException:
        store.put('paused', was_paused)
        raise


def copy_application(source, application):
    for path in source.rglob('*'):
        if path.is_file() and path.suffix in ('.py', '.sh', '.json') and '__pycache__' not in path.parts:
            destination = application / path.relative_to(source)
            # This wrapper can select a server-local SSH identity for the shared account.
            if path.name == 'git_ssh.sh' and destination.is_file():
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            if path.resolve() != destination.resolve():
                shutil.copyfile(path, destination)
            os.chmod(destination, 0o700 if path.suffix == '.sh' else 0o600)


def install(arguments):
    if os.name != 'posix' or os.getuid() == 0 or sys.version_info < (3, 10):
        raise ValueError('Run with the registered Python 3.12.9 as the ordinary Linux user')
    os.umask(0o077)
    network_auth = None
    if arguments.network_auth_file:
        network_auth = read_json(arguments.network_auth_file)
        if (not isinstance(network_auth, dict) or network_auth.get('portal') != 'http://portal.example.invalid:8080/eportal/' or
                not all(isinstance(network_auth.get(key), str) and network_auth[key] for key in ('username', 'password')) or
                set(network_auth) - {'portal', 'username', 'password', 'service'}):
            raise ValueError('Invalid server-local campus authentication configuration')
    if not arguments.no_cron and shutil.which('crontab') is None:
        raise ValueError('crontab is unavailable; rerun with --no-cron for manual startup')
    root = owned_directory(arguments.root, create=True)
    os.chmod(root, 0o700)
    if root == arguments.legacy_root.resolve() or root == arguments.legacy_farm.resolve():
        raise ValueError('Install the replacement in its own td_simple directory')
    projects_root = owned_directory(arguments.projects_root, create=True)
    if projects_root == root:
        raise ValueError('Use separate project and controller directories')
    if not (arguments.td_root / 'bin/td').is_file() or not (arguments.td_root / 'bin/td.sh').is_file():
        raise ValueError('The explicit TD root is missing bin/td or bin/td.sh')
    existing_config = read_json(root / 'config.json', {})
    was_paused = drain_for_update(root, existing_config, arguments.wait_idle)
    (root / 'STOP').touch()
    deadline = time.monotonic() + 60
    while (locked(root / 'service.lock') or locked(root / 'supervisor.lock')) and time.monotonic() < deadline:
        time.sleep(1)
    if locked(root / 'service.lock') or locked(root / 'supervisor.lock'):
        raise ValueError('The existing new-service controller has not stopped; its program files are preserved')
    if any(locked(path) for path in jobs_directory(root, existing_config).glob('*/worker.lock')):
        raise ValueError('New-service jobs are running; let them finish and rerun this installer; their program files are preserved')
    retirement = (retire_legacy(arguments.legacy_root, arguments.legacy_farm) if arguments.retire_legacy
                  else read_json(root / 'legacy-retirement.json', {'state': 'NOT_REQUESTED'}))
    atomic_json(root / 'legacy-retirement.json', retirement)
    source = Path(__file__).resolve().parent
    application = root / 'app'
    if application.is_symlink():
        raise ValueError('The application directory must not be a symlink')
    application.mkdir(exist_ok=True)
    copy_application(source, application)
    previous = read_json(root / 'config.json') or default_config(arguments, retirement)
    config = upgrade_config(previous, arguments.max_parallel)
    store = Store(root)
    overrides = upgrade_resource_overrides(store.get('resource_policy_overrides', {}),
                                          previous.get('resource_policy_version', 0))
    store.put('resource_policy_overrides', overrides)
    config['td_root'] = str(arguments.td_root.resolve())
    if retirement.get('farm'):
        config['legacy_farm'] = retirement['farm']
    if arguments.seed_repo:
        config['seed_repo'] = str(arguments.seed_repo.resolve())
    config.setdefault('environment', {})
    config['environment'].update({name: os.environ[name] for name in TD_ENVIRONMENT if os.environ.get(name)})
    atomic_json(root / 'config.json', config)
    if network_auth is not None:
        atomic_json(root / 'network-auth.json', network_auth)
        os.chmod(root / 'network-auth.json', 0o600)
    load_config(root)
    Store(root).put('paused', was_paused)
    if not arguments.no_cron:
        cron_update(root, arguments.legacy_root)
    if arguments.start:
        (root / 'STOP').unlink()
        started = time.time()
        with (root / 'boot.log').open('ab') as output:
            process = subprocess.Popen([sys.executable, '-I', '-B', str(application / 'service.py'),
                                        'supervise', '--root', str(root)],
                                       stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=True, cwd=root)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            status = read_json(root / 'status.json', {})
            if status.get('generated_at', 0) >= started and status.get('controller_version') == VERSION:
                print('TD_SIMPLE_STARTED root=' + str(root) + ' poll=60s publish=60s')
                print('Admission: ' + status['admission'])
                break
            if process.poll() is not None:
                raise ValueError('Supervisor exited; see ' + str(root / 'boot.log'))
            time.sleep(1)
        else:
            raise ValueError('No new local heartbeat yet; see ' + str(root / 'boot.log'))
    else:
        print('TD_SIMPLE_INSTALLED_STOPPED root=' + str(root))
    print('Legacy: ' + retirement['state'])
    print('Controller: ' + VERSION)
    print('Result branch: ' + config['result_branch'])
    print('Uploads: continuous backlog drain; 128MiB batches; no byte-per-minute limit; idle/retry poll=60s')
    print('Native TD threads: ' + '/'.join(map(str, TD_THREAD_VALUES)) + ' (explicit values; checked before launch)')
    print('Memory budget: historical peak x growth factor, floor ' + str(overrides.get('memory_per_job_gib', config['memory_per_job_gib'])) + 'GiB; cold jobs >=16GiB')
    parallel_limit = overrides.get('max_parallel', config['max_parallel'])
    print('Resources: max_parallel=' + (str(parallel_limit) if parallel_limit else 'resource-budget') +
          ' TD_CPU<=50%, TD_RSS<=300GiB (admission targets); host CPU/free-memory checks enabled')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=(Path.home() / 'td_simple'))
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--projects-root', type=Path, default=(Path.home() / 'fpga_projects'))
    parser.add_argument('--seed-repo', type=Path)
    parser.add_argument('--legacy-root', type=Path, default=(Path.home() / 'td_operator'))
    parser.add_argument('--legacy-farm', type=Path, default=(Path.home() / 'td_farm'))
    parser.add_argument('--retire-legacy', action='store_true')
    parser.add_argument('--network-auth-file', type=Path)
    parser.add_argument('--no-cron', action='store_true')
    parser.add_argument('--start', action='store_true')
    parser.add_argument('--wait-idle', action='store_true')
    parser.add_argument('--max-parallel', type=nonnegative_integer)
    return install(parser.parse_args())


if __name__ == '__main__':
    raise SystemExit(main())
