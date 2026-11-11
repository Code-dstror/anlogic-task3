"""Minimal TD launcher: native exit status, log capture and explicit cancellation."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import atomic_json, process_identity
from process_control import signal_session


def terminate(process, record):
    if not signal_session(record, signal.SIGTERM):
        return
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        signal_session(record, signal.SIGKILL)
        process.wait()


def run(arguments):
    td_root = arguments.td_root.resolve()
    environment = dict(os.environ)
    for key in ('TD_HOME', 'TD_ROOT', 'ANLOGIC_TD_ROOT', 'TD_INSTALL_DIR'):
        environment[key] = str(td_root)
    environment['PATH'] = str(td_root / 'bin') + os.pathsep + environment.get('PATH', '')
    if os.name == 'posix':
        if not (td_root / 'bin/td').is_file() or not (td_root / 'bin/td.sh').is_file():
            raise ValueError('The selected TD installation is missing bin/td or bin/td.sh')
        command = ['/bin/bash', str(td_root / 'bin/td.sh'), '-b', str(arguments.script.resolve())]
    else:
        command = [str(td_root / 'bin/td_commands_prompt.exe'), arguments.script.resolve().as_posix()]
    arguments.log.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    cancelled = False
    inherited = (arguments.lease_fd,) if arguments.lease_fd is not None and os.name == 'posix' else ()
    with arguments.log.open('wb') as output:
        process = subprocess.Popen(command, cwd=arguments.workdir, env=environment,
                                   stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=os.name == 'posix', pass_fds=inherited)
        record = process_identity(process.pid)
        atomic_json(arguments.record, dict(process=record, command=command, started=started))
        try:
            while process.poll() is None:
                if arguments.cancel and arguments.cancel.exists():
                    cancelled = True
                    if os.name == 'posix':
                        terminate(process, record)
                    else:
                        process.terminate()
                    break
                time.sleep(1)
            exit_code = process.wait()
        except BaseException:
            if os.name == 'posix':
                terminate(process, record)
            else:
                process.terminate()
            raise
    atomic_json(arguments.record.with_suffix('.result.json'),
                dict(exit_code=exit_code, cancelled=cancelled, started=started, finished=time.time(), command=command))
    return 130 if cancelled else exit_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('script', type=Path)
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--workdir', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--record', type=Path, required=True)
    parser.add_argument('--cancel', type=Path)
    parser.add_argument('--lease-fd', type=int)
    return run(parser.parse_args())


if __name__ == '__main__':
    raise SystemExit(main())
