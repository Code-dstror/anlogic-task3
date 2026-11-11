"""Signal only the original owned TD session, including after a shell exec."""
from __future__ import annotations

import os

from common import process_identity


def same_process(record):
    if not record:
        return None
    current = process_identity(record.get('pid'))
    if current and all(current.get(key) == record.get(key) for key in ('pid', 'start', 'uid')):
        return current
    return None


def signal_session(record, signal_number):
    current = same_process(record)
    if not current:
        return False
    try:
        if os.getpgid(current['pid']) != current['pid']:
            raise ValueError('Refusing to signal a TD process outside its own session group')
        os.killpg(current['pid'], signal_number)
    except ProcessLookupError:
        return False
    return True
