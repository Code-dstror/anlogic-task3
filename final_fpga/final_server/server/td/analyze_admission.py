"""Verify cached TD resource CSVs and replay measured admission without launching TD."""
from __future__ import annotations

import argparse
from bisect import bisect_right
from collections import Counter, defaultdict
import csv
import hashlib
import io
import json
from pathlib import Path
import random
import subprocess
import sys
import tempfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent / 'simple'))
from common import RESOURCE_DEFAULTS
from resources import ResourceMonitor


def percentile(values, fraction):
    values = sorted(values)
    return round(values[int((len(values) - 1) * fraction)], 3) if values else None


def analyze(cache, ref, output):
    def blob(path):
        return subprocess.check_output(['git', '--git-dir=' + str(cache), 'show', ref + ':' + path])

    status = json.loads(blob('status.json'))
    curves = []
    stages = defaultdict(list)
    inventory = []
    for job in status['jobs']:
        if job['threads'] != 4 or job['stages'].get('synthesis') != 'REUSED':
            continue
        manifest = json.loads(blob('jobs/' + job['id'] + '/artifacts.json'))
        item = next((x for x in manifest['files'] if x['path'] == 'resources.csv' and x['complete']), None)
        if item is None:
            continue
        parts = [blob(part['path']) for part in item['parts']]
        for body, part in zip(parts, item['parts']):
            if len(body) != part['bytes'] or hashlib.sha256(body).hexdigest() != part['sha256']:
                raise ValueError('Invalid chunk for ' + job['id'])
        body = b''.join(parts)
        if len(body) != item['bytes'] or hashlib.sha256(body).hexdigest() != item['sha256']:
            raise ValueError('Invalid CSV for ' + job['id'])
        rows = list(csv.DictReader(io.StringIO(body.decode('utf-8'))))
        samples = [(float(row['epoch']), float(row['cpu_cores']), float(row['rss_gib'])) for row in rows]
        for row, sample in zip(rows, samples):
            stages[row['stage']].append(sample[1:])
        inventory.append(dict(job=job['id'], source=job['source_commit'], state=job['state'],
                              sha256=item['sha256'], samples=len(samples)))
        if samples and job['state'] == 'DONE':
            origin = samples[0][0]
            curves.append(dict(samples=[(t - origin, cpu, rss) for t, cpu, rss in samples], job=job))

    summaries = {name: dict(samples=len(rows), cpu_p50=percentile([r[0] for r in rows], .5),
                           cpu_p95=percentile([r[0] for r in rows], .95),
                           cpu_p99=percentile([r[0] for r in rows], .99),
                           cpu_max=percentile([r[0] for r in rows], 1),
                           rss_max_gib=percentile([r[1] for r in rows], 1)) for name, rows in stages.items()}
    replays = []
    for seed in (0, 1, 2):
        workload = list(curves)
        random.Random(seed).shuffle(workload)
        for external_cores, headroom in ((0, 1000), (60, 1000), (0, 150)):
            replays.append(replay(workload, seed, external_cores, headroom))
    result = dict(results_commit=ref, snapshot_time=status['generated_at'], verified_files=len(inventory),
                  samples=sum(x['samples'] for x in inventory), states=dict(Counter(x['state'] for x in inventory)),
                  stages=summaries, replay=replays, files=inventory,
                  limitations='Replay superposes recorded samples and does not model duration changes under contention; '
                              'recent same-project historical memory peaks are assumed available.')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'files'}))


def replay(curves, seed, external, headroom):
    with tempfile.TemporaryDirectory() as directory:
        monitor = ResourceMonitor(Path(directory), dict(RESOURCE_DEFAULTS, max_parallel=0), Path(directory) / 'jobs')
        records = []
        for curve in curves:
            job = curve['job']
            spec = dict(project=job['effective_config'], seed=job['seed'], resume={'checkpoint_level': 1})
            record = dict(id=job['id'], state='RUNNING', spec=spec)
            records.append(record)
            history = monitor.history.setdefault(monitor.key(spec), {})
            history['rss_peak_gib'] = max(history.get('rss_peak_gib', 0), max(r[2] for r in curve['samples']))
            curve['times'] = [r[0] for r in curve['samples']]
        active = {}
        next_job = 0
        elapsed = 0
        peak_jobs = 0
        peak_cpu = 0
        peak_memory = 0
        blocked = Counter()
        over_cpu = 0
        over_memory = 0
        while next_job < len(curves) or active:
            now = 100000 + elapsed
            groups = {}
            for number, started in list(active.items()):
                curve = curves[number]
                age = elapsed - started
                if age > curve['times'][-1] + 20:
                    del active[number]
                    continue
                index = max(0, bisect_right(curve['times'], age) - 1)
                recent = curve['samples'][max(0, index - 2):index + 1]
                groups[records[number]['id']] = dict(cpu_cores=recent[-1][1], rss_gib=recent[-1][2],
                    cpu_ready=age >= 40, cpu_peak_recent=max(row[1] for row in recent))
            cpu = sum(g['cpu_cores'] for g in groups.values())
            memory = sum(g['rss_gib'] for g in groups.values())
            peak_cpu, peak_memory = max(peak_cpu, cpu), max(peak_memory, memory)
            over_cpu += cpu > 56
            over_memory += memory > 300
            if elapsed % 20 == 0:
                monitor.value = dict(complete=True, state='READY', sampled_at=now, effective_cpu_cores=112,
                                     host_cpu_count=112, td_cpu_cores=cpu, td_rss_gib=memory,
                                     host_busy_cores=external + cpu, memory_headroom_gib=max(0, headroom - memory), groups=groups)
            if next_job < len(curves):
                with patch('resources.time.time', return_value=now):
                    allowed, reason, _ = monitor.allows(records[next_job], [records[n] for n in active])
                if allowed:
                    active[next_job] = elapsed
                    next_job += 1
                    monitor.last_start = now
                else:
                    blocked[reason] += 1
            peak_jobs = max(peak_jobs, len(active))
            elapsed += 10
            if elapsed > 30 * 86400:
                raise ValueError('Replay made insufficient progress')
        return dict(order_seed=seed, jobs=len(curves), external_cpu_cores=external,
                    initial_memory_headroom_gib=headroom, peak_jobs=peak_jobs,
                    peak_td_cpu_percent=round(peak_cpu / 112 * 100, 2), peak_td_rss_gib=round(peak_memory, 2),
                    cpu_above_target_samples=over_cpu, memory_above_target_samples=over_memory, waits=dict(blocked))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results-git', type=Path, required=True)
    parser.add_argument('--ref', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    analyze(args.results_git.resolve(), args.ref, args.output)
