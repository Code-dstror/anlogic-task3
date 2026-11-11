"""Pinned source/test authorities, with bounded Windows sharing retries."""
from pathlib import Path
import hashlib
import json
import os
import time

EXT = Path(__file__).resolve().parent
PROJECT = EXT.parents[2]
LOCK = PROJECT / 'docs/HD_TEST_LOCK.json'


def retry(operation):
    for attempt in range(7):
        try:
            return operation()
        except PermissionError:
            if attempt == 6:
                raise
            time.sleep(0.02 * 2 ** attempt)


def shared_bytes(path):
    """Windows state readers permit another process to atomically replace the file."""
    if os.name != 'nt':
        return Path(path).read_bytes()
    import ctypes
    from ctypes import wintypes
    import msvcrt
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    create = kernel.CreateFileW
    create.argtypes = [wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,wintypes.LPVOID,
                       wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE]
    create.restype = wintypes.HANDLE
    handle = create(str(Path(path).resolve()), 0x80000000, 7, None, 3, 0x80, None)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        descriptor = msvcrt.open_osfhandle(handle, os.O_RDONLY | os.O_BINARY)
    except Exception:
        kernel.CloseHandle(wintypes.HANDLE(handle))
        raise
    with os.fdopen(descriptor, 'rb') as stream:
        return stream.read()


def sha(path):
    return retry(lambda: hashlib.sha256(shared_bytes(path)).hexdigest())


def read(path):
    return retry(lambda: json.loads(shared_bytes(path).decode('utf-8-sig')))


def pinned_json(path, expected):
    data = retry(lambda: shared_bytes(path))
    if hashlib.sha256(data).hexdigest() != expected:
        raise RuntimeError('Pinned SHA256 differs: ' + str(path))
    return json.loads(data.decode('utf-8-sig'))


def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    body = json.dumps(value, indent=2) + '\n'
    retry(lambda: temporary.write_text(body, encoding='utf-8'))
    retry(lambda: os.replace(temporary, path))


def authorities(expected_lock=None):
    expected_lock = expected_lock or os.environ.get('HDR_MERGE_TEST_LOCK_SHA256')
    if not expected_lock or len(expected_lock) != 64:
        raise RuntimeError('Externally pinned HDR_MERGE_TEST_LOCK_SHA256 is required')
    lock = pinned_json(LOCK, expected_lock)
    seal_path = PROJECT / lock['source_seal_path']
    seal = pinned_json(seal_path, lock['source_seal_sha256'])
    if not seal.get('production_inputs'):
        raise RuntimeError('Pinned source seal has no production inputs')
    return dict(lock=lock, seal=seal, seal_path=seal_path,
                source_seal_sha256=lock['source_seal_sha256'], test_lock_sha256=expected_lock)


def verify(bound, output=None):
    # Revalidate the external authority before trusting either path/hash mapping.
    current = authorities(bound['test_lock_sha256'])
    rows = []
    for category, expected in [('production', current['seal']['production_inputs']),
                               ('test_reference', current['lock']['test_inputs'])]:
        for relative, digest in expected.items():
            path = PROJECT / relative
            actual = sha(path) if path.is_file() else None
            rows.append(dict(category=category, path=relative,
                             expected_sha256=digest, actual_sha256=actual))
    failures = [row['path'] for row in rows if row['actual_sha256'] != row['expected_sha256']]
    report = dict(status='SOURCE_DRIFT' if failures else 'PASS',
                  checked_epoch=time.time(), source_seal_sha256=current['source_seal_sha256'],
                  test_lock_sha256=current['test_lock_sha256'], inputs=rows, mismatches=failures)
    if output:
        atomic(output, report)
    if failures:
        raise RuntimeError('Pinned input drift: ' + ', '.join(failures))
    return report


def begin_binding(run):
    bound = authorities()
    # Reserve the run only after authorities are valid; the runner creates it next.
    bound['start_report'] = verify(bound)
    return bound


def finish_binding(bound, run):
    atomic(Path(run) / 'PINNED_INPUTS_START.json', bound['start_report'])
    return verify(bound, Path(run) / 'PINNED_INPUTS_END.json')


def assert_snapshot_binding(sid):
    bound = authorities()
    if sid.get('source_seal_sha256') != bound['source_seal_sha256'] or sid.get('test_lock_sha256') != bound['test_lock_sha256']:
        raise RuntimeError('Simulation identity differs from pinned source/test authority')
    expected = {str((PROJECT / p).resolve()).casefold(): h
                for p, h in bound['seal']['production_inputs'].items()}
    actual = {str(Path(row['path']).resolve()).casefold(): row['sha256']
              for row in sid['production_inputs']}
    if actual != expected:
        raise RuntimeError('Simulation production identity differs from pinned source authority')
    verify(bound)
