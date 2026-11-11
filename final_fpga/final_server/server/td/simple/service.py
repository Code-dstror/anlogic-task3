"""One native TD queue, continuous artifact upload, durable local results."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (COMMIT, TERMINAL, VERSION, FileLock, Store, atomic_json, contained, digest, encoded,
                    identifier, jobs_directory, load_config, locked, project_config, read_json, relative_path)
from common import BUILD_FIELDS, RETIRED_CPU_POLICY, capabilities, job_threads, job_thread_reservation, resource_policy
from checkpoints import continuation
from flow import stage_status
from network import reconnect
from resources import ResourceMonitor
from logs import MESSAGE_SUFFIXES, finalize_logs
from transport import Git, fingerprint


CHUNK_BYTES = 8 * 1024**2
UPLOAD_BATCH_BYTES = 128 * 1024**2
UPLOAD_PUSH_TIMEOUT = 1800
LIVE_BYTES = 64 * 1024
REPORT_SUFFIXES = {'.log', '.rpt', '.timing', '.area', '.twr', '.sta', '.txt', '.csv', '.json',
                   '.prj', '.cfg', '.f', '.bit', '.sdc', '.adc', '.html', '.xml',
                   '.ts', '.qor', '.srr', '.report', '.summary', '.usage', '.status', '.params',
                   '.tcl', '.sh', '.bat'} | MESSAGE_SUFFIXES


def event_logger(root):
    logger = logging.getLogger('td-simple-' + str(root))
    if not logger.handlers:
        handler = RotatingFileHandler(Path(root) / 'service.log', maxBytes=10 * 1024**2,
                                      backupCount=4, encoding='utf-8')
        handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    return logger


def legacy_workers(farm):
    if not farm or not (Path(farm) / 'state.sqlite').is_file():
        return []
    farm = Path(farm).resolve()
    connection = sqlite3.connect((farm / 'state.sqlite').as_uri() + '?mode=ro', uri=True, timeout=5)
    try:
        rows = connection.execute("SELECT id,attempt FROM units WHERE state='RUNNING'").fetchall()
    finally:
        connection.close()
    active = []
    for name, attempt in rows:
        lease = farm / 'units' / identifier(name) / f'attempt-{int(attempt):03d}' / 'lease.lock'
        if lease.is_file() and locked(lease):
            active.append(name)
    return active


class Controller:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.config = load_config(self.root)
        self.store = Store(self.root)
        self.base_config = dict(self.config)
        overrides = {key: value for key, value in self.store.get('resource_policy_overrides', {}).items()
                     if key not in RETIRED_CPU_POLICY}
        if overrides:
            self.config.update(resource_policy(overrides))
        self.log = event_logger(self.root)
        self.stop = threading.Event()
        self.source_lock = threading.Lock()
        self.source = None
        self.commands = None
        self.publisher = None
        self.admission = 'STARTING'
        self.children = {}
        self.jobs_root = jobs_directory(self.root, self.config)
        self.jobs_root.mkdir(parents=True, exist_ok=True)
        self.resources = ResourceMonitor(self.root, self.config, self.jobs_root)
        self.resource_admission = {}
        self.waiting = {}
        self.fingerprint_cache = {}
        self.known_source_commits = set()

    def has_source_commit(self, commit):
        if commit not in self.known_source_commits:
            if not self.source.has_commit(commit):
                return False
            self.known_source_commits.add(commit)
        return True

    def compilation_fingerprint(self, commit, project):
        compiled = {key: value for key, value in project.items() if key not in ('priority', 'max_parallel', 'memory_gib')}
        cache_key = (commit, digest(encoded(compiled)))
        if cache_key not in self.fingerprint_cache:
            self.fingerprint_cache[cache_key] = fingerprint(self.source, commit, project)
        return self.fingerprint_cache[cache_key]

    def validate_project_policy(self, project, resume=None):
        for seed in project['seeds']:
            threads = job_thread_reservation(dict(project=project, seed=seed, resume=resume or {}))
            if threads > min(self.config['max_threads_per_job'], self.config['max_total_threads']):
                raise ValueError('Requested threads exceed the active server policy; adjust policy before submitting')

    def network_state(self, name, error=None):
        state = self.store.get('network.' + name, {})
        state['last_attempt'] = time.time()
        state['error'] = error
        if error is None:
            state['last_success'] = time.time()
        self.store.put('network.' + name, state)

    def source_poll(self):
        with self.source_lock:
            if self.source is None:
                self.source = Git(self.root / 'git/source.git', self.config['remote'], self.config.get('seed_repo'))
            commit = self.source.fetch(self.config['source_branch'])
            if commit is None:
                raise ValueError('The configured source branch does not exist')
            self.known_source_commits.add(commit)
            manifest = self.config['project_manifest']
            if self.source.exists(commit, manifest):
                document = json.loads(self.source.blob(commit, manifest))
                if document.get('schema') != 1 or set(document) != {'schema', 'projects'}:
                    raise ValueError('Project manifest must contain schema=1 and projects')
                projects = [project_config(item) for item in document['projects']]
            else:
                projects = self.config['fallback_projects']
            if len({item['id'] for item in projects}) != len(projects):
                raise ValueError('Duplicate project identifiers in the manifest')
            self.store.put('projects', projects)
            self.store.put('source_head', commit)
            previous = [record['spec'] for record in self.store.jobs()
                        if record['spec'].get('trigger') == 'project-push']
            for project in projects:
                if not project['enabled']:
                    continue
                key = self.compilation_fingerprint(commit, project)
                if any(spec['project']['id'] == project['id'] and
                       self.has_source_commit(spec['source_commit']) and
                       self.compilation_fingerprint(spec['source_commit'], spec['project']) == key for spec in previous):
                    continue
                self.enqueue_project('auto-' + project['id'][:40] + '-' + key[:20], commit, project, 'project-push')
            self.prepare_sources()

    def enqueue_project(self, prefix, commit, project, trigger):
        if project['target'] == 'bitgen':
            raise ValueError('Use continue --target bitgen with a completed routing job')
        self.validate_project_policy(project)
        seeds = project['seeds'][:1] if project['target'] == 'synth' else project['seeds']
        shared = project['target'] != 'synth' and len(seeds) > 1
        synthesis_id = prefix + '-syn' if shared else None
        if shared:
            synthesis_project = dict(project, target='synth', seeds=seeds[:1])
            if 'seed_threads' in synthesis_project:
                synthesis_project['seed_threads'] = {seed: threads for seed, threads in project['seed_threads'].items()
                                                     if int(seed) == seeds[0]}
            synthesis_spec = dict(id=synthesis_id, source_commit=commit, project=synthesis_project,
                                  seed=seeds[0], trigger=trigger + ':synthesis')
            self.store.enqueue(synthesis_spec)
        jobs = []
        for seed in seeds:
            job_id = prefix + '-s' + str(seed)
            spec = dict(id=job_id, source_commit=commit, project=project, seed=seed, trigger=trigger)
            if shared:
                spec.update(shared_synthesis=True, resume=dict(job=synthesis_id, checkpoint_level=1,
                            rollback_steps=0, synthesis_threads=job_threads(synthesis_spec)))
            if self.store.enqueue(spec):
                self.log.info('Queued %s at %s', job_id, commit)
            jobs.append(job_id)
        return jobs, synthesis_id

    def prepare_continuation(self, record):
        job = self.jobs_root / record['id']
        spec = record['spec']
        atomic_json(job / 'spec.json', spec)
        if spec.get('shared_synthesis'):
            parent = next((item for item in self.store.jobs() if item['id'] == spec['resume']['job']), None)
            if parent is None or parent['state'] not in TERMINAL:
                return
            try:
                if parent['state'] != 'DONE':
                    raise ValueError('Shared synthesis failed; inspect source job ' + parent['id'])
                continuation(parent, self.jobs_root, 'full', parent['spec']['seed'], {})
            except ValueError as error:
                self.store.state(record['id'], 'FAILED', str(error))
                atomic_json(job / 'result.json', dict(id=record['id'], state='FAILED', error=str(error),
                            source_commit=spec['source_commit'], resume=spec['resume'], board='NOT_RUN'))
                return
        atomic_json(job / 'READY', dict(source_commit=spec['source_commit'], resume=spec['resume']))

    def prepare_sources(self):
        for record in self.store.jobs():
            if record['state'] != 'QUEUED':
                continue
            job = self.jobs_root / record['id']
            if (job / 'READY').is_file():
                continue
            spec = record['spec']
            job.mkdir(exist_ok=True)
            atomic_json(job / 'spec.json', spec)
            if spec.get('resume'):
                self.prepare_continuation(record)
                continue
            if not self.source.has_commit(spec['source_commit']):
                self.source.run('fetch', 'origin', '+' + spec['source_commit'] + ':refs/td/requested')
            partial = job / 'source.tmp'
            try:
                if (job / 'checkout').is_dir():
                    atomic_json(job / 'READY', dict(source_commit=spec['source_commit']))
                    continue
                if partial.exists():
                    if partial.is_symlink() or partial.resolve().parent != job.resolve():
                        raise ValueError('Unexpected temporary source path')
                    shutil.rmtree(partial)
                self.source.export(spec['source_commit'], spec['project']['root'], partial)
                for attempt in range(5):
                    try:
                        partial.rename(job / 'checkout')
                        break
                    except PermissionError:
                        if os.name != 'nt' or attempt == 4:
                            raise
                        time.sleep(0.1 * (attempt + 1))
                atomic_json(job / 'READY', dict(source_commit=spec['source_commit']))
            except ValueError as error:
                self.store.state(record['id'], 'FAILED', str(error))
                atomic_json(job / 'result.json', dict(id=record['id'], state='FAILED', error=str(error),
                                                      source_commit=spec['source_commit'], board='NOT_RUN'))
                self.log.error('Source preparation failed for %s: %s', record['id'], error)

    def command_poll(self):
        if self.commands is None:
            self.commands = Git(self.root / 'git/commands.git', self.config['remote'])
        commit = self.commands.fetch(self.config['command_branch'])
        if commit is None:
            return
        for path in self.commands.files(commit, 'requests'):
            if not path.endswith('.json') or len(Path(path).parts) != 2:
                continue
            request_id = identifier(Path(path).stem)
            with self.store.connection() as connection:
                if connection.execute('SELECT 1 FROM commands WHERE id=?', (request_id,)).fetchone():
                    continue
            try:
                request = json.loads(self.commands.blob(commit, path, limit=64 * 1024))
                receipt = self.apply_command(request_id, request)
            except LookupError:
                continue
            except Exception as error:
                receipt = dict(id=request_id, state='FAILED', error=str(error), time=time.time())
            with self.store.connection() as connection:
                connection.execute('INSERT OR IGNORE INTO commands VALUES(?,?)',
                                   (request_id, encoded(receipt).decode()))
            self.log.info('Command %s: %s', request_id, receipt['state'])

    def apply_command(self, request_id, request):
        if not isinstance(request, dict) or request.get('schema') != 1 or request.get('id') != request_id:
            raise ValueError('Request schema or filename/id mismatch')
        action = request.get('action')
        allowed = {'schema', 'id', 'action'}
        fields = {'build': {'project', 'commit', *BUILD_FIELDS}, 'cancel': {'job'},
                  'continue': {'job', *BUILD_FIELDS}, 'policy': {'policy'},
                  'pause': set(), 'resume': set()}
        if action not in fields or set(request) - (allowed | fields[action]):
            raise ValueError('Use build, continue, policy, cancel, pause or resume with their documented fields')
        jobs = []
        synthesis_job = None
        if action == 'build':
            allowed |= fields['build']
            projects = self.store.get('projects')
            if projects is None:
                raise LookupError('Waiting for the first source poll')
            project = next((item for item in projects if item['id'] == request.get('project')), None)
            if project is None:
                raise ValueError('Unknown project; add it to server/td/projects.json first')
            project = copy.deepcopy(project)
            if 'td_reset' in request:
                from run_options import validate_run_options
                validate_run_options({'td_reset': request['td_reset']})
                for run in request['td_reset']:
                    project.get('td_options', {}).pop(run, None)
                    project.get('td_strategies', {}).pop(run, None)
            for field in BUILD_FIELDS:
                if field in request:
                    project[field] = request[field]
            if 'seed_threads' in project and 'seed_threads' not in request:
                project['seed_threads'] = {seed: threads for seed, threads in project['seed_threads'].items()
                                           if int(seed) in project['seeds']}
            project = project_config(project)
            commit = request.get('commit') or self.store.get('source_head')
            if not isinstance(commit, str) or not COMMIT.fullmatch(commit):
                raise ValueError('A build needs a full source commit')
            prefix = 'manual-' + request_id[:50] + '-' + digest(encoded(request))[:16]
            jobs, synthesis_job = self.enqueue_project(prefix, commit, project, request_id)
        elif action == 'continue':
            allowed |= fields['continue']
            parent = next((record for record in self.store.jobs() if record['id'] == request.get('job')), None)
            if parent is None:
                raise ValueError('Unknown source job')
            target = request.get('target', 'full')
            if target not in ('synth', 'place', 'route', 'full', 'bitgen'):
                raise ValueError('Choose synth, place, route, full or bitgen')
            changes = {key: request[key] for key in BUILD_FIELDS if key in request and key != 'target'}
            changes.setdefault('seeds', [parent['spec']['seed']])
            if 'seed_threads' not in changes:
                changes['seed_threads'] = {seed: threads for seed, threads in parent['spec']['project'].get('seed_threads', {}).items()
                                          if int(seed) in changes['seeds']}
            candidate = project_config(dict(parent['spec']['project'], **dict(changes, target=target)))
            prepared = []
            for seed in candidate['seeds'][:1] if target == 'synth' else candidate['seeds']:
                project, resume = continuation(parent, self.jobs_root, target, seed, changes)
                self.validate_project_policy(dict(project, seeds=[seed]), resume)
                job_id = 'continue-' + request_id[:45] + '-' + digest(encoded(request))[:16] + '-s' + str(seed)
                prepared.append(dict(id=job_id, source_commit=parent['spec']['source_commit'], project=project,
                                     seed=seed, trigger=request_id, resume=resume))
            for spec in prepared:
                self.store.enqueue(spec)
                job = self.jobs_root / spec['id']
                atomic_json(job / 'spec.json', spec)
                atomic_json(job / 'READY', dict(source_commit=spec['source_commit'], resume=spec['resume']))
                jobs.append(spec['id'])
        elif action == 'policy':
            allowed |= fields['policy']
            previous = {key: value for key, value in self.store.get('resource_policy_overrides', {}).items()
                        if key not in RETIRED_CPU_POLICY}
            overrides = dict(previous, **resource_policy(request.get('policy')))
            self.store.put('resource_policy_overrides', overrides)
            self.config.update(overrides)
            return dict(id=request_id, state='ACCEPTED', action=action,
                        resource_policy=dict(cpu_budget_mode='recent_peak_with_headroom' if self.resources.measured_admission else 'requested_threads',
                                             cpu_growth_factor=self.config['cpu_growth_factor'],
                                             memory_budget_mode='historical_peak_with_floor' if self.resources.measured_admission else 'fixed_per_job',
                                             parallelism_mode='resource_budget' if not self.config['max_parallel'] else 'manual_cap',
                                             **{key: self.config[key] for key in capabilities()['policy_fields']}),
                        affects='new-starts-only; running TD jobs retain their requested configuration', time=time.time())
        elif action == 'cancel':
            allowed.add('job')
            job_id = identifier(request.get('job'))
            records = self.store.jobs()
            record = next((item for item in records if item['id'] == job_id), None)
            if record is None:
                raise ValueError('Unknown job: ' + job_id)
            if record['state'] not in TERMINAL:
                job = self.jobs_root / job_id
                atomic_json(job / 'CANCEL', dict(request=request_id))
                if record['state'] == 'QUEUED':
                    self.store.state(job_id, 'CANCELLED')
            jobs = [job_id]
        elif action in ('pause', 'resume'):
            self.store.put('paused', action == 'pause')
        else:
            raise ValueError('Use build, continue, cancel, pause or resume; commands cannot contain shell/Tcl')
        if set(request) - allowed:
            raise ValueError('Unknown command fields')
        return dict(id=request_id, state='ACCEPTED', action=action, jobs=jobs, synthesis_job=synthesis_job, time=time.time())

    def reconcile(self):
        for record in self.store.jobs():
            if record['state'] not in ('STARTING', 'RUNNING'):
                continue
            job = self.jobs_root / record['id']
            result = read_json(job / 'result.json')
            if result and result['state'] in TERMINAL:
                self.store.state(record['id'], result['state'], result.get('error'))
            elif not locked(job / 'worker.lock'):
                try:
                    finalize_logs(job, 'INTERRUPTED')
                except Exception:
                    self.log.exception('Unable to preserve interrupted job logs: %s', record['id'])
                self.store.state(record['id'], 'INTERRUPTED', 'Worker exited without a result; explicit build required to retry')
        for job_id, process in tuple(self.children.items()):
            if process.poll() is not None:
                process.wait()
                self.children.pop(job_id)

    def dispatch(self):
        self.reconcile()
        records = self.store.jobs()
        for record in records:
            if record['state'] == 'QUEUED' and record['spec'].get('resume'):
                job = self.jobs_root / record['id']
                if not (job / 'READY').exists():
                    self.prepare_continuation(record)
        records = self.store.jobs()
        self.resources.sample(records)
        active = [record for record in records if record['state'] in ('STARTING', 'RUNNING')]
        self.resource_admission = self.resources.forecast(active)
        self.waiting = {}
        if self.store.get('paused', False):
            self.admission = 'PAUSED'
            return
        legacy = legacy_workers(self.config.get('legacy_farm'))
        if legacy:
            self.admission = 'WAITING_FOR_LEGACY_WORKERS: ' + ','.join(legacy)
            return
        if self.config.get('legacy_farm'):
            self.config['legacy_farm'] = None
            self.base_config['legacy_farm'] = None
            atomic_json(self.root / 'config.json', self.base_config)
        self.admission = 'IDLE'
        if any(record['state'] == 'QUEUED' and record['spec'].get('resume') and
               not (self.jobs_root / record['id'] / 'READY').exists() for record in records):
            self.admission = 'WAITING_FOR_CHECKPOINT'
        candidates = sorted(records, key=lambda record: (-record['spec']['project'].get('priority', 0),
                                                         record['created'], record['id']))
        for record in candidates:
            job = self.jobs_root / record['id']
            if record['state'] != 'QUEUED' or not (job / 'READY').is_file():
                if record['state'] == 'QUEUED':
                    self.waiting[record['id']] = 'WAITING_FOR_CHECKPOINT' if record['spec'].get('resume') else 'WAITING_FOR_SOURCE'
                continue
            available, self.admission, self.resource_admission = self.resources.allows(record, active)
            if not available:
                self.waiting[record['id']] = self.admission
                continue
            lease = FileLock(job / 'worker.lock')
            if not lease.acquire():
                continue
            try:
                self.store.state(record['id'], 'STARTING')
                command = [sys.executable, '-I', '-B', str(Path(__file__).with_name('worker.py')),
                           '--root', str(self.root), '--job', record['id'],
                           '--lease-fd', str(lease.stream.fileno())]
                with (job / 'worker.log').open('ab') as output:
                    self.children[record['id']] = subprocess.Popen(
                        command, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                        start_new_session=True, pass_fds=(lease.stream.fileno(),))
                self.resources.started()
                self.admission = 'WAITING_FOR_START_INTERVAL'
                self.waiting.pop(record['id'], None)
                self.log.info('Started %s', record['id'])
            except Exception as error:
                self.store.state(record['id'], 'FAILED', str(error))
            finally:
                lease.close()
            return

    def snapshot(self):
        records = self.store.jobs()
        jobs = []
        for record in records[-200:]:
            job = self.jobs_root / record['id']
            reserved_memory = (self.resources.estimate(record['spec'])['memory_gib']
                               if record['state'] in ('QUEUED', 'STARTING', 'RUNNING') else None)
            jobs.append(dict(id=record['id'], state=record['state'], source_commit=record['spec']['source_commit'],
                             project=record['spec']['project']['id'], seed=record['spec']['seed'],
                             threads=job_threads(record['spec']), resources=read_json(job / 'resources.json'),
                             reserved_threads=job_thread_reservation(record['spec']),
                             reserved_memory_gib=reserved_memory,
                             requested_memory_gib=record['spec']['project'].get('memory_gib'),
                             effective_config=dict(record['spec']['project'], **({'memory_gib': reserved_memory}
                                                    if reserved_memory is not None else {}),
                                                   **({'max_parallel': 0} if reserved_memory is not None and not self.config['max_parallel'] else {})),
                             requested_max_parallel=record['spec']['project'].get('max_parallel'),
                             waiting_reason=(self.waiting.get(record['id'], self.admission)
                                             if record['state'] == 'QUEUED' else None),
                             resume=record['spec'].get('resume'),
                             updated=record['updated'], error=record['error'], stages=stage_status(job / 'td.log'),
                             result=read_json(job / 'result.json')))
        return dict(schema=1, controller_version=VERSION, generated_at=time.time(), controller_pid=os.getpid(),
                    capabilities=capabilities(),
                    poll_seconds=60, publish_seconds=60, admission=self.admission,
                    upload_policy=dict(mode='continuous', rate_limit_bytes_per_second=None,
                                       batch_bytes=UPLOAD_BATCH_BYTES, chunk_bytes=CHUNK_BYTES,
                                       idle_poll_seconds=60, retry_seconds=60,
                                       push_timeout_seconds=UPLOAD_PUSH_TIMEOUT),
                    resource_policy=dict(cpu_budget_mode='recent_peak_with_headroom' if self.resources.measured_admission else 'requested_threads',
                                         cpu_growth_factor=self.config['cpu_growth_factor'],
                                         memory_budget_mode='historical_peak_with_floor' if self.resources.measured_admission else 'fixed_per_job',
                                         parallelism_mode='resource_budget' if not self.config['max_parallel'] else 'manual_cap', **{key: self.config[key] for key in
                                     ('max_parallel', 'max_td_memory_gib', 'max_host_cpu_percent',
                                      'max_threads_per_job', 'max_total_threads', 'max_synth_parallel',
                                      'memory_per_job_gib', 'memory_growth_factor',
                                      'min_free_memory_gib', 'resource_sample_seconds', 'max_td_cpu_percent', 'start_interval_seconds')}),
                    resources=self.resources.value, resource_admission=self.resource_admission,
                    source_head=self.store.get('source_head'), jobs=jobs,
                    job_counts={state: sum(record['state'] == state for record in records)
                                for state in ('QUEUED', 'STARTING', 'RUNNING', *sorted(TERMINAL))},
                    pending_uploads=self.store.get('pending_uploads', 0),
                    campus_network=self.store.get('campus_network', {}),
                    network={name: self.store.get('network.' + name, {})
                             for name in ('source', 'commands', 'publish')})

    def artifact_plan(self, budget=UPLOAD_BATCH_BYTES):
        previous = read_json(self.root / 'uploaded.json', {})
        ledger = dict(previous)
        files = {}
        pending = 0
        for record in reversed(self.store.jobs()):
            job = self.jobs_root / record['id']
            if not job.is_dir():
                continue
            candidates = {path for path in job.iterdir() if path.is_file() and
                          path.name in ('spec.json', 'result.json', 'command.json', 'td.log', 'worker.log', 'build.tcl',
                                        'resources.json', 'resources.csv', 'reused-from.json',
                                        'warnings.csv', 'warning-summary.json', 'reports.json',
                                        'thread-syn_1.params', 'thread-phy_1.params')}
            archive_root = job / 'stage-logs'
            if archive_root.is_dir() and not archive_root.is_symlink():
                candidates.update(path for path in archive_root.rglob('*') if path.is_file() and
                                  not path.is_symlink() and path.suffix.lower() in REPORT_SUFFIXES)
            paths = read_json(job / 'paths.json', {})
            if paths.get('project'):
                project_file = Path(paths['project'])
                if not project_file.resolve().is_relative_to(job.resolve()):
                    raise ValueError('Native project file left its job directory')
                if project_file.is_file():
                    candidates.add(project_file)
            if paths.get('run_root'):
                run_root = Path(paths['run_root'])
                if not run_root.resolve().is_relative_to(job.resolve()):
                    raise ValueError('Native run output left its job directory')
                candidates.update(path for path in run_root.rglob('*') if path.is_file() and
                                  not path.is_symlink() and path.suffix.lower() in REPORT_SUFFIXES)
            artifacts = []
            for path in sorted(candidates):
                if path.is_symlink():
                    continue
                if path.suffix == '.bit' and stage_status(job / 'td.log')['bitgen'] != 'DONE':
                    continue
                relative = path.relative_to(job).as_posix()
                stat = path.stat()
                if path.suffix.lower() in MESSAGE_SUFFIXES:
                    with path.open('rb') as stream:
                        stream.seek(max(0, stat.st_size - LIVE_BYTES))
                        files['jobs/' + record['id'] + '/live/' + relative] = stream.read(LIVE_BYTES)
                if path.name == 'resources.json':
                    files['jobs/' + record['id'] + '/resources.json'] = path.read_bytes()
                if path.name == 'resources.csv':
                    with path.open('rb') as stream:
                        stream.seek(max(0, stat.st_size - LIVE_BYTES))
                        files['jobs/' + record['id'] + '/live/resources.csv'] = stream.read(LIVE_BYTES)
                if record['state'] not in TERMINAL and not path.is_relative_to(archive_root) and (
                        path.suffix.lower() in MESSAGE_SUFFIXES or path.name == 'resources.csv'):
                    continue
                key = record['id'] + '/' + relative
                signature = [stat.st_size, stat.st_mtime_ns]
                known = previous.get(key, {})
                entry = dict(known) if known.get('signature') == signature else dict(signature=signature, parts=[])
                parts = list(entry['parts'])
                total_parts = (stat.st_size + CHUNK_BYTES - 1) // CHUNK_BYTES
                with path.open('rb') as stream:
                    stream.seek(len(parts) * CHUNK_BYTES)
                    while len(parts) < total_parts and budget > 0:
                        body = stream.read(min(CHUNK_BYTES, budget))
                        expected = min(CHUNK_BYTES, stat.st_size - len(parts) * CHUNK_BYTES)
                        if len(body) != expected:
                            break
                        checksum = digest(body)
                        chunk_path = 'chunks/' + checksum[:2] + '/' + checksum + '.bin'
                        files[chunk_path] = body
                        parts.append(dict(path=chunk_path, bytes=len(body), sha256=checksum))
                        budget -= len(body)
                entry.update(parts=parts, complete=len(parts) == total_parts)
                if entry['complete'] and 'sha256' not in entry:
                    checksum = hashlib.sha256()
                    with path.open('rb') as stream:
                        while body := stream.read(1024**2):
                            checksum.update(body)
                    entry['sha256'] = checksum.hexdigest()
                if path.stat().st_size != stat.st_size or path.stat().st_mtime_ns != stat.st_mtime_ns:
                    continue
                ledger[key] = entry
                pending += not entry['complete']
                inherited = record['spec'].get('resume', {}).get('job') if relative.startswith('checkout/') and stat.st_mtime < record['created'] else None
                artifacts.append(dict(path=relative, bytes=stat.st_size, mtime=stat.st_mtime, inherited_from=inherited, complete=entry['complete'],
                                      parts=parts, sha256=entry.get('sha256')))
            files['jobs/' + record['id'] + '/artifacts.json'] = encoded(dict(schema=1, files=artifacts))
        return files, ledger, pending

    def publish_poll(self):
        if self.publisher is None:
            self.publisher = Git(self.root / 'git/results.git', self.config['remote'],
                                 push_timeout=UPLOAD_PUSH_TIMEOUT, stop_event=self.stop)
        files, ledger, pending = self.artifact_plan()
        self.store.put('pending_uploads', pending)
        files['status.json'] = encoded(self.snapshot())
        with self.store.connection() as connection:
            for row in connection.execute('SELECT id,receipt FROM commands'):
                files['commands/' + row['id'] + '.json'] = row['receipt'].encode()
        self.publisher.publish(self.config['result_branch'], files, 'TD status, logs and reports')
        atomic_json(self.root / 'uploaded.json', ledger)
        return pending > 0 and any(name.startswith('chunks/') for name in files)

    def network_poll(self):
        state = reconnect(self.root)
        previous = self.store.get('campus_network', {})
        self.store.put('campus_network', dict(state, checked_at=time.time()))
        if state.get('state') != previous.get('state'):
            self.log.info('Campus network: %s', state['state'])

    def periodic(self, name, operation):
        while not self.stop.is_set():
            started = time.monotonic()
            more_uploads = False
            try:
                more_uploads = operation()
                self.network_state(name)
            except Exception as error:
                self.network_state(name, str(error))
                self.log.warning('%s: %s; retry on next minute', name, error)
            delay = 0 if name == 'publish' and more_uploads else max(0, 60 - (time.monotonic() - started))
            self.stop.wait(delay)

    def run(self):
        if os.name != 'posix' or os.getuid() == 0:
            raise ValueError('Run the service as the ordinary Linux account')
        with FileLock(self.root / 'service.lock'):
            operations = [('source', self.source_poll), ('commands', self.command_poll),
                          ('publish', self.publish_poll), ('campus', self.network_poll)]
            threads = [threading.Thread(target=self.periodic, args=operation, daemon=True) for operation in operations]
            for thread in threads:
                thread.start()
            try:
                while not (self.root / 'STOP').exists():
                    try:
                        self.dispatch()
                        atomic_json(self.root / 'status.json', self.snapshot())
                    except Exception as error:
                        self.log.exception('Local scheduler: %s', error)
                    self.stop.wait(2)
            finally:
                self.stop.set()
                for thread in threads:
                    thread.join(timeout=30)
        return 0


def supervise(root):
    root = Path(root).resolve()
    with FileLock(root / 'supervisor.lock'):
        while not (root / 'STOP').exists():
            with (root / 'supervisor.log').open('ab') as output:
                process = subprocess.Popen([sys.executable, '-I', '-B', str(Path(__file__).resolve()),
                                            'serve', '--root', str(root)],
                                           stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT)
                process.wait()
            if not (root / 'STOP').exists():
                time.sleep(5)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('serve', 'supervise'))
    parser.add_argument('--root', type=Path, required=True)
    arguments = parser.parse_args()
    os.umask(0o077)
    return supervise(arguments.root) if arguments.mode == 'supervise' else Controller(arguments.root).run()


if __name__ == '__main__':
    raise SystemExit(main())
