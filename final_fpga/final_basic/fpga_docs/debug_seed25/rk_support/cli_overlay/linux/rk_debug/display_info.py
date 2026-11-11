"""Bounded explicit modetest connector/plane query; no modeset or installation.

Production is Linux-only. The caller supplies a trusted modetest executable;
hashing its file records identity, not authenticity or a sandbox. Listing DRM
resources proves neither successful scanout nor physical HDMI presentation.
"""
from __future__ import annotations

import hashlib
import math
import os
from pathlib import Path
import re
import selectors
import stat
import subprocess
import sys
import time


MAX_OUTPUT_BYTES = 4 * 1024 * 1024
MAX_EXECUTABLE_BYTES = 32 * 1024 * 1024
_DRIVER = re.compile(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}\Z')


def _identity(executable):
    if not isinstance(executable, (str, Path)):
        raise ValueError('explicit absolute modetest executable required')
    path = Path(executable)
    if (not path.is_absolute() or len(str(path)) > 4096 or '\0' in str(path)
            or path.resolve(strict=True) != path.absolute()):
        raise ValueError('executable must be an absolute path without aliases')
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= MAX_EXECUTABLE_BYTES:
        raise ValueError('executable must be a bounded regular non-link file')
    hasher = hashlib.sha256()
    consumed = 0
    with path.open('rb', buffering=0) as stream:
        opened = os.fstat(stream.fileno())
        if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise ValueError('executable changed before identity read')
        while True:
            block = stream.read(min(65536, MAX_EXECUTABLE_BYTES - consumed + 1))
            if not block:
                break
            consumed += len(block)
            if consumed > MAX_EXECUTABLE_BYTES:
                raise ValueError('executable exceeded identity byte bound')
            hasher.update(block)
        after = os.fstat(stream.fileno())
    if (consumed != before.st_size or (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns)
            != (after.st_size, after.st_mtime_ns, after.st_ctime_ns)):
        raise ValueError('executable changed during identity read')
    return dict(path=str(path), bytes=consumed, sha256=hasher.hexdigest())


def inspect_display(executable, driver_name='rockchip', *, timeout_s, max_output_bytes=65536):
    """Run exactly ``ABS_MODETEST -M DRIVER -c -p`` with bounded binary capture.

    timeout_s is the whole helper observation budget, including a reserved
    min(0.1s,20%) kill/reap interval. Output bytes are a combined stdout+stderr
    ceiling; at most one extra byte is read to detect overflow. Nonblocking pipe
    reads/select avoid an unbounded communicate() or orphaned reader threads.
    A helper not reaped by the deadline is explicitly UNKNOWN_HELPER_PENDING.
    """
    if (type(timeout_s) not in (int, float) or not math.isfinite(timeout_s)
            or not 0.01 <= timeout_s <= 30):
        raise ValueError('timeout_s must be explicit, finite and in [0.01,30]')
    if type(max_output_bytes) is not int or not 1 <= max_output_bytes <= MAX_OUTPUT_BYTES:
        raise ValueError('combined max_output_bytes must be in [1,4194304]')
    if type(driver_name) is not str or not _DRIVER.fullmatch(driver_name):
        raise ValueError('driver_name must be one bounded option-free driver identifier')
    if sys.platform != 'linux':
        raise RuntimeError('actual display-info queries require Linux; Windows supports fake-process tests only')
    identity = _identity(executable)
    command = [identity['path'], '-M', driver_name, '-c', '-p']
    start = time.monotonic()
    deadline = start + timeout_s
    cleanup_reserve = min(0.1, timeout_s * .2)
    query_deadline = deadline - cleanup_reserve
    streams = {}
    captured = {'stdout': bytearray(), 'stderr': bytearray()}
    total = 0
    reason = error = cleanup_error = None
    process = selector = None
    returncode = None
    helper_reaped = False
    kill_requested = False
    try:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
            shell=False, close_fds=True, start_new_session=True)
        selector = selectors.DefaultSelector()
        for name in ('stdout', 'stderr'):
            stream = getattr(process, name)
            if stream is None:
                raise RuntimeError('helper capture pipe is missing')
            streams[name] = stream
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
        while selector.get_map():
            remaining = query_deadline - time.monotonic()
            if remaining <= 0:
                reason = 'TIMEOUT'
                break
            ready = selector.select(remaining)
            for key, _ in ready:
                try:
                    block = os.read(key.fileobj.fileno(), min(4096, max_output_bytes - total + 1))
                except BlockingIOError:
                    continue
                if not block:
                    selector.unregister(key.fileobj)
                    continue
                available = max_output_bytes - total
                captured[key.data].extend(block[:available])
                total += min(len(block), available)
                if len(block) > available:
                    reason = 'OUTPUT_LIMIT'
                    break
            if reason is not None:
                break
        if reason is None:
            remaining = max(0.0, query_deadline - time.monotonic())
            try:
                returncode = process.wait(timeout=remaining)
                helper_reaped = True
            except subprocess.TimeoutExpired:
                reason = 'TIMEOUT'
    except (OSError, ValueError, RuntimeError) as exc:
        reason = 'LAUNCH_FAILED' if process is None else 'QUERY_ERROR'
        error = f'{type(exc).__name__}: {exc}'[:512]
    finally:
        if process is not None and not helper_reaped:
            try:
                if process.poll() is None:
                    kill_requested = True
                    process.kill()  # Only this invocation's owned child; never a device/service.
                returncode = process.wait(timeout=max(0.0, deadline - time.monotonic()))
                helper_reaped = True
            except (OSError, subprocess.TimeoutExpired) as exc:
                cleanup_error = f'{type(exc).__name__}: {exc}'[:512]
                returncode = process.poll()
                helper_reaped = returncode is not None
        if process is not None:
            for name in ('stdout', 'stderr'):
                stream = getattr(process, name, None)
                if stream is not None:
                    streams.setdefault(name, stream)
        if selector is not None:
            try:
                selector.close()
            except OSError as exc:
                cleanup_error = cleanup_error or f'selector close: {exc}'[:512]
        for stream in streams.values():
            try:
                stream.close()
            except OSError as exc:
                cleanup_error = cleanup_error or f'pipe close: {exc}'[:512]
    status = ('UNKNOWN_HELPER_PENDING' if process is not None and not helper_reaped else
              reason if reason is not None else 'QUERY_COMPLETED' if returncode == 0 else 'QUERY_NONZERO_EXIT')
    return dict(format='RK_DEBUG_DISPLAY_INFO_V1', status=status,
        scope='READ_ONLY_MODETEST_RESOURCES_NOT_DISPLAY_OR_MODESET_QUALIFICATION',
        executable=identity, driver_name=driver_name, command=command,
        pid=None if process is None else process.pid, returncode=returncode,
        helper_reaped=helper_reaped, kill_requested=kill_requested,
        timed_out=reason == 'TIMEOUT', output_limit_exceeded=reason == 'OUTPUT_LIMIT',
        stdout=bytes(captured['stdout']).decode('utf-8', errors='replace'),
        stderr=bytes(captured['stderr']).decode('utf-8', errors='replace'),
        text_encoding='UTF8_REPLACE', captured_bytes=total,
        stdout_bytes=len(captured['stdout']), stderr_bytes=len(captured['stderr']),
        stdout_sha256=hashlib.sha256(captured['stdout']).hexdigest(),
        stderr_sha256=hashlib.sha256(captured['stderr']).hexdigest(),
        elapsed_s=time.monotonic() - start,
        limits=dict(timeout_s=timeout_s, query_budget_s=timeout_s-cleanup_reserve,
                    cleanup_reserve_s=cleanup_reserve, combined_output_bytes=max_output_bytes),
        error=error, cleanup_error=cleanup_error, physical_display='NOT_RUN',
        receiver_mpp_opened=False, installation_performed=False)
