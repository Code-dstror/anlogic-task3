"""Bounded operator reports, independent of hardware and large frame payloads."""
from __future__ import annotations

from collections import deque
from dataclasses import asdict, is_dataclass
import json
import math
from pathlib import Path
from threading import Lock
import time


def _unique(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError('duplicate JSON field: ' + key)
        result[key] = value
    return result


def load_document(path, *, maximum=65536):
    path = Path(path)
    if not path.is_file() or path.stat().st_size > maximum:
        raise ValueError('expected a bounded regular JSON file')
    with path.open('rb') as stream:
        data = stream.read(maximum + 1)
    if len(data) > maximum:
        raise ValueError('JSON file exceeded its bound during read')
    return parse_document(data)


def parse_document(data):
    if not isinstance(data, (str, bytes)) or len(data) > 65536:
        raise ValueError('bounded JSON text required')
    def reject(value):
        raise ValueError('nonfinite JSON value')
    try:
        value = json.loads(data, object_pairs_hook=_unique, parse_constant=reject)
    except (UnicodeError, RecursionError) as error:
        raise ValueError('invalid JSON document') from error
    pending = [(value, 0)]
    count = 0
    while pending:
        item, depth = pending.pop()
        count += 1
        if depth > 12 or count > 8192:
            raise ValueError('JSON nesting/item limit')
        if isinstance(item, dict):
            pending.extend((v, depth + 1) for v in item.values())
        elif isinstance(item, list):
            pending.extend((v, depth + 1) for v in item)
        elif type(item) is float and not math.isfinite(item):
            raise ValueError('nonfinite JSON number')
    return value


def public_value(value):
    """For small status/configuration objects only; binary frames are excluded."""
    if hasattr(value, 'as_dict'):
        value = value.as_dict()
    elif is_dataclass(value):
        value = asdict(value)
    if isinstance(value, dict):
        return {str(key): public_value(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [public_value(item) for item in value]
    if isinstance(value, Path):
        return str(value)
    if value is None or type(value) in (str, int, bool):
        return value
    if type(value) is float and math.isfinite(value):
        return value
    raise TypeError('binary/unrecognized value is not a debug status object')


class Journal:
    def __init__(self, *, limit=256, clock_ns=time.monotonic_ns):
        if type(limit) is not int or not 1 <= limit <= 4096:
            raise ValueError('journal limit must be 1..4096 events')
        self._events, self._lock = deque(maxlen=limit), Lock()
        self._clock = clock_ns
        self.total = 0

    def record(self, kind, value):
        event = dict(kind=kind, host_monotonic_ns=self._clock(), value=public_value(value))
        encoded = json.dumps(event, ensure_ascii=False, allow_nan=False)
        if len(encoded.encode('utf-8')) > 262144:
            raise ValueError('one debug event exceeds256 KiB')
        with self._lock:
            self.total += 1
            event['ordinal'] = self.total
            self._events.append(event)

    def snapshot(self):
        with self._lock:
            return dict(total=self.total, retained=len(self._events),
                        dropped_from_history=self.total-len(self._events), events=list(self._events))


def save_report(path, value):
    data = (json.dumps(public_value(value), indent=2, ensure_ascii=False, allow_nan=False)+'\n').encode('utf-8')
    if len(data) > 8 * 1024 * 1024:
        raise ValueError('debug report exceeds8 MiB')
    with Path(path).open('xb') as stream:
        stream.write(data)
        stream.flush()
