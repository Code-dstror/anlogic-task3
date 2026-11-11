"""Regression checks for relocated native checkpoints and exact thread sums."""
from __future__ import annotations

import hashlib
from pathlib import Path
import random
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'server/td/simple'))
from common import RESOURCE_DEFAULTS, project_config
from flow import build_script, canonical_project_paths
import install
from resources import ResourceMonitor


class ExactBudgetTests(unittest.TestCase):
    def setUp(self):
        directory = ROOT / 'server/td/local/simple-tests'
        directory.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=directory)
        self.root = Path(self.temporary.name)
        self.config = dict(RESOURCE_DEFAULTS, resource_policy_version=5, max_parallel=8,
                           max_total_threads=64, memory_per_job_gib=16, memory_growth_factor=1.5, cpu_growth_factor=1)
        self.monitor = ResourceMonitor(self.root, self.config, self.root / 'jobs')
        self.monitor.value = dict(complete=True, state='READY', sampled_at=1000,
                                  effective_cpu_cores=112, host_cpu_count=112,
                                  td_cpu_cores=0, td_rss_gib=0, host_busy_cores=0,
                                  memory_headroom_gib=1000, groups={})

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def record(number, threads, synth=False):
        return dict(id='job' + str(number), state='RUNNING', spec=dict(seed=1,
                    project=dict(id='camera', root='.', al='camera.al', threads=threads,
                                 target='synth' if synth else 'full'),
                    **({} if synth else {'resume': {'checkpoint_level': 1}})))

    def admits(self, candidate, active):
        with patch('resources.time.time', return_value=1000):
            return self.monitor.allows(candidate, active)

    def test_arbitrary_compositions_of_sixty_four_threads_are_admitted(self):
        combinations = [[8] * 8, [8, 8, 16, 32], [32, 32], [16] * 4,
                        [4,4,8,16,32], [2,2,4,8,16,32], [1,1,2,4,8,16,32]]
        generator = random.Random(20261022)
        while len(combinations) < 134:
            count = generator.randint(2, 8)
            values = generator.choices([1,2,4,8,16,32],k=count)
            if sum(values) == 64:
                generator.shuffle(values)
                combinations.append(values)
        for values in combinations:
            with self.subTest(threads=values):
                active = [self.record(number, threads, synth=number % 2 == 0)
                          for number, threads in enumerate(values[:-1])]
                candidate = self.record(99, values[-1], synth=True)
                self.assertEqual(sum(values), 64)
                self.assertTrue(self.admits(candidate, active)[0])
                self.assertEqual(self.monitor.forecast(active)['active_threads'], sum(values[:-1]))

    def test_all_eight_synthesis_processes_can_reserve_eight_threads(self):
        active = [self.record(number, 8, synth=True) for number in range(7)]
        self.assertEqual(self.config['max_synth_parallel'], 0)
        self.assertTrue(self.admits(self.record(8, 8, synth=True), active)[0])
        self.assertEqual(self.admits(self.record(8, 16, synth=True), active)[1], 'WAITING_FOR_THREAD_BUDGET')

    def test_old_cpu_percentage_margin_and_history_do_not_reduce_thread_budget(self):
        self.config.update(max_cpu_percent=50, cpu_growth_factor=1.25)
        active = [self.record(number, 8) for number in range(7)]
        candidate = self.record(8, 8)
        self.monitor.history[self.monitor.key(candidate['spec'])] = {'cpu_peak_cores': 20}
        self.monitor.value.update(td_cpu_cores=56, host_busy_cores=56,
                                  groups={'idle-gui': {'cpu_cores': .02, 'rss_gib': 1}})
        self.assertEqual(self.monitor.estimate(candidate['spec'])['cpu_cores'], 8)
        self.assertEqual(self.monitor.forecast(active)['td_cpu_reserved_cores'], 56)
        self.assertTrue(self.admits(candidate, active)[0])

    def test_memory_host_capacity_and_host_load_still_gate_admission(self):
        candidate = self.record(1, 32)
        self.monitor.value['memory_headroom_gib'] = 10
        self.assertEqual(self.admits(candidate, [])[1], 'WAITING_FOR_HOST_MEMORY')
        self.monitor.value.update(memory_headroom_gib=1000, effective_cpu_cores=16)
        self.assertEqual(self.admits(candidate, [])[1], 'WAITING_FOR_CPU_CAPACITY')
        self.monitor.value.update(effective_cpu_cores=112, host_busy_cores=90)
        self.assertEqual(self.admits(candidate, [])[1], 'WAITING_FOR_HOST_CPU')

    def test_install_migrates_the_old_margin_and_default_synthesis_limit(self):
        upgraded = install.upgrade_config(dict(RESOURCE_DEFAULTS, resource_policy_version=3,
                                              cpu_growth_factor=1.25, max_synth_parallel=4,
                                              max_total_threads=32))
        self.assertEqual(upgraded['cpu_growth_factor'], 1.25)
        self.assertEqual(upgraded['max_synth_parallel'], 0)
        self.assertEqual(upgraded['max_total_threads'], 128)
        self.assertEqual(install.upgrade_resource_overrides(
            dict(cpu_growth_factor=1.25, max_cpu_percent=50, max_total_threads=32,
                 max_synth_parallel=4, memory_growth_factor=1.5), 3), {})


class CanonicalCheckpointTests(unittest.TestCase):
    def setUp(self):
        directory = ROOT / 'server/td/local/simple-tests'
        directory.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=directory)
        self.root = Path(self.temporary.name)
        self.checkout = self.root / 'checkout'
        self.project_dir = self.checkout / 'fpga_prj'
        shutil.copytree(ROOT / 'server/td/examples/smoke', self.project_dir)

    def tearDown(self):
        self.temporary.cleanup()

    def test_equivalent_constraint_and_include_aliases_are_canonicalized(self):
        (self.project_dir / 'include').mkdir()
        source = self.project_dir / 'td_smoke.al'
        text = source.read_text().replace('Path="td_smoke.adc"', 'Path="../fpga_prj/td_smoke.adc"')
        text = text.replace('Path="td_smoke.sdc"', 'Path="../fpga_prj/./td_smoke.sdc"')
        text = text.replace('<Property>', '<Property><Option Name="IncludeDir" Val="../fpga_prj/include"/>')
        canonical = canonical_project_paths(text, self.project_dir)
        before = ET.fromstring(text.replace('UsedInP&R', 'UsedInP&amp;R'))
        after = ET.fromstring(canonical.replace('UsedInP&R', 'UsedInP&amp;R'))
        for original, normalized in zip(before.findall('.//Source_Files//File'), after.findall('.//Source_Files//File')):
            self.assertEqual((self.project_dir / original.get('Path')).resolve(),
                             (self.project_dir / normalized.get('Path')).resolve())
        self.assertIn('Path="td_smoke.adc"', canonical)
        self.assertIn('Path="td_smoke.sdc"', canonical)
        self.assertIn('Val="include"', canonical)
        self.assertEqual(canonical_project_paths(canonical, self.project_dir), canonical)

    def test_resumed_build_changes_only_job_al_not_database_or_snapshot_or_inputs(self):
        al = self.project_dir / 'td_smoke.al'
        al.write_text(al.read_text().replace('Path="td_smoke.sdc"', 'Path="../fpga_prj/td_smoke.sdc"'))
        run = self.project_dir / 'td_smoke_Runs/syn_1'
        run.mkdir(parents=True)
        (run / 'td_smoke_gate.db').write_bytes(b'completed native database')
        (run / 'td_smoke.prj').write_text('<Project><File Path="../../td_smoke.sdc"/></Project>')
        tracked = [run / 'td_smoke_gate.db', run / 'td_smoke.prj', self.project_dir / 'td_smoke.sdc']
        hashes = [hashlib.sha256(path.read_bytes()).digest() for path in tracked]
        project = project_config(dict(id='probe', root='.', al='fpga_prj/td_smoke.al', threads=8, target='place'))
        build_script(self.checkout, dict(project=project, seed=1, resume={'checkpoint_level': 1, 'rollback_steps': 0}), self.root / 'build.tcl')
        self.assertEqual(hashes, [hashlib.sha256(path.read_bytes()).digest() for path in tracked])
        self.assertIn('Path="td_smoke.sdc"', al.read_text())
        self.assertNotIn('reset_runs syn_1', (self.root / 'build.tcl').read_text())


if __name__ == '__main__':
    unittest.main()
