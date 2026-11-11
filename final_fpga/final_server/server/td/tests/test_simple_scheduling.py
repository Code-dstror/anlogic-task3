"""Remote admission settings and queue scheduling, with no real TD processes."""
from __future__ import annotations

from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'server/td/simple'))
import test_simple_controller as fixture
from common import (RESOURCE_DEFAULTS, atomic_json, encoded, job_threads, job_thread_reservation,
                    project_config, read_json, resource_policy)
import install
from resources import ResourceMonitor
from service import Controller


class SchedulingTests(unittest.TestCase):
    setUp = fixture.SimpleFixture.setUp
    tearDown = fixture.SimpleFixture.tearDown
    git = fixture.SimpleFixture.git
    write = fixture.SimpleFixture.write
    commit = fixture.SimpleFixture.commit
    push_source = fixture.SimpleFixture.push_source
    source_job = fixture.SimpleFixture.source_job

    def request(self, name, **fields):
        return self.controller.apply_command(name, dict(schema=1, id=name, **fields))

    def test_thread_and_priority_bounds_and_separate_synthesis_reservation(self):
        project = project_config(dict(self.project, threads=8, synth_threads=32, priority=100, max_parallel=4))
        spec = dict(project=project, seed=1)
        self.assertEqual(job_threads(spec), 8)
        self.assertEqual(job_thread_reservation(spec), 32)
        self.assertEqual(job_thread_reservation(dict(spec, resume={'checkpoint_level': 1})), 8)
        self.assertEqual(job_threads(dict(spec, project=dict(project, target='synth'))), 32)
        for change in ({'threads': 33}, {'synth_threads': 0}, {'max_parallel': -1}, {'priority': True}, {'priority': 101}):
            with self.assertRaises(ValueError):
                project_config(dict(project, **change))

    def test_policy_is_persistent_atomic_and_does_not_rewrite_server_config(self):
        original = (self.root / 'config.json').read_bytes()
        receipt = self.request('policy1', action='policy', policy={'max_parallel': 4, 'max_threads_per_job': 32})
        self.assertEqual(receipt['resource_policy']['max_parallel'], 4)
        self.assertEqual(self.controller.resources.config['max_parallel'], 4)
        self.assertEqual((self.root / 'config.json').read_bytes(), original)
        restarted = Controller(self.root)
        self.assertEqual(restarted.config['max_parallel'], 4)
        self.assertEqual(restarted.config['max_threads_per_job'], 32)
        self.assertEqual(restarted.snapshot()['capabilities']['max_threads'], 32)
        before = self.controller.store.get('resource_policy_overrides')
        for bad in ({'max_parallel': -1}, {'max_cpu_percent': 51}, {'max_td_memory_gib': 301},
                    {'poll_seconds': 5}, {'td_root': '/elsewhere'}, {'max_total_threads': True}):
            with self.assertRaises(ValueError):
                self.request('badpolicy', action='policy', policy=bad)
            self.assertEqual(self.controller.store.get('resource_policy_overrides'), before)

    def test_update_migrates_only_old_default_eight_threads(self):
        for old, expected in ((8, 32), (4, 4)):
            upgraded = install.upgrade_config(dict(RESOURCE_DEFAULTS, resource_policy_version=2,
                                                   max_threads_per_job=old, max_parallel=3))
            self.assertEqual(upgraded['max_threads_per_job'], expected)
            self.assertEqual(upgraded['max_parallel'], 0)
        current = install.upgrade_config(dict(RESOURCE_DEFAULTS, max_threads_per_job=8))
        self.assertEqual(current['max_threads_per_job'], 8)

    def test_shared_synthesis_has_its_own_threads_and_retains_physical_threads(self):
        old = self.source_job()
        self.controller.store.state(old['id'], 'DONE')
        receipt = self.request('mixedthreads', action='build', project='camera', seeds=[1, 2], threads=8, synth_threads=32)
        records = {record['id']: record for record in self.controller.store.jobs()}
        synthesis = records[receipt['synthesis_job']]
        self.assertEqual(job_threads(synthesis['spec']), 32)
        for job in receipt['jobs']:
            self.assertEqual(job_thread_reservation(records[job]['spec']), 8)
            self.assertEqual(records[job]['spec']['resume']['synthesis_threads'], 32)

    def test_hard_thread_policy_rejects_before_queueing(self):
        self.source_job()
        self.request('policy8', action='policy', policy={'max_threads_per_job': 8})
        before = len(self.controller.store.jobs())
        with self.assertRaisesRegex(ValueError, 'active server policy'):
            self.request('wide', action='build', project='camera', threads=32)
        self.assertEqual(len(self.controller.store.jobs()), before)

    def test_build_reset_drops_inherited_selected_run_overrides(self):
        self.source_job()
        inherited = dict(self.project, td_options={'syn_1': {'rtl': {'min_control_set': 2}},
                                                   'phy_1': {'place': {'effort': 'high'}}},
                         td_strategies={'syn_1': 'RuntimeOptimize', 'phy_1': 'TimingHigh'})
        self.controller.store.put('projects', [inherited])
        receipt = self.request('reset', action='build', project='camera', td_reset=['syn_1'])
        project = next(record['spec']['project'] for record in self.controller.store.jobs() if record['id'] == receipt['jobs'][0])
        self.assertNotIn('syn_1', project['td_options'])
        self.assertNotIn('syn_1', project['td_strategies'])
        self.assertIn('phy_1', project['td_options'])
        self.assertIn('syn_1', self.controller.store.get('projects')[0]['td_options'])
        receipt = self.request('reset-explicit', action='build', project='camera', td_reset=['syn_1'],
                               td_options={'syn_1': {'rtl': {'min_control_set': 4}}})
        project = next(record['spec']['project'] for record in self.controller.store.jobs() if record['id'] == receipt['jobs'][0])
        self.assertEqual(project['td_options']['syn_1']['rtl']['min_control_set'], 4)

    def test_old_v3_automatic_identity_and_schedule_only_push_do_not_recompile(self):
        commit = self.git('rev-parse', 'HEAD')
        spec = dict(id='auto-camera-v3-existing-s1', source_commit=commit,
                    project=dict(self.project, memory_gib=64), seed=1, trigger='project-push')
        self.controller.store.enqueue(spec)
        self.controller.source_poll()
        self.assertEqual([record['id'] for record in self.controller.store.jobs()], [spec['id']])
        project = dict(self.project, priority=20, max_parallel=2, memory_gib=128)
        self.write('server/td/projects.json', encoded(dict(schema=1, projects=[project])).decode())
        self.commit('Scheduling configuration only')
        self.push_source()
        self.controller.source_poll()
        self.assertEqual([record['id'] for record in self.controller.store.jobs()], [spec['id']])
        self.assertEqual(self.controller.store.jobs()[0]['spec']['project']['memory_gib'], 64)

    def test_existing_queue_reports_fixed_memory_without_rewriting_source_spec(self):
        self.controller.config['max_parallel']=0
        spec=dict(id='legacy-memory',source_commit='a'*40,project=dict(self.project,memory_gib=48,max_parallel=8),seed=1)
        self.controller.store.enqueue(spec)
        row=next(j for j in self.controller.snapshot()['jobs'] if j['id']==spec['id'])
        self.assertEqual(row['reserved_memory_gib'],16)
        self.assertEqual(row['requested_memory_gib'],48)
        self.assertEqual(row['effective_config']['memory_gib'],16)
        self.assertEqual(row['effective_config']['max_parallel'],0)
        self.assertEqual(row['requested_max_parallel'],8)
        self.assertEqual(self.controller.store.jobs()[0]['spec']['project']['memory_gib'],48)
        self.controller.store.state(spec['id'],'DONE')
        row=next(j for j in self.controller.snapshot()['jobs'] if j['id']==spec['id'])
        self.assertIsNone(row['reserved_memory_gib'])
        self.assertEqual(row['effective_config']['memory_gib'],48)

    def queued(self, name, priority=0, threads=8):
        project = dict(self.project, priority=priority, threads=threads)
        spec = dict(id=name, source_commit='a' * 40, project=project, seed=1)
        self.controller.store.enqueue(spec)
        atomic_json(self.controller.jobs_root / name / 'READY', {})
        return name

    def test_dispatch_priority_fifo_and_backfills_a_resource_blocked_head(self):
        self.queued('low-first', priority=0)
        self.queued('wide-first', priority=20, threads=32)
        self.queued('high-first', priority=10)
        self.queued('high-second', priority=10)
        def allows(record, active):
            return record['id'] != 'wide-first', 'READY' if record['id'] != 'wide-first' else 'WAITING_FOR_TD_CPU_BUDGET', {}
        with patch.object(self.controller.resources, 'sample'), \
                patch.object(self.controller.resources, 'allows', side_effect=allows), \
                patch('service.subprocess.Popen', return_value=SimpleNamespace(poll=lambda: None)) as launch:
            self.controller.dispatch()
        self.assertEqual(launch.call_args.args[0][-3], 'high-first')
        states = {record['id']: record['state'] for record in self.controller.store.jobs()}
        self.assertEqual(states['high-first'], 'STARTING')
        self.assertEqual(states['high-second'], 'QUEUED')
        snapshots = {job['id']: job for job in self.controller.snapshot()['jobs']}
        self.assertEqual(snapshots['wide-first']['waiting_reason'], 'WAITING_FOR_TD_CPU_BUDGET')
        self.assertEqual(snapshots['high-first']['effective_config']['priority'], 10)

    def test_project_parallel_limit_does_not_limit_another_project(self):
        monitor = self.controller.resources
        monitor.config['max_parallel'] = 8
        monitor.value = dict(complete=True, sampled_at=1000, effective_cpu_cores=256, host_cpu_count=256,
                             td_cpu_cores=0, td_rss_gib=0, host_busy_cores=0, memory_headroom_gib=1000, groups={})
        spec = dict(project=dict(self.project, max_parallel=1), seed=1, resume={'checkpoint_level': 1})
        active = [dict(id='active', spec=spec)]
        candidate = dict(id='next', spec=spec)
        with patch('resources.time.time', return_value=1000):
            self.assertEqual(monitor.allows(candidate, active)[1], 'WAITING_FOR_PROJECT_SLOT')
            candidate['spec'] = dict(spec, project=dict(spec['project'], id='other'))
            self.assertTrue(monitor.allows(candidate, active)[0])

    def test_reused_synthesis_candidate_does_not_wait_for_synthesis_slot(self):
        monitor = self.controller.resources
        monitor.config['max_parallel'] = 8
        monitor.config['max_synth_parallel'] = 1
        monitor.value = dict(complete=True, sampled_at=1000, effective_cpu_cores=256, host_cpu_count=256,
                             td_cpu_cores=0, td_rss_gib=0, host_busy_cores=0, memory_headroom_gib=1000, groups={})
        active = [dict(id='active', spec=dict(project=self.project, seed=1))]
        candidate = dict(id='resumed', spec=dict(project=self.project, seed=1, resume={'checkpoint_level': 1}))
        with patch('resources.time.time', return_value=1000):
            self.assertTrue(monitor.allows(candidate, active)[0])


if __name__ == '__main__':
    unittest.main()
