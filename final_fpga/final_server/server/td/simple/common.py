"""Small shared primitives for the native TD controller."""
from __future__ import annotations

from contextlib import contextmanager
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import sqlite3
import time
import uuid


REMOTE = 'git@github.com:OWNER/REPOSITORY.git'
VERSION = '2026.11.10-measured-admission-v6.6-sanitized'
SOURCE_BRANCH = 'feature/fpga-pipeline'
COMMAND_BRANCH = 'codex/td-commands-build-server-simple'
RESULT_BRANCH = 'codex/td-results-build-server-simple'
IDENTIFIER = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,119}\Z')
COMMIT = re.compile(r'[0-9a-f]{40}\Z')
TERMINAL = {'DONE', 'FAILED', 'CANCELLED', 'INTERRUPTED'}
TD_ENVIRONMENT = {'LM_LICENSE_FILE', 'ANLOGIC_LICENSE_FILE', 'TD_LICENSE_FILE',
                  'SNPSLMD_LICENSE_FILE', 'LD_LIBRARY_PATH'}
MAX_THREADS = 32
TD_THREAD_VALUES = (1, 2, 4, 8, 16, 32)
BUILD_FIELDS = ('target', 'threads', 'seeds', 'seed_threads', 'synth_threads', 'max_parallel',
                'priority', 'memory_gib', 'td_options', 'td_strategies', 'td_reset')
POLICY_LIMITS = {
    'max_parallel': (0, None, int), 'max_threads_per_job': (1, MAX_THREADS, int),
    'max_total_threads': (1, 256, int), 'max_synth_parallel': (0, None, int),
    'max_td_cpu_percent': (1, 50, float),
    'max_td_memory_gib': (1, 300, float),
    'max_host_cpu_percent': (1, 100, float), 'min_free_memory_gib': (64, 300, float),
    'memory_per_job_gib': (1, 300, float), 'memory_growth_factor': (1, 4, float),
}
RETIRED_CPU_POLICY = {'max_cpu_percent', 'cpu_growth_factor', 'unknown_td_threads'}
RESOURCE_DEFAULTS = dict(resource_policy_version=6, resource_sample_seconds=20, start_interval_seconds=30,
                         max_td_cpu_percent=50,
                         max_cpu_percent=50, max_td_memory_gib=300, max_host_cpu_percent=85,
                         min_free_memory_gib=64, memory_per_job_gib=12, memory_growth_factor=1.25,
                         cpu_growth_factor=1.25, max_threads_per_job=MAX_THREADS, max_total_threads=128,
                         max_synth_parallel=0, unknown_td_threads=16)


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode('utf-8')


def atomic_bytes(path, body):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with temporary.open('xb') as stream:
            stream.write(body)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        if os.name == 'posix':
            descriptor = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
    finally:
        temporary.unlink(missing_ok=True)


def atomic_json(path, value):
    atomic_bytes(path, encoded(value))


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8-sig'))
    except FileNotFoundError:
        return default


def digest(body):
    return hashlib.sha256(body).hexdigest()


def identifier(value):
    if not isinstance(value, str) or not IDENTIFIER.fullmatch(value):
        raise ValueError('Invalid identifier: ' + repr(value))
    return value


def relative_path(value, allow_dot=False):
    if allow_dot and value == '.':
        return value
    if (not isinstance(value, str) or not value or value.startswith('/') or
            '\\' in value or ':' in value or any(ord(character) < 32 for character in value) or
            any(part in ('', '.', '..') for part in value.split('/'))):
        raise ValueError('Expected a relative path inside the project: ' + repr(value))
    return PurePosixPath(value).as_posix()


def contained(root, relative):
    relative_path(relative)
    root = Path(root).resolve()
    candidate = root / relative
    if not candidate.resolve().is_relative_to(root):
        raise ValueError('Path leaves the owned directory: ' + relative)
    return candidate


def project_config(value):
    allowed = {'id', 'root', 'al', 'watch', 'enabled', 'target', 'threads', 'seeds', 'seed_threads',
               'memory_gib', 'td_options', 'synth_threads', 'max_parallel', 'priority',
               'td_strategies', 'td_reset'}
    if not isinstance(value, dict) or set(value) - allowed:
        raise ValueError('Unknown project configuration fields')
    result = dict(value)
    result['id'] = identifier(result['id'])
    result['root'] = relative_path(result['root'], allow_dot=True)
    result['al'] = relative_path(result['al'])
    if not result['al'].endswith('.al'):
        raise ValueError('A project must name its native .al file')
    result.setdefault('watch', ['src_fpga', 'fpga_prj'])
    if not isinstance(result['watch'], list) or not result['watch']:
        raise ValueError('A project needs at least one watched path')
    result['watch'] = [relative_path(item) for item in result['watch']]
    result.setdefault('enabled', True)
    result.setdefault('target', 'full')
    result.setdefault('threads', 8)
    result.setdefault('seeds', [1])
    if type(result['enabled']) is not bool or result['target'] not in ('full', 'route', 'synth', 'place', 'bitgen'):
        raise ValueError('Invalid project enable flag or target')
    validate_threads(result['threads'], 'threads')
    if 'synth_threads' in result:
        validate_threads(result['synth_threads'], 'synth_threads')
    if 'max_parallel' in result and (type(result['max_parallel']) is not int or result['max_parallel'] < 0):
        raise ValueError('Project max_parallel must be nonnegative; zero means resource-budget admission')
    if 'priority' in result and (type(result['priority']) is not int or not -100 <= result['priority'] <= 100):
        raise ValueError('priority must be an integer between -100 and 100; higher starts first')
    if (not isinstance(result['seeds'], list) or not result['seeds'] or
            any(type(seed) is not int or not 0 <= seed <= 2147483647 for seed in result['seeds']) or
            len(set(result['seeds'])) != len(result['seeds'])):
        raise ValueError('Use distinct nonnegative seed identifiers')
    overrides = result.get('seed_threads', {})
    if (not isinstance(overrides, dict) or any(str(seed) not in {str(item) for item in result['seeds']} or
            type(threads) is not int or threads not in TD_THREAD_VALUES for seed, threads in overrides.items())):
        raise ValueError('seed_threads maps selected seeds to TD thread values 1, 2, 4, 8, 16 or 32')
    if 'seed_threads' in result:
        result['seed_threads'] = {str(seed): threads for seed, threads in overrides.items()}
    if ('memory_gib' in result and (type(result['memory_gib']) not in (int, float) or
            not math.isfinite(result['memory_gib']) or not 1 <= result['memory_gib'] <= 300)):
        raise ValueError('memory_gib must be a finite reservation between 1 and 300 GiB')
    from run_options import validate_run_options
    validate_run_options(result)
    return result


def validate_threads(value, field='threads'):
    if type(value) is not int or value not in TD_THREAD_VALUES:
        raise ValueError(field + ' must be a TD native thread value: 1, 2, 4, 8, 16 or 32; auto is not a fixed reservation')
    return value


def nonnegative_integer(value):
    result = int(value)
    if result < 0:
        raise ValueError('Use a nonnegative integer; zero removes the optional job-count cap')
    return result


def positive_integer(value):
    result = nonnegative_integer(value)
    if not result:
        raise ValueError('Use a positive integer')
    return result


def job_threads(spec):
    physical = spec['project'].get('seed_threads', {}).get(str(spec['seed']), spec['project']['threads'])
    if spec['project'].get('target') == 'synth':
        return spec['project'].get('synth_threads', physical)
    return physical


def job_thread_reservation(spec):
    threads = job_threads(spec)
    if not spec.get('resume', {}).get('checkpoint_level'):
        return max(threads, spec['project'].get('synth_threads', threads))
    return threads


def resource_policy(value):
    if not isinstance(value, dict) or not value or set(value) - POLICY_LIMITS.keys():
        raise ValueError('Policy must contain only documented resource admission fields')
    for key, setting in value.items():
        lower, upper, kind = POLICY_LIMITS[key]
        if (type(setting) not in (int, float) or not math.isfinite(setting) or
                kind is int and type(setting) is not int or setting < lower or upper is not None and setting > upper):
            raise ValueError(f'{key} must be {kind.__name__} >= {lower}' + (f' and <= {upper}' if upper is not None else ''))
    return dict(value)


def capabilities():
    return dict(run_config_version=1, build_fields=list(BUILD_FIELDS), max_threads=MAX_THREADS,
                native_thread_values=list(TD_THREAD_VALUES), thread_parameter_readback=True,
                memory_budget_mode='historical_peak_with_floor',
                max_seeds=None, resource_driven_parallelism=True, policy_fields=list(POLICY_LIMITS),
                cpu_budget_mode='recent_peak_with_headroom', checkpoint_path_normalization=True,
                reports_profile='timing-diagnostics-v2',
                targets=['synth', 'place', 'route', 'full', 'bitgen'])


def load_config(root):
    config = read_json(Path(root) / 'config.json')
    if not isinstance(config, dict) or config.get('remote') != REMOTE:
        raise ValueError('Configure the enrolled fpga-project SSH remote')
    for key in ('source_branch', 'command_branch', 'result_branch'):
        branch = config[key]
        if (not isinstance(branch, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_./-]*', branch) or
                '..' in branch or branch.endswith('/') or '//' in branch):
            raise ValueError('Invalid Git branch')
    if config.get('poll_seconds') != 60:
        raise ValueError('This service polls and publishes every 60 seconds, all day')
    if type(config.get('max_parallel')) is not int or config['max_parallel'] < 0:
        raise ValueError('max_parallel must be nonnegative; zero means resource-budget admission')
    for key, default in RESOURCE_DEFAULTS.items():
        config.setdefault(key, default)
        if (type(config[key]) not in (int, float) or not math.isfinite(config[key]) or
                key == 'max_synth_parallel' and type(config[key]) is not int or
                (config[key] < 0 if key == 'max_synth_parallel' else config[key] <= 0)):
            raise ValueError('Invalid resource setting: ' + key)
    for key, maximum in (('max_cpu_percent', 50), ('max_td_cpu_percent', 50), ('max_td_memory_gib', 300),
                         ('max_host_cpu_percent', 100), ('max_threads_per_job', MAX_THREADS),
                         ('max_total_threads', 256)):
        if config[key] > maximum:
            raise ValueError(key + ' exceeds the service resource ceiling')
    if config['memory_growth_factor'] < 1 or config['cpu_growth_factor'] < 1 or config['resource_sample_seconds'] != 20:
        raise ValueError('Use growth factors >= 1 and a 20-second resource sample interval')
    relative_path(config['project_manifest'])
    config['fallback_projects'] = [project_config(item) for item in config['fallback_projects']]
    if set(config.get('environment', {})) - TD_ENVIRONMENT:
        raise ValueError('Only TD/license library environment settings may be restored at boot')
    return config


def jobs_directory(root, config):
    return Path(config.get('jobs_root', Path(root) / 'jobs')).resolve()


class FileLock:
    def __init__(self, path):
        self.path = Path(path)
        self.stream = None

    def acquire(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        stream = self.path.open('a+b')
        try:
            if os.name == 'posix':
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            else:
                import msvcrt
                if self.path.stat().st_size == 0:
                    stream.write(b'0')
                    stream.flush()
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            stream.close()
            return False
        self.stream = stream
        return True

    def close(self):
        if self.stream is not None:
            if os.name != 'posix':
                import msvcrt
                self.stream.seek(0)
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_UNLCK, 1)
            self.stream.close()
            self.stream = None

    def __enter__(self):
        if self.stream is not None:
            return self
        if not self.acquire():
            raise RuntimeError('Already running: ' + str(self.path))
        return self

    def __exit__(self, *unused):
        self.close()


def locked(path):
    lock = FileLock(path)
    available = lock.acquire()
    lock.close()
    return not available


def process_identity(pid):
    if os.name != 'posix' or type(pid) is not int or pid <= 1:
        return None
    folder = Path('/proc') / str(pid)
    try:
        fields = (folder / 'stat').read_text().rsplit(')', 1)[1].split()
        if fields[0] == 'Z' or folder.stat().st_uid != os.getuid():
            return None
        return dict(pid=pid, start=fields[19], uid=folder.stat().st_uid,
                    argv=(folder / 'cmdline').read_bytes().rstrip(b'\0').decode(errors='replace').split('\0'))
    except (OSError, IndexError):
        return None


def alive(record):
    return bool(record and process_identity(record.get('pid')) == record)


class Store:
    def __init__(self, root):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        with self.connection() as connection:
            connection.execute('PRAGMA journal_mode=WAL')
            connection.executescript('''
                CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS jobs(
                    id TEXT PRIMARY KEY, spec TEXT NOT NULL, state TEXT NOT NULL,
                    created REAL NOT NULL, updated REAL NOT NULL, error TEXT);
                CREATE TABLE IF NOT EXISTS commands(
                    id TEXT PRIMARY KEY, receipt TEXT NOT NULL);
            ''')

    @contextmanager
    def connection(self):
        connection = sqlite3.connect(self.root / 'state.sqlite', timeout=30)
        connection.row_factory = sqlite3.Row
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def get(self, key, default=None):
        with self.connection() as connection:
            row = connection.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone()
        return json.loads(row[0]) if row else default

    def put(self, key, value):
        with self.connection() as connection:
            connection.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', (key, encoded(value).decode()))

    def jobs(self):
        with self.connection() as connection:
            return [dict(row, spec=json.loads(row['spec'])) for row in
                    connection.execute('SELECT * FROM jobs ORDER BY created,id')]

    def state(self, job, state, error=None):
        with self.connection() as connection:
            connection.execute('UPDATE jobs SET state=?,updated=?,error=? WHERE id=?',
                               (state, time.time(), error, job))

    def enqueue(self, spec):
        identifier(spec['id'])
        if not COMMIT.fullmatch(spec['source_commit']):
            raise ValueError('A build requires a fixed 40-character source commit')
        with self.connection() as connection:
            inserted = connection.execute('INSERT OR IGNORE INTO jobs VALUES(?,?,?,?,?,NULL)',
                                          (spec['id'], encoded(spec).decode(), 'QUEUED', time.time(), time.time()))
        return inserted.rowcount != 0
