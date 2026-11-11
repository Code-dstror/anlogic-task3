"""Preserve native stage messages before TD reuses its run.log filenames."""
from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import atomic_json, read_json


MESSAGE_SUFFIXES = {'.log', '.logw', '.msg', '.messages', '.warnings', '.errors'}
SNAPSHOT_SUFFIXES = MESSAGE_SUFFIXES | {'.tcl', '.sh', '.bat', '.cfg', '.prj', '.params', '.status'}
STAGE_RUNS = dict(synthesis='syn_1', placement='phy_1', routing='phy_1', bitgen='phy_1')
WARNING = re.compile(r'\b(CRITICAL[- ]WARNING|WARNING)\b', re.IGNORECASE)
# Linux TD emits this successful check as an informational RUN message. Its
# phrase "critical warning" is not itself a warning. Match only the zero case;
# keep nonzero checks and actual warning lines in the index and all raw logs.
CLEAN_CRITICAL_CHECK = re.compile(
    r'\s*RUN-0008\s*:\s*Do critical warning check and 0 issue\(s\) found\.\s*', re.IGNORECASE)
CODE = re.compile(r'\b[A-Z][A-Z0-9]+-\d{3,}\b')
SUPPRESSION = re.compile(r'similar messages.*suppress|messages? (?:will be |are |were )?suppressed', re.IGNORECASE)


def native_paths(job):
    job = Path(job).resolve()
    paths = read_json(job / 'paths.json', {})
    result = {}
    for name in ('project', 'run_root'):
        if name in paths:
            path = Path(paths[name]).resolve()
            if not path.is_relative_to(job):
                raise ValueError('Native log path leaves its job')
            result[name] = path
    return result


def capture_stage(job, stage, run, state, since=0):
    job = Path(job).resolve()
    if stage not in (*STAGE_RUNS, 'terminal') or run not in ('syn_1', 'phy_1'):
        raise ValueError('Use a native stage and run')
    if stage != 'terminal' and STAGE_RUNS[stage] != run:
        raise ValueError('Native stage/run mismatch')
    paths = native_paths(job)
    destination = job / 'stage-logs' / stage
    previous = read_json(destination / 'capture.json')
    if previous is not None:
        return previous
    temporary = job / ('.stage-logs-' + uuid.uuid4().hex + '.tmp')
    sources = []
    if 'run_root' in paths:
        directory = paths['run_root'] / run
        if directory.is_dir():
            sources.extend((path, Path(run) / path.relative_to(directory))
                           for path in directory.rglob('*')
                           if path.is_file() and path.suffix.lower() in SNAPSHOT_SUFFIXES)
    if 'project' in paths:
        sources.extend((path, Path('project') / path.name)
                       for path in paths['project'].parent.iterdir()
                       if path.is_file() and path.suffix.lower() in MESSAGE_SUFFIXES)
    if stage == 'terminal':
        sources.extend((job / name, Path(name)) for name in ('td.log', 'worker.log') if (job / name).is_file())
    entries, errors = [], []
    temporary.mkdir()
    try:
        for source, relative in sorted(sources):
            try:
                if source.is_symlink() or not source.resolve().is_relative_to(job):
                    raise ValueError('Linked native message file is not archived')
                with source.open('rb') as stream:
                    before = os.fstat(stream.fileno())
                    target = temporary / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    remaining = before.st_size
                    with target.open('xb') as output:
                        while remaining:
                            body = stream.read(min(1024**2, remaining))
                            if not body:
                                raise OSError('Native message file was truncated while being archived')
                            output.write(body)
                            remaining -= len(body)
                        output.flush()
                        os.fsync(output.fileno())
                    after = os.fstat(stream.fileno())
                entries.append(dict(path=relative.as_posix(), source=source.relative_to(job).as_posix(),
                                    bytes=before.st_size, mtime=before.st_mtime,
                                    predates_stage=bool(since and before.st_mtime < since),
                                    changed_during_copy=(before.st_size, before.st_mtime_ns) !=
                                                        (after.st_size, after.st_mtime_ns)))
            except (OSError, ValueError) as error:
                errors.append(dict(source=source.relative_to(job).as_posix(), error=str(error)))
        document = dict(schema=1, stage=stage, run=run, state=state, captured_at=time.time(),
                        files=entries, errors=errors, warning_inventory_complete=False)
        atomic_json(temporary / 'capture.json', document)
        destination.parent.mkdir(exist_ok=True)
        temporary.rename(destination)
        return document
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def summarize_warnings(job):
    job = Path(job).resolve()
    sources = [path for path in (job / 'stage-logs').rglob('*')
               if path.is_file() and not path.is_symlink() and path.suffix.lower() in MESSAGE_SUFFIXES]
    if (job / 'td.log').is_file():
        sources.append(job / 'td.log')
    temporary = job / ('warnings.' + uuid.uuid4().hex + '.tmp')
    files, total, suppressed = [], 0, 0
    try:
        with temporary.open('w', encoding='utf-8', newline='') as output:
            writer = csv.writer(output)
            writer.writerow(['source', 'line', 'severity', 'code', 'message'])
            for source in sorted(sources):
                count, notices, codes = 0, 0, {}
                relative = source.relative_to(job).as_posix()
                with source.open('rb') as probe:
                    binary = b'\0' in probe.read(4096)
                if binary:
                    files.append(dict(path=relative, indexed_as_text=False, visible_warning_lines=0,
                                      suppression_notices=0, codes={}))
                    continue
                with source.open(encoding='utf-8', errors='replace') as stream:
                    for number, line in enumerate(stream, 1):
                        severity = None if CLEAN_CRITICAL_CHECK.fullmatch(line) else WARNING.search(line)
                        suppression = SUPPRESSION.search(line)
                        if suppression:
                            notices += 1
                        if not severity and not suppression:
                            continue
                        code = CODE.search(line)
                        name = code.group() if code else ''
                        if severity:
                            count += 1
                            codes[name] = codes.get(name, 0) + 1
                        writer.writerow([relative, number, severity.group().upper() if severity else 'SUPPRESSION',
                                         name, line.rstrip('\r\n')])
                files.append(dict(path=relative, indexed_as_text=True, visible_warning_lines=count,
                                  suppression_notices=notices, codes=codes))
                total += count
                suppressed += notices
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, job / 'warnings.csv')
    finally:
        temporary.unlink(missing_ok=True)
    summary = dict(schema=1, generated_at=time.time(), visible_warning_occurrences=total,
                   suppression_notices=suppressed, warning_inventory_complete=False, files=files,
                   notes=['Counts are emitted log occurrences, not unique issues or GUI message totals.',
                          'Stage/terminal/console copies may contain the same warning more than once.',
                          'Inspect raw .logw companions for warnings suppressed in run.log.',
                          'Messages TD never wrote to any file and overwritten pre-upgrade logs cannot be reconstructed.'])
    atomic_json(job / 'warning-summary.json', summary)
    return summary


def finalize_logs(job, state):
    job = Path(job).resolve()
    paths = native_paths(job)
    if 'run_root' not in paths:
        return dict(state='NOT_RUN', warning_inventory_complete=False)
    from flow import stage_status
    stages = stage_status(job / 'td.log')
    for stage, run in STAGE_RUNS.items():
        if stages[stage] == 'RUNNING':
            capture_stage(job, stage, run, state)
    run = 'phy_1' if (paths['run_root'] / 'phy_1').is_dir() else 'syn_1'
    capture_stage(job, 'terminal', run, state)
    summary = summarize_warnings(job)
    captures = [read_json(path) for path in sorted((job / 'stage-logs').glob('*/capture.json'))]
    errors = [error for capture in captures for error in capture['errors']]
    return dict(state='PARTIAL' if errors else 'CAPTURED', errors=errors,
                stages=[capture['stage'] for capture in captures], warning_inventory_complete=False,
                visible_warning_occurrences=summary['visible_warning_occurrences'],
                suppression_notices=summary['suppression_notices'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--job', type=Path, required=True)
    parser.add_argument('--stage', required=True, choices=(*STAGE_RUNS, 'terminal'))
    parser.add_argument('--run', required=True, choices=('syn_1', 'phy_1'))
    parser.add_argument('--state', required=True)
    parser.add_argument('--since', type=float, default=0)
    arguments = parser.parse_args()
    captured = capture_stage(arguments.job, arguments.stage, arguments.run, arguments.state, arguments.since)
    print('TD_SIMPLE_LOG_ARCHIVE ' + arguments.stage + ' files=' + str(len(captured['files'])))
    if captured['errors']:
        raise OSError(json.dumps(captured['errors'], ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
