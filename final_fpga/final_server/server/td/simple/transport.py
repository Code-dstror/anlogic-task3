"""Git 1.8-compatible transport with independent, bounded network calls."""
from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path, PurePosixPath
import signal
import subprocess
import tarfile
import time

from common import COMMIT, contained, relative_path


class GitError(RuntimeError):
    pass


class Git:
    def __init__(self, path, remote, seed=None, timeout=25, push_timeout=None, stop_event=None):
        self.path = Path(path).resolve()
        self.remote = remote
        self.timeout = timeout
        self.push_timeout = push_timeout
        self.stop_event = stop_event
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not (self.path / 'HEAD').is_file():
            if seed and Path(seed).is_dir():
                self.execute(['clone', '--bare', str(Path(seed).resolve()), str(self.path)], cwd=self.path.parent,
                             timeout=300)
            else:
                self.path.mkdir(exist_ok=True)
                self.execute(['init', '--bare'], cwd=self.path)
        self.run('config', 'remote.origin.url', remote)
        self.run('config', 'gc.auto', '0')

    @staticmethod
    def environment(extra=None):
        environment = dict(os.environ)
        for key in tuple(environment):
            if key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
                       'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_CONFIG') or key.startswith('GIT_CONFIG_'):
                environment.pop(key, None)
        environment.update(LC_ALL='C', GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never',
                           GIT_AUTHOR_NAME='TD native controller', GIT_AUTHOR_EMAIL='td@localhost',
                           GIT_COMMITTER_NAME='TD native controller', GIT_COMMITTER_EMAIL='td@localhost')
        if os.name == 'posix':
            environment.pop('GIT_SSH_COMMAND', None)
            environment['GIT_SSH'] = str(Path(__file__).with_name('git_ssh.sh'))
        environment.update(extra or {})
        return environment

    @classmethod
    def execute(cls, arguments, cwd, data=None, timeout=25, allowed=(0,), environment=None, stop_event=None):
        command = ['git', '-c', 'core.autocrlf=false', '-c', 'core.eol=lf', *arguments]
        process = subprocess.Popen(command, cwd=cwd, env=cls.environment(environment),
                                   stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=os.name == 'posix')
        deadline = time.monotonic() + timeout
        try:
            while True:
                if stop_event is not None and stop_event.is_set():
                    raise InterruptedError('Controller is stopping')
                remaining = max(0, deadline - time.monotonic())
                try:
                    output, errors = process.communicate(data, timeout=min(1, remaining) if stop_event is not None else remaining)
                    break
                except subprocess.TimeoutExpired:
                    data = None
                    if time.monotonic() >= deadline:
                        raise
        except (subprocess.TimeoutExpired, InterruptedError) as error:
            try:
                if os.name == 'posix' and os.getpgid(process.pid) == process.pid:
                    os.killpg(process.pid, signal.SIGKILL)
                else:
                    process.kill()
            except ProcessLookupError:
                pass
            process.communicate()
            if isinstance(error, InterruptedError):
                raise GitError('Git operation stopped with the controller') from None
            raise GitError('Git network/operation timeout; retry on the next minute') from None
        if process.returncode not in allowed:
            raise GitError(errors.decode(errors='replace')[-3000:] or 'Git failed')
        return output

    def run(self, *arguments, data=None, allowed=(0,), environment=None, timeout=None):
        return self.execute(list(arguments), self.path, data, timeout or self.timeout, allowed, environment,
                            stop_event=self.stop_event)

    def fetch(self, branch):
        try:
            self.run('fetch', 'origin', '+refs/heads/' + branch + ':refs/td/head')
        except GitError as error:
            if "couldn't find remote ref" in str(error).lower():
                return None
            raise
        return self.run('rev-parse', 'refs/td/head').decode().strip()

    def has_commit(self, commit):
        if not isinstance(commit, str) or not COMMIT.fullmatch(commit):
            return False
        try:
            return self.run('cat-file', '-t', commit).strip() == b'commit'
        except GitError:
            return False

    def blob(self, commit, path, limit=2 * 1024**2):
        relative_path(path)
        size = int(self.run('cat-file', '-s', commit + ':' + path))
        if size > limit:
            raise ValueError('Oversized configuration/request: ' + path)
        return self.run('show', commit + ':' + path)

    def exists(self, commit, path):
        relative_path(path)
        try:
            self.run('cat-file', '-e', commit + ':' + path)
            return True
        except GitError:
            return False

    def tree(self, commit, path):
        relative_path(path)
        return self.run('rev-parse', commit + ':' + path).decode().strip()

    def files(self, commit, prefix):
        relative_path(prefix)
        return [item.decode('utf-8') for item in
                self.run('ls-tree', '-rz', '--name-only', commit, '--', prefix).split(b'\0') if item]

    def export(self, commit, project_root, destination):
        if not self.has_commit(commit):
            raise ValueError('Source commit is not fetched yet')
        relative_path(project_root, allow_dot=True)
        destination = Path(destination)
        destination.mkdir(parents=True, exist_ok=False)
        arguments = ['git', 'archive', '--format=tar', commit]
        if project_root != '.':
            arguments.extend(['--', project_root])
        process = subprocess.Popen(arguments, cwd=self.path, env=self.environment(),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        total = 0
        try:
            with tarfile.open(fileobj=process.stdout, mode='r|') as archive:
                for member in archive:
                    name = member.name.rstrip('/')
                    relative_path(name)
                    if not (member.isdir() or member.isfile()):
                        raise ValueError('Only ordinary project files/directories are exported: ' + name)
                    if any(part.endswith('_Runs') or part == '.git' for part in PurePosixPath(name).parts):
                        continue
                    total += member.size
                    if total > 8 * 1024**3:
                        raise ValueError('Project export exceeds 8 GiB')
                    target = contained(destination, name)
                    if member.isdir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with archive.extractfile(member) as source, target.open('xb') as output:
                            while body := source.read(1024**2):
                                output.write(body)
            process.stdout.close()
            errors = process.stderr.read()
            if process.wait(timeout=30):
                raise GitError(errors.decode(errors='replace')[-3000:])
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()

    def publish(self, branch, files, message):
        parent = self.fetch(branch)
        index = self.path / 'publish.index'
        index.unlink(missing_ok=True)
        environment = {'GIT_INDEX_FILE': str(index)}
        if parent:
            self.run('read-tree', parent, environment=environment)
        else:
            self.run('read-tree', '--empty', environment=environment)
        previous = {}
        if parent:
            for entry in self.run('ls-tree', '-r', '-z', parent).split(b'\0'):
                if entry:
                    metadata, name = entry.split(b'\t', 1)
                    previous[name.decode('utf-8')] = metadata.split()[2].decode()
        updates = []
        for name, body in files.items():
            relative_path(name)
            identity = hashlib.sha1(b'blob ' + str(len(body)).encode() + b'\0' + body, usedforsecurity=False).hexdigest()
            if previous.get(name) == identity:
                continue
            oid = self.run('hash-object', '-w', '--stdin', data=body).decode().strip()
            updates.append(('100644 ' + oid + '\t' + name).encode('utf-8') + b'\0')
        if updates:
            self.run('update-index', '-z', '--index-info', data=b''.join(updates), environment=environment)
        tree = self.run('write-tree', environment=environment).decode().strip()
        if parent and tree == self.run('rev-parse', parent + '^{tree}').decode().strip():
            return parent
        arguments = ['commit-tree', tree]
        if parent:
            arguments.extend(['-p', parent])
        commit = self.run(*arguments, data=(message + '\n').encode()).decode().strip()
        self.run('push', 'origin', commit + ':refs/heads/' + branch, timeout=self.push_timeout)
        return commit


def project_prefix(project, path):
    return path if project['root'] == '.' else project['root'] + '/' + path


def fingerprint(repository, commit, project):
    values = dict(project={key: value for key, value in project.items()
                           if key not in ('priority', 'max_parallel', 'memory_gib')}, trees={})
    paths = set(project['watch']) | {project['al']}
    for path in sorted(paths):
        values['trees'][path] = repository.tree(commit, project_prefix(project, path))
    from common import digest, encoded
    return digest(encoded(values))
