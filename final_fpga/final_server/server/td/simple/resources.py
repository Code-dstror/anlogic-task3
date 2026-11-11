"""Read-only telemetry and conservative admission from measured CPU and RAM."""
from __future__ import annotations

import csv
import math
import os
from pathlib import Path
import re
import time

from common import atomic_json, job_thread_reservation, read_json
from flow import stage_status


GIB = 1024**3


def group_limits(proc, mount):
    directories = {mount, mount / 'memory', mount / 'cpu'}
    for line in (proc / 'self/cgroup').read_text().splitlines():
        unused, controllers, name = line.split(':', 2)
        relative = Path(name.lstrip('/'))
        if '..' in relative.parts:
            raise ValueError('Unexpected cgroup membership')
        bases = [mount] if not controllers else [mount / controller for controller in controllers.split(',')]
        for base in bases:
            directory = base / relative
            while directory.is_relative_to(base):
                directories.add(directory)
                if directory == base:
                    break
                directory = directory.parent
    cpu_limits = []
    memory_limits = []
    for directory in directories:
        if (directory / 'cpu.max').exists():
            quota, period = (directory / 'cpu.max').read_text().split()
            if quota != 'max':
                cpu_limits.append(int(quota) / int(period))
        if (directory / 'cpu.cfs_quota_us').exists():
            quota = int((directory / 'cpu.cfs_quota_us').read_text())
            if quota > 0:
                cpu_limits.append(quota / int((directory / 'cpu.cfs_period_us').read_text()))
        for limit_name, used_name in (('memory.max', 'memory.current'), ('memory.high', 'memory.current'),
                                     ('memory.limit_in_bytes', 'memory.usage_in_bytes')):
            if (directory / limit_name).exists():
                limit = (directory / limit_name).read_text().strip()
                if limit != 'max' and 0 < int(limit) < 2**60:
                    total = int(limit) / GIB
                    used = int((directory / used_name).read_text()) / GIB
                    memory_limits.append(max(0, total - used - max(2, min(64, total * .1))))
    return cpu_limits, memory_limits


def process_table(proc, td_root, page_size):
    processes = {}
    td_prefix = str(Path(td_root).resolve() / 'bin') + '/'
    for directory in proc.iterdir():
        if not directory.name.isdecimal():
            continue
        try:
            body = (directory / 'stat').read_text()
            fields = body.rsplit(')', 1)[1].split()
            name = body.split('(', 1)[1].rsplit(')', 1)[0]
            if fields[0] == 'Z':
                continue
            try:
                executable = os.readlink(directory / 'exe')
            except (PermissionError, FileNotFoundError):
                executable = ''
            try:
                arguments = (directory / 'cmdline').read_bytes().rstrip(b'\0').decode(errors='replace').split('\0')
            except PermissionError:
                arguments = []
            processes[int(directory.name)] = dict(
                pid=int(directory.name), start=fields[19], parent=int(fields[1]),
                ticks=int(fields[11]) + int(fields[12]), rss_gib=max(0, int(fields[21])) * page_size / GIB,
                uid=directory.stat().st_uid, name=name,
                td=(name == 'td' or executable.startswith(td_prefix) or
                    any(argument.startswith(td_prefix) for argument in arguments)))
        except (FileNotFoundError, ProcessLookupError):
            continue
    return processes


def process_groups(processes, records, jobs_root):
    children = {}
    for process in processes.values():
        children.setdefault(process['parent'], []).append(process['pid'])
    owners = {}
    for record in records:
        if record['state'] not in ('STARTING', 'RUNNING'):
            continue
        owner = read_json(jobs_root / record['id'] / 'worker.json', {})
        current = processes.get(owner.get('pid'))
        if not current or any(current[key] != owner.get(key) for key in ('pid', 'start', 'uid')):
            continue
        pending = [current['pid']]
        while pending:
            pid = pending.pop()
            if pid in owners:
                continue
            owners[pid] = record['id']
            pending.extend(children.get(pid, []))
    manual = {pid for pid, process in processes.items() if process['td'] and pid not in owners}
    for root_pid in manual:
        pending = [root_pid]
        while pending:
            pid = pending.pop()
            if pid != root_pid and pid in manual or pid in owners:
                continue
            owners[pid] = 'manual:' + str(root_pid) + ':' + processes[root_pid]['start']
            pending.extend(children.get(pid, []))
    groups = {}
    for pid, owner in owners.items():
        group = groups.setdefault(owner, dict(pids=[], rss_gib=0, ticks={}))
        process = processes[pid]
        group['pids'].append(pid)
        group['rss_gib'] += process['rss_gib']
        group['ticks'][(pid, process['start'])] = process['ticks']
    return groups


class ResourceMonitor:
    def __init__(self, root, config, jobs_root, proc=Path('/proc'), mount=Path('/sys/fs/cgroup')):
        self.root, self.config, self.jobs_root = Path(root), config, Path(jobs_root)
        self.proc, self.mount = Path(proc), Path(mount)
        self.previous = None
        self.next_sample = 0
        self.value = {}
        self.history = read_json(self.root / 'resource-history.json', {})
        self.job_peaks = {}
        self.log_signatures = {}
        self.last_start = read_json(self.root / 'resource-start.json', {}).get('time', 0)
        self.cpu_windows = {}

    @property
    def measured_admission(self):
        return self.config.get('resource_policy_version', 5) >= 6

    def key(self, spec):
        project = spec['project']
        return '|'.join((project['id'], project['root'], project['al'], str(job_thread_reservation(spec))))

    def estimate(self, spec):
        if self.measured_admission:
            peak = self.history.get(self.key(spec), {}).get('rss_peak_gib', 0)
            memory = max(self.config['memory_per_job_gib'], math.ceil(peak * self.config['memory_growth_factor']))
            if not peak:
                memory = max(16, memory)
            return dict(cpu_cores=job_thread_reservation(spec) * self.config['cpu_growth_factor'],
                        memory_gib=memory)
        return dict(cpu_cores=job_thread_reservation(spec),
                    memory_gib=self.config['memory_per_job_gib'])

    def sample(self, records):
        now = time.monotonic()
        if now < self.next_sample:
            return self.value
        self.next_sample = now + self.config['resource_sample_seconds']
        try:
            self.learn_native_peaks(records)
            self.value = self.collect(records, now)
            atomic_json(self.root / 'resource-history.json', self.history)
        except (OSError, ValueError, IndexError, KeyError, TypeError) as error:
            self.previous = None
            self.cpu_windows.clear()
            self.value = dict(sampled_at=time.time(), complete=False, state='RESOURCE_TELEMETRY_UNAVAILABLE',
                              error=str(error)[-300:])
        atomic_json(self.root / 'resources.json', self.value)
        return self.value

    def learn_native_peaks(self, records):
        for record in records:
            if record['state'] == 'QUEUED':
                continue
            job = self.jobs_root / record['id']
            paths = read_json(job / 'paths.json', {})
            run_root = Path(paths.get('run_root', job / 'missing'))
            if not run_root.resolve().is_relative_to(job.resolve()):
                raise ValueError('Native log path leaves its job')
            for run in ('syn_1', 'phy_1'):
                path = run_root / run / 'run.log'
                if not path.is_file():
                    continue
                stat = path.stat()
                signature = (stat.st_size, stat.st_mtime_ns)
                if self.log_signatures.get(str(path)) == signature:
                    continue
                with path.open('rb') as stream:
                    stream.seek(max(0, stat.st_size - 128 * 1024))
                    peaks = re.findall(rb'\bpeak\s*=\s*(\d+(?:\.\d+)?)', stream.read())
                if peaks:
                    history = self.history.setdefault(self.key(record['spec']), {})
                    history['rss_peak_gib'] = max(history.get('rss_peak_gib', 0), max(map(float, peaks)) / 1024)
                self.log_signatures[str(path)] = signature

    def collect(self, records, now):
        lines = (self.proc / 'stat').read_text().splitlines()
        values = list(map(int, lines[0].split()[1:9]))
        total, idle = sum(values), values[3] + values[4]
        host_cpus = sum(line.split()[0][3:].isdecimal() for line in lines if line.startswith('cpu'))
        if host_cpus < 1:
            raise ValueError('Host CPU count unavailable')
        affinity = len(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else host_cpus
        cpu_limits, memory_limits = group_limits(self.proc, self.mount)
        effective = min([host_cpus, affinity, *cpu_limits])
        memory = {name: int(value.split()[0]) / 1024**2 for name, value in
                  (line.split(':', 1) for line in (self.proc / 'meminfo').read_text().splitlines())}
        page_size = os.sysconf('SC_PAGE_SIZE') if hasattr(os, 'sysconf') else 4096
        ticks_per_second = os.sysconf('SC_CLK_TCK') if hasattr(os, 'sysconf') else 100
        groups = process_groups(process_table(self.proc, self.config['td_root'], page_size), records, self.jobs_root)
        current_ticks = {key: ticks for group in groups.values() for key, ticks in group['ticks'].items()}
        previous = self.previous
        self.previous = (now, total, idle, current_ticks)
        ready = bool(previous and 0 < now - previous[0] <= 45 and total > previous[1] and idle >= previous[2])
        if not ready:
            self.cpu_windows.clear()
        host_busy = (max(0, min(1, 1 - (idle - previous[2]) / (total - previous[1]))) if ready else 0)
        for name, group in groups.items():
            ticks = group.pop('ticks')
            group['cpu_cores'] = (sum(max(0, ticks - previous[3].get(key, ticks)) for key, ticks in
                                       ticks.items()) / ticks_per_second / (now - previous[0]) if ready else 0)
            group['cpu_percent'] = group['cpu_cores'] / effective * 100
            window = self.cpu_windows.setdefault(name, [])
            if ready:
                window.append(group['cpu_cores'])
                del window[:-3]
            group['cpu_peak_recent'] = max(window, default=0)
            group['cpu_ready'] = len(window) >= 2
        self.cpu_windows = {name: value for name, value in self.cpu_windows.items() if name in groups}
        current = {record['id']: record for record in records}
        for name, group in groups.items():
            key = self.key(current[name]['spec']) if name in current else 'manual'
            history = self.history.setdefault(key, {})
            history['rss_peak_gib'] = max(history.get('rss_peak_gib', 0), group['rss_gib'])
            history['cpu_peak_cores'] = max(history.get('cpu_peak_cores', 0), group['cpu_cores'])
            history['updated_at'] = time.time()
            if name in current:
                self.record_job(name, group)
        td_cores = sum(group['cpu_cores'] for group in groups.values())
        reserve = max(self.config['min_free_memory_gib'], min(128, memory['MemTotal'] * .08))
        return dict(sampled_at=time.time(), complete=ready, state='READY' if ready else 'WAITING_FOR_CPU_SAMPLE',
                    host_cpu_count=host_cpus, effective_cpu_cores=effective, host_cpu_percent=host_busy * 100,
                    host_busy_cores=host_busy * host_cpus, td_cpu_percent=td_cores / effective * 100,
                    td_cpu_cores=td_cores, td_rss_gib=sum(group['rss_gib'] for group in groups.values()),
                    host_memory_total_gib=memory['MemTotal'], host_memory_available_gib=memory['MemAvailable'],
                    host_memory_used_gib=memory['MemTotal'] - memory['MemAvailable'],
                    host_memory_percent=(1 - memory['MemAvailable'] / memory['MemTotal']) * 100,
                    host_memory_reserve_gib=reserve,
                    memory_headroom_gib=min([max(0, memory['MemAvailable'] - reserve), *memory_limits]),
                    manual_td_groups=sum(name.startswith('manual:') for name in groups), groups=groups)

    def record_job(self, name, group):
        job = self.jobs_root / name
        stages = stage_status(job / 'td.log')
        stage = next((stage for stage, state in stages.items() if state == 'RUNNING'), 'starting_or_finishing')
        peaks = self.job_peaks.setdefault(name, read_json(job / 'resources.json', {}).get('stage_peaks', {}))
        peak = peaks.setdefault(stage, {})
        peak['rss_gib'] = max(peak.get('rss_gib', 0), group['rss_gib'])
        peak['cpu_cores'] = max(peak.get('cpu_cores', 0), group['cpu_cores'])
        paths = read_json(job / 'paths.json', {})
        logs = [job / 'td.log']
        if paths.get('run_root') and Path(paths['run_root']).resolve().is_relative_to(job.resolve()):
            logs += [Path(paths['run_root']) / run / 'run.log' for run in ('syn_1', 'phy_1')]
        activity = {str(path.relative_to(job)): dict(bytes=path.stat().st_size, mtime=path.stat().st_mtime)
                    for path in logs if path.is_file()}
        snapshot = dict(sampled_at=time.time(), stage=stage, stage_peaks=peaks, logs=activity, **group)
        atomic_json(job / 'resources.json', snapshot)
        csv_path = job / 'resources.csv'
        needs_header = not csv_path.exists()
        with csv_path.open('a', newline='', encoding='utf-8') as stream:
            writer = csv.writer(stream)
            if needs_header:
                writer.writerow(['epoch', 'stage', 'cpu_cores', 'cpu_percent', 'rss_gib'])
            writer.writerow([snapshot['sampled_at'], stage, group['cpu_cores'], group['cpu_percent'], group['rss_gib']])

    def forecast(self, active):
        groups = self.value.get('groups', {})
        active_ids = {record['id'] for record in active}
        cpu, memory, growth, uncontrolled_cpu = 0, 0, 0, 0
        for record in active:
            group = groups.get(record['id'], {})
            estimate = self.estimate(record['spec'])
            reserved_cpu = estimate['cpu_cores']
            if self.measured_admission and group.get('cpu_ready'):
                reserved_cpu = max(job_thread_reservation(record['spec']) * .5, 1,
                                   group['cpu_peak_recent'] * self.config['cpu_growth_factor'])
            reserved_memory = estimate['memory_gib']
            cpu += reserved_cpu
            memory += reserved_memory
            growth += max(0, reserved_memory - group.get('rss_gib', 0))
        for name, group in groups.items():
            if name in active_ids:
                continue
            peak = self.history.get('manual', {})
            manual_cpu = max(0, group['cpu_cores'])
            if self.measured_admission:
                manual_cpu = max(1, manual_cpu, group.get('cpu_peak_recent', 0)) * self.config['cpu_growth_factor']
            uncontrolled_cpu += manual_cpu
            reserved = max(32, self.config['memory_per_job_gib'], group['rss_gib'] * self.config['memory_growth_factor'],
                           peak.get('rss_peak_gib', 0) * self.config['memory_growth_factor'])
            memory += reserved
            growth += max(0, reserved - group['rss_gib'])
        return dict(td_cpu_reserved_cores=cpu, uncontrolled_td_cpu_cores=uncontrolled_cpu,
                    td_memory_reserved_gib=memory, future_memory_growth_gib=growth,
                    active_jobs=len(active), active_threads=sum(job_thread_reservation(record['spec']) for record in active))

    def allows(self, candidate, active):
        sample = self.value
        forecast = self.forecast(active)
        estimate = self.estimate(candidate['spec'])
        forecast.update(candidate=estimate, candidate_job=candidate['id'])
        if not sample.get('complete'):
            return False, sample.get('state', 'RESOURCE_TELEMETRY_UNAVAILABLE'), forecast
        if not 0 <= time.time() - sample.get('sampled_at', 0) < 45:
            return False, 'RESOURCE_TELEMETRY_STALE', forecast
        if job_thread_reservation(candidate['spec']) > self.config['max_threads_per_job']:
            return False, 'WAITING_FOR_THREAD_POLICY', forecast
        if self.config['max_parallel'] and len(active) >= self.config['max_parallel']:
            return False, 'WAITING_FOR_PARALLEL_SLOT', forecast
        project = candidate['spec']['project']
        same_project = [record for record in active if record['spec']['project']['id'] == project['id']]
        project_limits = [p.get('max_parallel', 0) for p in [project, *(r['spec']['project'] for r in same_project)]]
        project_limits = [limit for limit in project_limits if limit]
        # Resource-only mode must not inherit the old eight-job project cap.
        if self.config['max_parallel'] and project_limits and len(same_project) >= min(project_limits):
            return False, 'WAITING_FOR_PROJECT_SLOT', forecast
        if forecast['active_threads'] + job_thread_reservation(candidate['spec']) > self.config['max_total_threads']:
            return False, 'WAITING_FOR_THREAD_BUDGET', forecast
        synthesizing = sum(not record['spec'].get('resume', {}).get('checkpoint_level') and
                           stage_status(self.jobs_root / record['id'] / 'td.log')['synthesis'] not in ('DONE', 'REUSED')
                           for record in active)
        if (self.config['max_synth_parallel'] and not candidate['spec'].get('resume', {}).get('checkpoint_level') and
                synthesizing >= self.config['max_synth_parallel']):
            return False, 'WAITING_FOR_SYNTHESIS_SLOT', forecast
        predicted_cpu = forecast['td_cpu_reserved_cores'] + estimate['cpu_cores']
        if self.measured_admission:
            predicted_cpu = max(predicted_cpu + forecast['uncontrolled_td_cpu_cores'],
                                sample['td_cpu_cores'] + estimate['cpu_cores'])
            ceiling = sample['effective_cpu_cores'] * self.config['max_td_cpu_percent'] / 100
            forecast.update(projected_td_cpu_cores=predicted_cpu, td_cpu_limit_cores=ceiling)
            active_ids = {record['id'] for record in active}
            if any(name not in active_ids and not group.get('cpu_ready')
                   for name, group in sample.get('groups', {}).items()):
                return False, 'WAITING_FOR_MANUAL_TD_SAMPLE', forecast
            if predicted_cpu > ceiling:
                return False, 'WAITING_FOR_TD_CPU_BUDGET', forecast
        if predicted_cpu > sample['effective_cpu_cores']:
            return False, 'WAITING_FOR_CPU_CAPACITY', forecast
        # Fixed reservations must not hide RAM already consumed above budget.
        # Account for measured RSS plus remaining reservations and the new job.
        projected_rss = sample['td_rss_gib'] + forecast['future_memory_growth_gib'] + estimate['memory_gib']
        forecast['projected_td_memory_gib'] = projected_rss
        if max(projected_rss, forecast['td_memory_reserved_gib'] + estimate['memory_gib']) > self.config['max_td_memory_gib']:
            return False, 'WAITING_FOR_TD_MEMORY_BUDGET', forecast
        external = max(0, sample['host_busy_cores'] - sample['td_cpu_cores'])
        measured_controlled = max(0, sample['td_cpu_cores'] - forecast['uncontrolled_td_cpu_cores'])
        predicted_host = (external + forecast['uncontrolled_td_cpu_cores'] + estimate['cpu_cores'] +
                          max(forecast['td_cpu_reserved_cores'], measured_controlled))
        if predicted_host > sample['host_cpu_count'] * self.config['max_host_cpu_percent'] / 100:
            return False, 'WAITING_FOR_HOST_CPU', forecast
        if forecast['future_memory_growth_gib'] + estimate['memory_gib'] > sample['memory_headroom_gib']:
            return False, 'WAITING_FOR_HOST_MEMORY', forecast
        start_interval = self.config['start_interval_seconds'] if self.measured_admission else self.config['resource_sample_seconds']
        if time.time() - self.last_start < start_interval:
            return False, 'WAITING_FOR_START_INTERVAL', forecast
        return True, 'READY', forecast

    def started(self):
        self.last_start = time.time()
        atomic_json(self.root / 'resource-start.json', dict(time=self.last_start))
