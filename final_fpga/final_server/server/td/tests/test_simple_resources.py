"""Check fixed-budget admission with synthetic Linux counters, never real TD."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
TEST_TEMP = ROOT / 'server/td/local/simple-tests'
TEST_TEMP.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / 'server/td/simple'))
from common import RESOURCE_DEFAULTS, FileLock, Store, atomic_json, job_threads, project_config
from resources import ResourceMonitor, group_limits, process_groups, process_table
import install


class ResourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=TEST_TEMP)
        self.root = Path(self.temporary.name)
        self.jobs = self.root / 'jobs'
        self.jobs.mkdir()
        self.proc = self.root / 'proc'
        self.proc.mkdir()
        (self.proc / 'self').mkdir()
        (self.proc / 'self/cgroup').write_text('0::/\n')
        self.mount = self.root / 'cgroup'
        self.mount.mkdir()
        self.config = dict(RESOURCE_DEFAULTS, resource_policy_version=5, max_parallel=8,
                           max_total_threads=64, memory_per_job_gib=16, memory_growth_factor=1.5,
                           cpu_growth_factor=1, td_root=str(self.root / 'td'))
        self.monitor = ResourceMonitor(self.root, self.config, self.jobs, self.proc, self.mount)

    def tearDown(self):
        self.temporary.cleanup()

    def record(self, name='job1', seed=1, threads=8, state='RUNNING'):
        folder = self.jobs / name
        folder.mkdir(exist_ok=True)
        (folder / 'td.log').write_text('TD_SIMPLE_STAGE synthesis DONE\nTD_SIMPLE_STAGE placement START\n')
        project = dict(id='camera', root='candidate', al='fpga_prj/camera.al', threads=threads)
        return dict(id=name, state=state, spec=dict(id=name, project=project, seed=seed))

    def ready(self, **changes):
        self.monitor.value = dict(complete=True, state='READY', sampled_at=1000,
                                  effective_cpu_cores=256, host_cpu_count=256,
                                  td_cpu_cores=0, td_rss_gib=0, host_busy_cores=0,
                                  memory_headroom_gib=1000, groups={})
        self.monitor.value.update(changes)

    def allows(self, candidate, active=()):
        with patch('resources.time.time', return_value=1000):
            return self.monitor.allows(candidate, list(active))

    def host(self, user=1000, idle=9000):
        (self.proc / 'stat').write_text(f'cpu {user} 0 0 {idle} 0 0 0 0\n' +
                                       ''.join(f'cpu{number} 0 0 0 0\n' for number in range(128)))
        (self.proc / 'meminfo').write_text(f'MemTotal: {1536 * 1024**2} kB\nMemAvailable: {1400 * 1024**2} kB\n')

    def process(self, pid, parent=1, ticks=0, rss_gib=1, name='td', start='100'):
        directory = self.proc / str(pid)
        directory.mkdir(exist_ok=True)
        fields = ['0'] * 22
        fields[0], fields[1], fields[11], fields[12], fields[19], fields[21] = (
            'S', str(parent), str(ticks), '0', start, str(int(rss_gib * 1024**3 / 4096)))
        (directory / 'stat').write_text(str(pid) + ' (' + name + ') ' + ' '.join(fields))
        (directory / 'cmdline').write_bytes(b'fixture\0')
        return dict(pid=pid, start=start, uid=directory.stat().st_uid)

    def test_first_sample_is_not_fresh_zero_cpu_and_second_uses_real_ticks(self):
        self.host()
        record = self.record()
        atomic_json(self.jobs / record['id'] / 'worker.json', self.process(100, name='python'))
        self.process(101, parent=100, ticks=500)
        first = self.monitor.collect([record], 10)
        self.assertFalse(first['complete'])
        json.dumps(first)
        self.host(user=129000, idle=137000)
        self.process(101, parent=100, ticks=16500)
        with patch('resources.os.sched_getaffinity', return_value=set(range(128)), create=True):
            second = self.monitor.collect([record], 30)
        self.assertTrue(second['complete'])
        self.assertAlmostEqual(second['host_cpu_percent'], 50)
        self.assertAlmostEqual(second['td_cpu_cores'], 8)
        self.assertAlmostEqual(second['td_cpu_percent'], 6.25)
        self.assertEqual(second['groups']['job1']['pids'], [100, 101])
        self.assertTrue((self.jobs / 'job1/resources.csv').exists())

    def test_warmup_sample_with_processes_can_be_saved_as_json(self):
        self.host()
        self.process(100)
        result = self.monitor.sample([])
        self.assertFalse(result['complete'])
        self.assertEqual(result['state'], 'WAITING_FOR_CPU_SAMPLE')
        self.assertIn('manual:100:100', json.loads((self.root / 'resources.json').read_text())['groups'])

    def test_manual_gui_and_its_backends_are_counted_once_and_workers_include_all_children(self):
        record = self.record()
        atomic_json(self.jobs / 'job1/worker.json', self.process(100, name='python'))
        self.process(101, parent=100, name='bash')
        self.process(102, parent=101, name='td')
        self.process(200, name='td')
        self.process(201, parent=200, name='td')
        self.process(202, parent=201, name='backend')
        groups = process_groups(process_table(self.proc, self.config['td_root'], 4096), [record], self.jobs)
        all_pids = [pid for group in groups.values() for pid in group['pids']]
        self.assertEqual(sorted(all_pids), [100, 101, 102, 200, 201, 202])
        self.assertEqual(len(all_pids), len(set(all_pids)))
        self.assertEqual(set(groups['job1']['pids']), {100, 101, 102})
        self.assertEqual(sum(name.startswith('manual:') for name in groups), 2)

    def test_reused_pid_does_not_inherit_an_old_worker_owner(self):
        record = self.record()
        owner = self.process(100)
        owner['start'] = '99'
        atomic_json(self.jobs / 'job1/worker.json', owner)
        groups = process_groups(process_table(self.proc, self.config['td_root'], 4096), [record], self.jobs)
        self.assertNotIn('job1', groups)
        self.assertEqual(len(groups), 1)

    def test_reservations_do_not_shrink_when_a_stage_is_temporarily_idle(self):
        active = [self.record('job' + str(number)) for number in range(1, 8)]
        self.ready(groups={record['id']: dict(cpu_cores=.01, rss_gib=.1) for record in active})
        forecast = self.monitor.forecast(active)
        self.assertEqual(forecast['td_memory_reserved_gib'], 112)
        self.assertEqual(forecast['td_cpu_reserved_cores'], 56)
        self.assertTrue(self.allows(self.record('eighth', state='QUEUED'), active)[0])
        for record in active:
            (self.jobs / record['id'] / 'td.log').write_text('TD_SIMPLE_STAGE synthesis DONE\nTD_SIMPLE_STAGE routing START\n')
        self.assertEqual(self.monitor.forecast(active), forecast)

    def test_eighth_job_can_start_but_ninth_waits_even_at_zero_current_utilization(self):
        active = [self.record('job' + str(number)) for number in range(8)]
        self.ready()
        allowed, reason, unused = self.allows(self.record('ninth', state='QUEUED'), active)
        self.assertFalse(allowed)
        self.assertEqual(reason, 'WAITING_FOR_PARALLEL_SLOT')

    def test_legacy_project_hints_and_history_do_not_inflate_controlled_budget(self):
        active = [self.record('first'), self.record('second')]
        candidate = self.record('third', state='QUEUED')
        self.monitor.history[self.monitor.key(candidate['spec'])] = dict(rss_peak_gib=80)
        candidate['spec']['project']['memory_gib'] = 48
        self.ready()
        allowed, reason, forecast = self.allows(candidate, active)
        self.assertTrue(allowed, reason)
        self.assertEqual(forecast['candidate']['memory_gib'], 16)
        self.assertEqual(forecast['td_memory_reserved_gib'], 32)

    def test_eight_legacy_48gib_seeds_reserve_128gib_and_are_admitted(self):
        active = [self.record('old' + str(n)) for n in range(7)]
        candidate = self.record('eighth', state='QUEUED')
        for record in active + [candidate]:
            record['spec']['project']['memory_gib'] = 48
        self.monitor.history[self.monitor.key(candidate['spec'])] = dict(rss_peak_gib=96)
        self.ready(td_rss_gib=42, groups={r['id']:dict(cpu_cores=1,rss_gib=6) for r in active})
        allowed, reason, forecast = self.allows(candidate, active)
        self.assertTrue(allowed, reason)
        self.assertEqual(forecast['td_memory_reserved_gib'] + forecast['candidate']['memory_gib'], 128)
        self.assertEqual(forecast['projected_td_memory_gib'], 128)

    def test_sixteen_four_thread_seeds_use_resources_not_old_eight_job_caps(self):
        self.config['max_parallel']=0
        active=[self.record('seed'+str(n),threads=4) for n in range(15)]
        candidate=self.record('sixteenth',threads=4,state='QUEUED')
        for row in active+[candidate]:
            row['spec']['project'].update(memory_gib=48,max_parallel=8)
        self.ready(td_rss_gib=90,groups={r['id']:dict(cpu_cores=.5,rss_gib=6) for r in active})
        allowed,reason,forecast=self.allows(candidate,active)
        self.assertTrue(allowed,reason)
        self.assertEqual(forecast['active_threads']+forecast['candidate']['cpu_cores'],64)
        self.assertEqual(forecast['td_memory_reserved_gib']+forecast['candidate']['memory_gib'],256)
        self.assertEqual(forecast['projected_td_memory_gib'],256)
        self.assertEqual(self.allows(self.record('seventeenth',threads=4),active+[candidate])[1],'WAITING_FOR_THREAD_BUDGET')

    def test_measured_usage_above_fixed_budget_still_blocks_rss_overcommit(self):
        active = self.record('large')
        self.ready(td_rss_gib=290,groups={'large':dict(cpu_cores=1,rss_gib=290)})
        allowed, reason, forecast = self.allows(self.record('next'),[active])
        self.assertFalse(allowed)
        self.assertEqual(reason,'WAITING_FOR_TD_MEMORY_BUDGET')
        self.assertEqual(forecast['td_memory_reserved_gib'],16)
        self.assertEqual(forecast['projected_td_memory_gib'],306)

    def test_resource_mode_is_not_a_hard_sixteen_seed_limit(self):
        self.config['max_parallel']=0
        active=[self.record('small'+str(n),threads=1) for n in range(17)]
        candidate=self.record('eighteenth',threads=1,state='QUEUED')
        for row in active+[candidate]:row['spec']['project']['max_parallel']=8
        self.ready(td_rss_gib=34,groups={r['id']:dict(cpu_cores=.1,rss_gib=2) for r in active})
        allowed,reason,forecast=self.allows(candidate,active)
        self.assertTrue(allowed,reason)
        self.assertEqual(forecast['projected_td_memory_gib'],288)
        self.assertEqual(self.allows(self.record('nineteenth',threads=1),active+[candidate])[1],'WAITING_FOR_TD_MEMORY_BUDGET')

    def test_full_thread_reservations_prevent_low_phase_cpu_overadmission(self):
        active = [self.record('job' + str(number)) for number in range(7)]
        self.ready(effective_cpu_cores=128)
        self.assertEqual(self.allows(self.record('next', threads=16), active)[1], 'WAITING_FOR_THREAD_BUDGET')

    def test_manual_td_is_in_the_same_cpu_and_memory_budget(self):
        self.ready(effective_cpu_cores=128, groups={
            'manual:1:10': dict(cpu_cores=1, rss_gib=110),
            'manual:2:10': dict(cpu_cores=1, rss_gib=110)})
        self.assertEqual(self.allows(self.record('next'))[1], 'WAITING_FOR_TD_MEMORY_BUDGET')
        self.ready(effective_cpu_cores=128, groups={
            'manual:' + str(number): dict(cpu_cores=0, rss_gib=1) for number in range(3)})
        self.assertTrue(self.allows(self.record('next'))[0])
        self.ready(effective_cpu_cores=128, host_cpu_count=128, host_busy_cores=105, td_cpu_cores=105,
                   groups={'manual:1': dict(cpu_cores=105, rss_gib=1)})
        self.assertEqual(self.allows(self.record('next'))[1], 'WAITING_FOR_HOST_CPU')

    def test_whole_host_cpu_and_future_memory_growth_gate_new_starts(self):
        candidate = self.record('next')
        self.ready(host_busy_cores=220)
        self.assertEqual(self.allows(candidate)[1], 'WAITING_FOR_HOST_CPU')
        self.ready(memory_headroom_gib=20)
        active = self.record('active')
        self.assertEqual(self.allows(candidate, [active])[1], 'WAITING_FOR_HOST_MEMORY')

    def test_missing_stale_or_failed_telemetry_never_authorizes_new_work(self):
        candidate = self.record()
        self.ready(sampled_at=900)
        self.assertEqual(self.allows(candidate)[1], 'RESOURCE_TELEMETRY_STALE')
        self.ready(complete=False, state='WAITING_FOR_CPU_SAMPLE')
        self.assertFalse(self.allows(candidate)[0])
        with patch.object(self.monitor, 'collect', side_effect=PermissionError('hidden process counters')):
            self.monitor.sample([])
        self.assertEqual(self.monitor.value['state'], 'RESOURCE_TELEMETRY_UNAVAILABLE')
        self.assertFalse(self.allows(candidate)[0])

    def test_cgroup_cpu_and_memory_limits_are_read_without_modifying_them(self):
        (self.mount / 'cpu.max').write_text('400000 100000\n')
        (self.mount / 'memory.max').write_text(str(64 * 1024**3))
        (self.mount / 'memory.current').write_text(str(50 * 1024**3))
        cpu, memory = group_limits(self.proc, self.mount)
        self.assertEqual(cpu, [4])
        self.assertAlmostEqual(memory[0], 7.6)
        self.host()
        self.assertEqual(self.monitor.collect([], 10)['effective_cpu_cores'], 4)

    def test_native_log_peak_and_history_survive_a_controller_restart(self):
        record = self.record()
        run_root = self.jobs / record['id'] / 'checkout/candidate/fpga_prj/camera_Runs'
        (run_root / 'phy_1').mkdir(parents=True)
        (run_root / 'phy_1/run.log').write_text('PHY-1001 : Memory(MB): used = 8192, peak = 65536;\n')
        atomic_json(self.jobs / record['id'] / 'paths.json', dict(run_root=str(run_root)))
        self.monitor.learn_native_peaks([record])
        self.assertEqual(self.monitor.history[self.monitor.key(record['spec'])]['rss_peak_gib'],64)
        self.assertEqual(self.monitor.estimate(record['spec'])['memory_gib'], 16)
        atomic_json(self.root / 'resource-history.json', self.monitor.history)
        restarted = ResourceMonitor(self.root, self.config, self.jobs, self.proc, self.mount)
        self.assertEqual(restarted.history[restarted.key(record['spec'])]['rss_peak_gib'],64)
        self.assertEqual(restarted.estimate(record['spec'])['memory_gib'], 16)

    def test_upgrade_migrates_old_memory_config_and_overrides_once(self):
        old=dict(RESOURCE_DEFAULTS,resource_policy_version=4,memory_per_job_gib=48,jobs_root='/owned/jobs')
        new=install.upgrade_config(old)
        self.assertEqual(new['memory_per_job_gib'],12)
        self.assertEqual(new['resource_policy_version'],6)
        self.assertEqual(new['jobs_root'],old['jobs_root'])
        self.assertEqual(old['memory_per_job_gib'],48)
        self.assertEqual(install.upgrade_resource_overrides({'memory_per_job_gib':48,'max_total_threads':64},4),{})
        self.assertEqual(install.upgrade_config(dict(new,memory_per_job_gib=24))['memory_per_job_gib'],24)

    def test_only_one_start_per_twenty_seconds_even_after_restart(self):
        self.ready()
        with patch('resources.time.time', return_value=995):
            self.monitor.started()
        restarted = ResourceMonitor(self.root, self.config, self.jobs, self.proc, self.mount)
        restarted.value = self.monitor.value
        with patch('resources.time.time', return_value=1000):
            self.assertEqual(restarted.allows(self.record(), [])[1], 'WAITING_FOR_START_INTERVAL')

    def test_four_concurrent_syntheses_gate_additional_full_jobs(self):
        self.config['max_synth_parallel'] = 4
        active = [self.record('job' + str(number)) for number in range(4)]
        for record in active:
            (self.jobs / record['id'] / 'td.log').write_text('TD_SIMPLE_STAGE synthesis START\n')
        self.ready()
        self.assertEqual(self.allows(self.record('next'), active)[1], 'WAITING_FOR_SYNTHESIS_SLOT')

    def test_batch_seed_count_has_no_fixed_twenty_four_limit(self):
        project = project_config(dict(id='camera', root='candidate', al='fpga_prj/camera.al',
                                      threads=8, seeds=list(range(1, 25)), seed_threads={'24': 4}))
        self.assertEqual(job_threads(dict(project=project, seed=24)), 4)
        self.assertEqual(job_threads(dict(project=project, seed=1)), 8)
        self.assertEqual(len(project_config(dict(project,seeds=list(range(1,65))))['seeds']),64)
        with self.assertRaises(ValueError):
            project_config(dict(project, threads=33))
        with self.assertRaises(ValueError):
            project_config(dict(project, seed_threads={'25': 8}))

    def test_native_options_cannot_bypass_thread_caps_or_add_arbitrary_tcl_hooks(self):
        base = dict(id='camera', root='candidate', al='fpga_prj/camera.al')
        for options in ({'phy_1': {'flow': {'thread': 32}}},
                        {'phy_1': {'flow': {'enable_seed': 'on'}}},
                        {'syn_1': {'design': {'tcl_beforestep': 'exec anything'}}}):
            with self.assertRaises(ValueError):
                project_config(dict(base, td_options=options))

    def test_native_threads_reject_non_choices_in_projects_synthesis_and_seeds(self):
        base = dict(id='camera', root='candidate', al='fpga_prj/camera.al')
        for value in [0,3,12,20,24,31,33,'auto',True]:
            for setting in [dict(threads=value),dict(synth_threads=value),dict(seed_threads={'1':value})]:
                with self.subTest(setting=setting), self.assertRaises(ValueError):
                    project_config(dict(base,**setting))
        for value in [1,2,4,8,16,32]:
            self.assertEqual(project_config(dict(base,threads=value))['threads'],value)

    def test_reused_synthesis_does_not_consume_synthesis_slots(self):
        active = [self.record('job' + str(number)) for number in range(4)]
        for record in active:
            record['spec']['resume'] = dict(checkpoint_level=1)
            (self.jobs / record['id'] / 'td.log').write_text('TD_SIMPLE_STAGE synthesis REUSED\n')
        self.ready()
        self.assertTrue(self.allows(self.record('next'), active)[0])

    def test_busy_update_refuses_before_stopping_controller_or_modifying_pause(self):
        record = self.record()
        with FileLock(self.jobs / record['id'] / 'worker.lock'):
            with self.assertRaisesRegex(ValueError, 'no controller was stopped'):
                install.drain_for_update(self.root, dict(jobs_root=str(self.jobs)))
        self.assertFalse((self.root / 'STOP').exists())
        self.assertFalse(Store(self.root).get('paused', False))

    def test_interrupted_idle_wait_restores_previous_pause_and_keeps_controller_running(self):
        record = self.record()
        with FileLock(self.jobs / record['id'] / 'worker.lock'):
            with patch('install.time.sleep', side_effect=KeyboardInterrupt):
                with self.assertRaises(KeyboardInterrupt):
                    install.drain_for_update(self.root, dict(jobs_root=str(self.jobs)), True)
        self.assertFalse(Store(self.root).get('paused', False))
        self.assertFalse((self.root / 'STOP').exists())

    def test_upgrade_changes_resource_defaults_but_preserves_state_paths_and_local_settings(self):
        previous = dict(max_parallel=1, max_cpu_percent=40, min_free_memory_gib=16,
                        jobs_root='/home/build-user/fpga_projects/builds', seed_repo='/home/build-user/manual',
                        environment={'LM_LICENSE_FILE': 'server-local-only'})
        upgraded = install.upgrade_config(previous, 8)
        self.assertEqual(upgraded['max_parallel'], 8)
        self.assertEqual(upgraded['max_cpu_percent'], 40)
        self.assertEqual(upgraded['max_td_memory_gib'], 300)
        self.assertEqual(upgraded['min_free_memory_gib'], 64)
        self.assertEqual(upgraded['jobs_root'], previous['jobs_root'])
        self.assertEqual(upgraded['environment'], previous['environment'])
        self.assertEqual(previous['max_parallel'], 1)

    def adaptive_workload(self, count, cpu=1.1, rss=9):
        self.config.update(RESOURCE_DEFAULTS, max_parallel=0)
        active = [self.record('adaptive' + str(n), threads=4) for n in range(count)]
        candidate = self.record('candidate', threads=4, state='QUEUED')
        self.monitor.history[self.monitor.key(candidate['spec'])] = {'rss_peak_gib': 9.257}
        groups = {r['id']: dict(cpu_cores=cpu, cpu_peak_recent=cpu, cpu_ready=True, rss_gib=rss) for r in active}
        self.ready(effective_cpu_cores=112, host_cpu_count=112, host_busy_cores=count * cpu,
                   td_cpu_cores=count * cpu, td_rss_gib=count * rss, groups=groups)
        return active, candidate

    def test_measured_policy_admits_twenty_five_known_four_thread_jobs(self):
        active, candidate = self.adaptive_workload(24)
        allowed, reason, budget = self.allows(candidate, active)
        self.assertTrue(allowed, reason)
        self.assertEqual(budget['active_threads'], 96)
        self.assertEqual(budget['projected_td_memory_gib'], 300)
        self.assertEqual(budget['projected_td_cpu_cores'], 53)
        active, candidate = self.adaptive_workload(25)
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_TD_MEMORY_BUDGET')

    def test_recent_cpu_bursts_block_new_starts_below_memory_limit(self):
        active, candidate = self.adaptive_workload(12, cpu=3.5)
        allowed, reason, budget = self.allows(candidate, active)
        self.assertFalse(allowed)
        self.assertEqual(reason, 'WAITING_FOR_TD_CPU_BUDGET')
        self.assertEqual(budget['td_cpu_limit_cores'], 56)

    def test_actual_cpu_over_target_blocks_even_if_groups_are_temporarily_low(self):
        active, candidate = self.adaptive_workload(20)
        self.monitor.value['td_cpu_cores'] = 58
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_TD_CPU_BUDGET')

    def test_missing_controlled_group_keeps_full_startup_reservation(self):
        active, candidate = self.adaptive_workload(11)
        self.monitor.value['groups'] = {}
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_TD_CPU_BUDGET')

    def test_cold_project_starts_with_sixteen_gib_then_learns_with_headroom(self):
        active, candidate = self.adaptive_workload(0)
        self.monitor.history.clear()
        self.assertEqual(self.monitor.estimate(candidate['spec'])['memory_gib'], 16)
        self.monitor.history[self.monitor.key(candidate['spec'])] = {'rss_peak_gib': 9.257}
        self.assertEqual(self.monitor.estimate(candidate['spec'])['memory_gib'], 12)
        self.monitor.history[self.monitor.key(candidate['spec'])]['rss_peak_gib'] = 20.1
        self.assertEqual(self.monitor.estimate(candidate['spec'])['memory_gib'], 26)

    def test_external_cpu_and_low_available_memory_reduce_admission(self):
        active, candidate = self.adaptive_workload(10)
        self.monitor.value['host_busy_cores'] = 100
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_HOST_CPU')
        self.monitor.value['host_busy_cores'] = 11
        self.monitor.value['memory_headroom_gib'] = 20
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_HOST_MEMORY')

    def test_manual_td_is_counted_and_requires_a_warm_cpu_sample(self):
        active, candidate = self.adaptive_workload(10)
        self.monitor.value['groups']['manual:42'] = dict(cpu_cores=30, cpu_peak_recent=30, rss_gib=5, cpu_ready=True)
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_TD_CPU_BUDGET')
        self.monitor.value['groups']['manual:42']['cpu_ready'] = False
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_MANUAL_TD_SAMPLE')

    def test_actual_memory_growth_blocks_and_does_not_cancel_workers(self):
        active, candidate = self.adaptive_workload(20, rss=15)
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_TD_MEMORY_BUDGET')
        self.assertFalse(any(self.jobs.glob('*/CANCEL')))

    def test_adaptive_telemetry_stale_or_incomplete_stops_admission(self):
        active, candidate = self.adaptive_workload(1)
        self.monitor.value['sampled_at'] = 900
        self.assertEqual(self.allows(candidate, active)[1], 'RESOURCE_TELEMETRY_STALE')
        self.monitor.value.update(sampled_at=1000, complete=False)
        self.assertFalse(self.allows(candidate, active)[0])

    def test_adaptive_ramp_waits_thirty_seconds_between_starts(self):
        active, candidate = self.adaptive_workload(1)
        self.monitor.last_start = 980
        self.assertEqual(self.allows(candidate, active)[1], 'WAITING_FOR_START_INTERVAL')
        self.monitor.last_start = 970
        self.assertTrue(self.allows(candidate, active)[0])

    def test_cpu_recent_peak_holds_a_burst_for_three_samples(self):
        self.config.update(RESOURCE_DEFAULTS, max_parallel=0)
        record = self.record(threads=4)
        self.host()
        atomic_json(self.jobs / 'job1/worker.json', self.process(100, name='python'))
        self.process(101, parent=100)
        self.monitor.collect([record], 10)
        ticks = 0
        with patch('resources.os.sched_getaffinity', return_value=set(range(128)), create=True):
            for index, cpu in enumerate((4, 1, 1, 1), 1):
                ticks += cpu * 2000
                self.host(user=1000 + index * 128000, idle=9000 + index * 128000)
                self.process(101, parent=100, ticks=ticks)
                group = self.monitor.collect([record], 10 + 20 * index)['groups']['job1']
                self.assertEqual(group['cpu_peak_recent'], 4 if index < 4 else 1)
                self.assertEqual(group['cpu_ready'], index >= 2)

    def test_v66_upgrade_preserves_custom_tighter_limits_and_is_idempotent(self):
        old = dict(self.config, max_total_threads=32, memory_per_job_gib=24, max_host_cpu_percent=70)
        updated = install.upgrade_config(old)
        self.assertEqual(updated['max_total_threads'], 32)
        self.assertEqual(updated['memory_per_job_gib'], 24)
        self.assertEqual(updated['max_host_cpu_percent'], 70)
        self.assertEqual(updated['max_td_cpu_percent'], 50)
        self.assertEqual(install.upgrade_config(updated), updated)


if __name__ == '__main__':
    unittest.main()
