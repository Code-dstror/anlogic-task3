"""Local build commands, status and resumable report download through GitHub."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (COMMAND_BRANCH, RESULT_BRANCH, FileLock, atomic_json, contained, digest, encoded,
                    BUILD_FIELDS, MAX_THREADS, TD_THREAD_VALUES, identifier, project_config, read_json, resource_policy,
                    nonnegative_integer, positive_integer)
from transport import Git


def receive(repository, commit, job, output):
    document = json.loads(repository.blob(commit, 'jobs/' + identifier(job) + '/artifacts.json', limit=16 * 1024**2))
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    received = []
    pending = []
    for item in document['files']:
        target = contained(output, item['path'])
        if not item['complete']:
            pending.append(item['path'])
            continue
        if target.exists() and target.stat().st_size == item['bytes']:
            with target.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() == item['sha256']:
                    received.append(item['path'])
                    continue
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(target.name + '.part')
        checksum = hashlib.sha256()
        total = 0
        with temporary.open('wb') as stream:
            for part in item['parts']:
                body = repository.blob(commit, part['path'], limit=8 * 1024**2)
                if len(body) != part['bytes'] or digest(body) != part['sha256']:
                    raise ValueError('Download chunk differs: ' + item['path'])
                stream.write(body)
                checksum.update(body)
                total += len(body)
        if total != item['bytes'] or checksum.hexdigest() != item['sha256']:
            raise ValueError('Downloaded file differs: ' + item['path'])
        os.replace(temporary, target)
        received.append(item['path'])
    return dict(output=str(output), received=received, pending=pending)


def prepare_configuration(arguments):
    """A partial override: omitted flags preserve the registered project configuration."""
    value = read_json(arguments.config) if arguments.config is not None else {}
    if not isinstance(value, dict) or set(value) - set(BUILD_FIELDS):
        raise ValueError('--config must be a JSON object containing documented build configuration fields')
    result = dict(value)
    for field in ('target', 'threads', 'synth_threads', 'max_parallel', 'priority', 'memory_gib'):
        setting = getattr(arguments, field, None)
        if setting is not None:
            result[field] = setting
    if arguments.seeds is not None:
        result['seeds'] = arguments.seeds
    elif arguments.seed_count is not None:
        result['seeds'] = list(range(1, arguments.seed_count + 1))
    if arguments.seed_threads is not None:
        overrides = {}
        for item in arguments.seed_threads:
            seed, threads = map(int, item.split(':'))
            if (not 0 <= seed <= 2147483647 or threads not in TD_THREAD_VALUES or
                    str(seed) in overrides or 'seeds' in result and seed not in result['seeds']):
                raise ValueError('Use distinct selected SEED:THREADS entries with TD thread values 1, 2, 4, 8, 16 or 32')
            overrides[str(seed)] = threads
        result['seed_threads'] = overrides
    if arguments.td_options is not None:
        options = read_json(arguments.td_options)
        if options is None:
            raise ValueError('Missing --td-options JSON file')
        result['td_options'] = options
    validation = dict(id='configuration', root='.', al='project.al', **result)
    validation.setdefault('seeds', [int(seed) for seed in result.get('seed_threads', {'1': 8})])
    validated = project_config(validation)
    # TD 2026.2 PHY-5016 ignores seeds above 1000 even when set_param succeeds.
    # Validate new requests here so historical job records remain readable.
    if any(seed > 1000 for seed in validated['seeds']):
        raise ValueError('TD placement seeds must be within 0..1000; larger values are ignored by PHY-5016')
    return result


def needs_capabilities(request):
    return (request['action'] == 'policy' or len(request.get('seeds', [])) > 1 or
            bool(set(request) & {'synth_threads', 'max_parallel', 'priority', 'td_strategies', 'td_reset'}) or
            request.get('threads', 8) > 8 or any(threads > 8 for threads in request.get('seed_threads', {}).values()) or
            any(isinstance(value, list) for sections in request.get('td_options', {}).values()
                for settings in sections.values() for value in settings.values()))


def check_capabilities(repository, commit, request):
    if commit is None:
        raise ValueError('No server capability receipt; install the v4 controller on build-server first')
    status = json.loads(repository.blob(commit, 'status.json', limit=16 * 1024**2))
    age = time.time() - status.get('generated_at', 0)
    if not 0 <= age <= 180:
        raise ValueError('Server capability snapshot is stale; wait for a fresh status before submitting new configuration')
    supported = status.get('capabilities', {})
    old_parallel_api = not supported.get('resource_driven_parallelism', False)
    limits = request.get('policy', {}) if request['action'] == 'policy' else request
    if old_parallel_api and any(name in limits and (limits[name] == 0 or limits[name] > 8)
                               for name in ('max_parallel', 'max_synth_parallel')):
        raise ValueError('Update the controller before using resource-driven or larger parallel limits')
    seed_limit = supported.get('max_seeds')
    if seed_limit is not None and len(request.get('seeds', [])) > seed_limit:
        raise ValueError('The installed controller still has a batch seed limit; update it first')
    if supported.get('run_config_version', 0) < 1:
        raise ValueError('Server controller does not support this configuration; install v4 with FinalShell first')
    if request['action'] == 'policy':
        if set(request['policy']) - set(supported.get('policy_fields', [])):
            raise ValueError('Server does not support the requested policy fields')
    elif set(request) & set(BUILD_FIELDS) - set(supported.get('build_fields', [])):
        raise ValueError('Server does not support the requested build configuration fields')
    threads = max([request.get('threads', 1), request.get('synth_threads', 1),
                   *request.get('seed_threads', {}).values()])
    native_values = supported.get('native_thread_values', list(TD_THREAD_VALUES))
    if any(value not in native_values for value in [request.get('threads', 1), request.get('synth_threads', 1),
                                                    *request.get('seed_threads', {}).values()]):
        raise ValueError('Server TD does not support the requested native thread value')
    limits = status.get('resource_policy', {})
    if threads > min(supported.get('max_threads', 8), limits.get('max_threads_per_job', 8), limits.get('max_total_threads', 64)):
        raise ValueError('Requested threads exceed the server active policy; adjust policy before submitting')
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--cache', type=Path)
    commands = parser.add_subparsers(dest='action', required=True)
    build = commands.add_parser('build')
    build.add_argument('--project', default='hdr_jpeg')
    build.add_argument('--commit')
    build.add_argument('--target', choices=('full', 'route', 'synth', 'place'))
    build.add_argument('--config', type=Path)
    build.add_argument('--td-options', type=Path)
    build.add_argument('--threads', type=int, choices=TD_THREAD_VALUES)
    build.add_argument('--synth-threads', type=int, choices=TD_THREAD_VALUES)
    build.add_argument('--max-parallel', type=nonnegative_integer)
    build.add_argument('--priority', type=int)
    seeds = build.add_mutually_exclusive_group()
    seeds.add_argument('--seeds', type=int, nargs='+')
    seeds.add_argument('--seed-count', type=positive_integer)
    build.add_argument('--seed-threads', nargs='+', metavar='SEED:THREADS')
    build.add_argument('--memory-gib', type=float)
    build.add_argument('--request-id')
    advance = commands.add_parser('continue')
    advance.add_argument('--job', required=True)
    advance.add_argument('--target', choices=('synth', 'place', 'route', 'full', 'bitgen'))
    advance.add_argument('--config', type=Path)
    advance.add_argument('--threads', type=int, choices=TD_THREAD_VALUES)
    advance.add_argument('--synth-threads', type=int, choices=TD_THREAD_VALUES)
    advance.add_argument('--max-parallel', type=nonnegative_integer)
    advance.add_argument('--priority', type=int)
    advance_seeds = advance.add_mutually_exclusive_group()
    advance_seeds.add_argument('--seeds', type=int, nargs='+')
    advance_seeds.add_argument('--seed-count', type=positive_integer)
    advance.add_argument('--seed-threads', nargs='+', metavar='SEED:THREADS')
    advance.add_argument('--td-options', type=Path)
    advance.add_argument('--memory-gib', type=float)
    advance.add_argument('--request-id')
    policy = commands.add_parser('policy')
    policy.add_argument('--file', required=True, type=Path)
    policy.add_argument('--request-id')
    cancel = commands.add_parser('cancel')
    cancel.add_argument('--job', required=True)
    cancel.add_argument('--request-id')
    for name in ('pause', 'resume'):
        command = commands.add_parser(name)
        command.add_argument('--request-id')
    commands.add_parser('status')
    download = commands.add_parser('receive')
    download.add_argument('--job', required=True)
    download.add_argument('--output', type=Path, required=True)
    receipt = commands.add_parser('receipt')
    receipt.add_argument('--request', required=True)
    arguments = parser.parse_args()
    repo = arguments.repo.resolve()
    cache = arguments.cache or repo / 'server/td/local/simple-client'
    cache.mkdir(parents=True, exist_ok=True)
    remote = Git.execute(['config', '--get', 'remote.origin.url'], repo).decode().strip()
    if remote.removesuffix('.git').lower() not in ('https://github.com/owner/repository',
                                             'git@github.com:owner/repository'):
        raise ValueError('Use the registered fpga-project repository')
    with FileLock(cache / 'client.lock'):
        if arguments.action in ('status', 'receive', 'receipt'):
            repository = Git(cache / 'results.git', remote)
            commit = repository.fetch(RESULT_BRANCH)
            if commit is None:
                raise ValueError('No simple-service results published yet; install/start it on build-server first')
            if arguments.action == 'status':
                result = json.loads(repository.blob(commit, 'status.json', limit=16 * 1024**2))
                result['snapshot_age_seconds'] = round(time.time() - result['generated_at'], 1)
            elif arguments.action == 'receipt':
                result = json.loads(repository.blob(commit, 'commands/' + identifier(arguments.request) + '.json'))
            else:
                result = receive(repository, commit, arguments.job, arguments.output)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        request_id = arguments.request_id or time.strftime('%Y%m%dT%H%M%SZ-', time.gmtime()) + uuid.uuid4().hex[:12]
        identifier(request_id)
        request = dict(schema=1, id=request_id, action=arguments.action)
        if arguments.action in ('build', 'continue'):
            request.update(prepare_configuration(arguments))
            if arguments.action == 'build':
                commit = arguments.commit or Git.execute(['rev-parse', 'HEAD'], repo).decode().strip()
                request.update(project=arguments.project, commit=commit)
            else:
                request['job'] = identifier(arguments.job)
        elif arguments.action == 'policy':
            request['policy'] = resource_policy(read_json(arguments.file))
        elif arguments.action == 'cancel':
            request['job'] = identifier(arguments.job)
        if needs_capabilities(request):
            results = Git(cache / 'results.git', remote)
            check_capabilities(results, results.fetch(RESULT_BRANCH), request)
        path = cache / 'outbox' / (request_id + '.json')
        previous = read_json(path)
        if previous is not None and previous != request:
            raise ValueError('Request id already contains another command')
        atomic_json(path, request)
        print('Request id: ' + request_id, flush=True)
        repository = Git(cache / 'commands.git', remote)
        published = repository.publish(COMMAND_BRANCH, {'requests/' + request_id + '.json': encoded(request)},
                                       'TD ' + arguments.action + ' ' + request_id)
        atomic_json(cache / 'sent' / (request_id + '.json'), dict(request=request, github_commit=published))
        print('PUBLISHED; check receipt --request ' + request_id + ' after the next server poll')
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
