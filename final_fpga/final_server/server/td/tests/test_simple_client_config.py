"""Exercise remote run configuration publication without contacting GitHub or TD."""
from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
TEST_TEMP = ROOT / 'server/td/local/simple-tests'
TEST_TEMP.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / 'server/td/simple'))
import client
from common import COMMAND_BRANCH, REMOTE, RESOURCE_DEFAULTS, RESULT_BRANCH, capabilities


class ClientConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=TEST_TEMP)
        self.root = Path(self.temporary.name)
        self.published = []
        self.fetches = []
        self.status = dict(generated_at=1000, controller_version='2026.10.22-run-config-v4',
                           capabilities=capabilities(), resource_policy=dict(RESOURCE_DEFAULTS, max_parallel=8))
        owner = self

        class FakeGit:
            def __init__(self, path, remote):
                self.path = Path(path)
                if remote != REMOTE:
                    raise AssertionError('Unexpected remote')

            @staticmethod
            def execute(arguments, repo):
                if arguments == ['config', '--get', 'remote.origin.url']:
                    return (REMOTE + '\n').encode()
                if arguments == ['rev-parse', 'HEAD']:
                    return b'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
                raise AssertionError('Unexpected local Git command: ' + repr(arguments))

            def fetch(self, branch):
                owner.fetches.append(branch)
                return 'b' * 40

            def blob(self, commit, path, **unused):
                if path != 'status.json':
                    raise AssertionError('Unexpected result lookup: ' + path)
                return json.dumps(owner.status).encode()

            def publish(self, branch, files, message):
                if branch != COMMAND_BRANCH or len(files) != 1:
                    raise AssertionError('Unexpected publication')
                owner.published.append(json.loads(next(iter(files.values()))))
                return 'c' * 40

        self.git = FakeGit

    def tearDown(self):
        self.temporary.cleanup()

    def configuration(self, value, name='configuration.json'):
        path = self.root / name
        path.write_text(json.dumps(value), encoding='utf-8')
        return str(path)

    def invoke(self, *arguments):
        action = arguments[0]
        argv = ['client.py', '--repo', str(self.root), '--cache', str(self.root / 'cache'),
                action, *arguments[1:], '--request-id', 'test-request']
        with patch.object(client, 'Git', self.git), patch.object(sys, 'argv', argv), \
                patch('client.time.time', return_value=1000), contextlib.redirect_stdout(io.StringIO()):
            return client.main()

    def test_build_with_project_alone_preserves_manifest_configuration(self):
        self.assertEqual(self.invoke('build', '--project', 'camera'), 0)
        request = self.published[0]
        self.assertEqual(request, dict(schema=1, id='test-request', action='build',
                                       project='camera', commit='a' * 40))
        self.assertNotIn(RESULT_BRANCH, self.fetches)

    def test_explicit_cli_values_override_configuration_file(self):
        path = self.configuration(dict(target='synth', threads=16, seeds=[1, 11],
                                       memory_gib=48, max_parallel=2, priority=10))
        self.invoke('build', '--project', 'camera', '--config', path,
                    '--target', 'route', '--threads', '32', '--seeds', '7', '--memory-gib', '64')
        request = self.published[0]
        self.assertEqual(request['target'], 'route')
        self.assertEqual(request['threads'], 32)
        self.assertEqual(request['seeds'], [7])
        self.assertEqual(request['memory_gib'], 64)
        self.assertEqual(request['max_parallel'], 2)
        self.assertEqual(request['priority'], 10)

    def test_native_strategy_and_reset_configuration_are_published_intact(self):
        values = dict(threads=32, synth_threads=16, max_parallel=1, priority=20,
                      td_strategies={'syn_1': 'RuntimeOptimize', 'phy_1': 'RuntimeOptimize'},
                      td_reset=['syn_1', 'phy_1'], td_options={'phy_1': {'route': {'fix_hold': 'on'}}})
        self.invoke('build', '--config', self.configuration(values))
        self.assertTrue(all(self.published[0][key] == value for key, value in values.items()))
        self.assertIn(RESULT_BRANCH, self.fetches)

    def test_basic_eight_thread_request_still_works_with_v3(self):
        self.status.pop('capabilities')
        self.status['controller_version'] = '2026.10.22-stage-logs-v3'
        self.invoke('build', '--threads', '8', '--seeds', '1')
        self.assertEqual(self.published[0]['threads'], 8)
        self.assertNotIn(RESULT_BRANCH, self.fetches)

    def test_v3_rejects_unsupported_thirty_two_thread_request_before_publication(self):
        self.status.pop('capabilities')
        self.status['controller_version'] = '2026.10.22-stage-logs-v3'
        with self.assertRaises(ValueError):
            self.invoke('build', '--threads', '32')
        self.assertEqual(self.published, [])

    def test_stale_capabilities_do_not_authorize_new_configuration(self):
        self.status['generated_at'] = 800
        with self.assertRaises(ValueError):
            self.invoke('build', '--config', self.configuration({'max_parallel': 2}))
        self.assertEqual(self.published, [])

    def test_capability_thread_limit_is_checked_before_publication(self):
        self.status['capabilities']['max_threads'] = 16
        with self.assertRaises(ValueError):
            self.invoke('build', '--threads', '32')
        self.assertEqual(self.published, [])

    def test_active_thread_policy_is_checked_even_when_program_supports_thirty_two(self):
        self.status['resource_policy']['max_threads_per_job'] = 8
        with self.assertRaises(ValueError):
            self.invoke('build', '--threads', '32')
        self.assertEqual(self.published, [])

    def test_per_seed_thread_override_uses_new_capabilities(self):
        self.invoke('build', '--seeds', '1', '11', '--seed-threads', '1:32', '11:8')
        self.assertEqual(self.published[0]['seed_threads'], {'1': 32, '11': 8})
        self.assertIn(RESULT_BRANCH, self.fetches)

    def test_policy_file_publishes_only_bounded_policy_action(self):
        value = dict(max_parallel=4, max_total_threads=48, max_host_cpu_percent=80)
        self.invoke('policy', '--file', self.configuration(value))
        self.assertEqual(self.published[0], dict(schema=1, id='test-request', action='policy', policy=value))
        self.assertIn(RESULT_BRANCH, self.fetches)

    def test_policy_rejects_retired_cpu_rule_thread_overflow_and_server_paths(self):
        for value in ({'max_cpu_percent': 50}, {'cpu_growth_factor': 1.25},
                      {'max_total_threads': 257}, {'max_td_cpu_percent': 51}, {'td_root': '/unregistered/td'}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.invoke('policy', '--file', self.configuration(value))
        self.assertEqual(self.published, [])

    def test_unknown_build_configuration_field_is_rejected_locally(self):
        with self.assertRaises(ValueError):
            self.invoke('build', '--config', self.configuration({'shell': 'anything'}))
        self.assertEqual(self.published, [])

    def test_unsupported_native_thread_values_never_reach_publication(self):
        for value in [3, 12, 20, 24, 31, 'auto', True]:
            for field in ['threads', 'synth_threads']:
                with self.subTest(value=value,field=field), self.assertRaises(ValueError):
                    self.invoke('build', '--config', self.configuration({field:value}))
        with self.assertRaises(ValueError):
            self.invoke('continue', '--job', 'parent', '--seeds', '1', '--seed-threads', '1:12')
        self.assertEqual(self.published, [])

    def test_server_native_value_receipt_is_checked_before_publication(self):
        self.status['capabilities']['native_thread_values'] = [1, 2, 4, 8]
        with self.assertRaises(ValueError):
            self.invoke('build','--threads','16')
        self.assertEqual(self.published, [])

    def test_large_batch_and_resource_budget_mode_are_not_fixed_seed_caps(self):
        self.invoke('build','--seed-count','32','--max-parallel','0')
        self.assertEqual(self.published[0]['seeds'],list(range(1,33)))
        self.assertEqual(self.published[0]['max_parallel'],0)

    def test_native_seed_bounds_are_preserved(self):
        self.invoke('build', '--seeds', '0', '1000')
        self.assertEqual(self.published[0]['seeds'], [0, 1000])

    def test_ignored_seeds_are_rejected_before_publication(self):
        cases = [
            ('build', '--seeds', '1001'),
            ('build', '--seeds', '2858', '50690'),
            ('continue', '--job', 'parent', '--seed-threads', '1001:4'),
            ('build', '--seed-count', '1001'),
            ('build', '--config', self.configuration({'seeds': [176, 1491]})),
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments), self.assertRaisesRegex(ValueError, '0..1000'):
                self.invoke(*arguments)
        self.assertEqual(self.published, [])

    def test_legacy_controller_limits_are_checked_before_publication(self):
        self.status['capabilities'].pop('resource_driven_parallelism')
        self.status['capabilities']['max_seeds']=24
        for args in [('build','--seed-count','32'),('build','--max-parallel','0')]:
            with self.subTest(args=args),self.assertRaises(ValueError):self.invoke(*args)
        self.assertEqual(self.published,[])


if __name__ == '__main__':
    unittest.main()
