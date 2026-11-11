"""Exercise the new controller against real local Git repositories and fake TD."""
from __future__ import annotations

import io
import json
import logging
import os
from pathlib import Path
import shutil
import sys
import threading
import subprocess
import tempfile
import tarfile
import tkinter
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import urllib.parse

ROOT = Path(__file__).resolve().parents[3]
TEST_TEMP = ROOT / 'server/td/local/simple-tests'
TEST_TEMP.mkdir(parents=True, exist_ok=True)
tempfile.tempdir = str(TEST_TEMP)
sys.path.insert(0, str(ROOT / 'server/td/simple'))
from common import (COMMAND_BRANCH, REMOTE, RESULT_BRANCH, SOURCE_BRANCH, FileLock,
                    atomic_json, digest, encoded, read_json)
from checkpoints import copy_checkpoint
from client import receive
from flow import build_script, stage_status, timing_status
from logs import capture_stage
import worker
import network
import install
from make_private_bundle import bundle
from service import Controller
from transport import Git, GitError


class SimpleFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.repo = self.base / 'source'
        self.repo.mkdir()
        self.git('init')
        self.git('checkout', '-b', SOURCE_BRANCH)
        self.project = dict(id='camera', root='candidate', al='fpga_prj/camera.al',
                            watch=['src_fpga/rtl', 'src_fpga/ip', 'fpga_prj'],
                            enabled=True, target='full', threads=8, seeds=[1])
        self.write('candidate/src_fpga/rtl/top.v', 'module top(input clk); endmodule\n')
        self.write('candidate/src_fpga/ip/README.txt', 'controlled IP fixture\n')
        self.write('candidate/fpga_prj/camera.al', '''<Project Path="."><Name>camera</Name>
            <HardWare><Device>PH1A90SEG324</Device><Speed>-2</Speed></HardWare>
            <Source_Files><Verilog><File Path="../src_fpga/rtl/top.v"/></Verilog></Source_Files>
            </Project>''')
        self.write('server/td/projects.json', encoded(dict(schema=1, projects=[self.project])).decode())
        self.commit('Initial camera project')
        self.remote = self.base / 'remote.git'
        Git.execute(['clone', '--bare', str(self.repo), str(self.remote)], self.base)
        self.root = self.base / 'controller'
        self.root.mkdir()
        atomic_json(self.root / 'config.json', dict(
            remote=REMOTE, source_branch=SOURCE_BRANCH, command_branch=COMMAND_BRANCH,
            result_branch=RESULT_BRANCH, project_manifest='server/td/projects.json',
            fallback_projects=[self.project], td_root=str(self.base / 'td'),
            poll_seconds=60, max_parallel=1, max_cpu_percent=50, min_free_memory_gib=16))
        self.redirect = patch('service.Git', side_effect=lambda path, remote, seed=None, **kwargs: Git(path, str(self.remote), **kwargs))
        self.redirect.start()
        self.controller = Controller(self.root)

    def tearDown(self):
        self.redirect.stop()
        for handler in tuple(self.controller.log.handlers):
            handler.close()
            self.controller.log.removeHandler(handler)
        self.temporary.cleanup()

    def git(self, *arguments):
        return Git.execute(list(arguments), self.repo).decode().strip()

    def write(self, path, text):
        destination = self.repo / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text, encoding='utf-8')

    def commit(self, message):
        self.git('add', '.')
        self.git('commit', '-q', '-m', message)
        return self.git('rev-parse', 'HEAD')

    def push_source(self):
        self.git('push', str(self.remote), 'HEAD:refs/heads/' + SOURCE_BRANCH)

    def source_job(self):
        self.controller.source_poll()
        return self.controller.store.jobs()[0]

    def terminal_job(self, body=b'full native log\n'):
        record = self.source_job()
        folder = self.root / 'jobs' / record['id']
        (folder / 'td.log').write_bytes(body)
        atomic_json(folder / 'result.json', dict(state='DONE', timing={'state': 'NEGATIVE'}))
        self.controller.store.state(record['id'], 'DONE')
        return record, folder

    def test_project_push_and_restart_do_not_duplicate_a_build(self):
        record = self.source_job()
        self.assertTrue((self.root / 'jobs' / record['id'] / 'READY').is_file())
        restarted = Controller(self.root)
        restarted.source_poll()
        self.assertEqual(len(restarted.store.jobs()), 1)
        self.write('candidate/README.md', 'Only documentation changes\n')
        self.commit('Documentation')
        self.push_source()
        restarted.source_poll()
        self.assertEqual(len(restarted.store.jobs()), 1)
        self.write('candidate/src_fpga/rtl/top.v', 'module top(input clk, input reset); endmodule\n')
        changed_commit = self.commit('Change actual hardware')
        self.push_source()
        restarted.source_poll()
        self.assertEqual(len(restarted.store.jobs()), 2)
        self.assertEqual(restarted.store.jobs()[-1]['spec']['source_commit'], changed_commit)

    def test_command_receipts_survive_restart_and_prevent_replay(self):
        self.source_job()
        sender = Git(self.base / 'sender.git', str(self.remote))
        request = dict(schema=1, id='build-camera', action='build', project='camera', seeds=[1, 6])
        sender.publish(COMMAND_BRANCH, {'requests/build-camera.json': encoded(request)}, 'Build request')
        self.controller.command_poll()
        self.assertEqual(len(self.controller.store.jobs()), 4)
        restarted = Controller(self.root)
        restarted.command_poll()
        self.assertEqual(len(restarted.store.jobs()), 4)
        with restarted.store.connection() as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM commands').fetchone()[0], 1)

    def test_invalid_command_has_no_side_effects(self):
        self.source_job()
        with self.assertRaises(ValueError):
            self.controller.apply_command('bad-pause', dict(schema=1, id='bad-pause', action='pause', shell='anything'))
        self.assertFalse(self.controller.store.get('paused', False))

    def test_pause_cancel_and_resume_preserve_other_jobs(self):
        record = self.source_job()
        self.controller.apply_command('pause', dict(schema=1, id='pause', action='pause'))
        self.controller.dispatch()
        self.assertEqual(self.controller.admission, 'PAUSED')
        self.controller.apply_command('cancel', dict(schema=1, id='cancel', action='cancel', job=record['id']))
        self.assertEqual(self.controller.store.jobs()[0]['state'], 'CANCELLED')
        self.controller.apply_command('resume', dict(schema=1, id='resume', action='resume'))
        self.assertFalse(self.controller.store.get('paused'))

    def test_controller_restart_adopts_a_live_worker_lock(self):
        record = self.source_job()
        self.controller.store.state(record['id'], 'RUNNING')
        with FileLock(self.root / 'jobs' / record['id'] / 'worker.lock'):
            restarted = Controller(self.root)
            restarted.reconcile()
            self.assertEqual(restarted.store.jobs()[0]['state'], 'RUNNING')
        restarted.reconcile()
        self.assertEqual(restarted.store.jobs()[0]['state'], 'INTERRUPTED')
        restarted.source_poll()
        self.assertEqual(len(restarted.store.jobs()), 1)

    def test_new_queue_waits_for_old_workers_and_then_drops_the_old_farm_dependency(self):
        self.controller.config['legacy_farm'] = str(self.base / 'td_farm')
        with patch('service.legacy_workers', return_value=['old-worker']):
            self.controller.dispatch()
        self.assertIn('WAITING_FOR_LEGACY_WORKERS', self.controller.admission)
        with patch('service.legacy_workers', return_value=[]):
            self.controller.dispatch()
        self.assertIsNone(read_json(self.root / 'config.json')['legacy_farm'])

    def test_source_export_recovers_after_atomic_rename_before_ready(self):
        record = self.source_job()
        (self.root / 'jobs' / record['id'] / 'READY').unlink()
        self.controller.source_poll()
        self.assertEqual(self.controller.store.jobs()[0]['state'], 'QUEUED')
        self.assertTrue((self.root / 'jobs' / record['id'] / 'READY').exists())

    def test_git_symlink_cannot_escape_a_source_export(self):
        self.source_job()
        oid = Git.execute(['hash-object', '-w', '--stdin'], self.repo,
                          data=b'../../../../outside').decode().strip()
        self.git('update-index', '--add', '--cacheinfo', '120000', oid, 'candidate/src_fpga/rtl/escape')
        self.git('commit', '-q', '-m', 'Malformed linked source')
        self.push_source()
        self.controller.source_poll()
        records = self.controller.store.jobs()
        self.assertEqual(len(records), 2)
        self.assertEqual(records[-1]['state'], 'FAILED')
        self.assertFalse((self.base / 'outside').exists())

    def test_project_runs_can_live_outside_the_controller_directory(self):
        config = read_json(self.root / 'config.json')
        config['jobs_root'] = str(self.base / 'fpga_projects/builds')
        atomic_json(self.root / 'config.json', config)
        controller = Controller(self.root)
        controller.source_poll()
        record = controller.store.jobs()[0]
        self.assertTrue((Path(config['jobs_root']) / record['id'] / 'READY').is_file())
        files, unused_ledger, unused_pending = controller.artifact_plan()
        self.assertIn('jobs/' + record['id'] + '/artifacts.json', files)

    def test_outage_does_not_lose_results_and_unknown_push_outcome_is_idempotent(self):
        record, folder = self.terminal_job(b'log retained throughout a six hour outage\n')
        self.controller.publisher = Git(self.root / 'git/results.git', str(self.remote))
        with patch.object(self.controller.publisher, 'publish', side_effect=GitError('network unavailable')):
            with patch('service.time.time', return_value=1900000000 + 6 * 3600):
                with self.assertRaises(GitError):
                    self.controller.publish_poll()
        self.assertFalse((self.root / 'uploaded.json').exists())
        self.assertIn(b'six hour outage', (folder / 'td.log').read_bytes())
        actual_publish = self.controller.publisher.publish
        def accepted_then_connection_lost(*arguments):
            actual_publish(*arguments)
            raise GitError('connection lost after accepted push')
        with patch.object(self.controller.publisher, 'publish', side_effect=accepted_then_connection_lost):
            with self.assertRaises(GitError):
                self.controller.publish_poll()
        self.assertFalse((self.root / 'uploaded.json').exists())
        self.controller.publish_poll()
        self.assertTrue((self.root / 'uploaded.json').is_file())
        receiver = Git(self.base / 'receiver.git', str(self.remote))
        head = receiver.fetch(RESULT_BRANCH)
        destination = self.base / 'download'
        result = receive(receiver, head, record['id'], destination)
        self.assertEqual(result['pending'], [])
        self.assertEqual((destination / 'td.log').read_bytes(), (folder / 'td.log').read_bytes())

    def test_log_chunks_resume_without_republishing_acknowledged_parts(self):
        record, folder = self.terminal_job(bytes(range(256)) * 3)
        with patch('service.CHUNK_BYTES', 64):
            files, ledger, pending = self.controller.artifact_plan(budget=128)
            self.assertGreater(pending, 0)
            atomic_json(self.root / 'uploaded.json', ledger)
            next_files, next_ledger, next_pending = self.controller.artifact_plan(budget=128)
            old_parts = {name for name in files if name.startswith('chunks/')}
            new_parts = {name for name in next_files if name.startswith('chunks/')}
            self.assertTrue(new_parts - old_parts)
            self.assertGreater(next_pending, 0)

    def test_continuous_publish_drains_backlog_then_returns_to_idle_polling(self):
        record, folder = self.terminal_job(bytes(range(256)) * 6)
        plan = self.controller.artifact_plan
        waits = []
        def wait(seconds):
            waits.append(seconds)
            if seconds > 0 or len(waits) > 30:
                self.controller.stop.set()
        with patch('service.CHUNK_BYTES', 64), \
                patch.object(self.controller, 'artifact_plan', side_effect=lambda: plan(budget=256)), \
                patch.object(self.controller.stop, 'wait', side_effect=wait):
            self.controller.periodic('publish', self.controller.publish_poll)
        self.assertLess(len(waits), 30)
        self.assertGreater(len(waits), 1)
        self.assertTrue(all(value == 0 for value in waits[:-1]))
        self.assertGreater(waits[-1], 0)
        self.assertEqual(self.controller.store.get('pending_uploads'), 0)
        receiver = Git(self.base / 'continuous-receiver.git', str(self.remote))
        head = receiver.fetch(RESULT_BRANCH)
        result = receive(receiver, head, record['id'], self.base / 'continuous-download')
        self.assertEqual(result['pending'], [])
        self.assertEqual((self.base / 'continuous-download/td.log').read_bytes(), (folder / 'td.log').read_bytes())
        self.assertEqual(self.controller.publisher.push_timeout, 1800)

    def test_default_batch_can_publish_a_report_larger_than_32_mib(self):
        record, folder = self.terminal_job()
        report = folder / 'stage-logs/routing/timing.rpt'
        report.parent.mkdir(parents=True)
        report.write_bytes(b'x' * (40 * 1024**2 + 17))
        files, ledger, pending = self.controller.artifact_plan()
        self.assertEqual(pending, 0)
        entry = ledger[record['id'] + '/stage-logs/routing/timing.rpt']
        self.assertTrue(entry['complete'])
        self.assertEqual(sum(part['bytes'] for part in entry['parts']), report.stat().st_size)
        self.assertLessEqual(sum(len(body) for path, body in files.items() if path.startswith('chunks/')), 128 * 1024**2)

    def test_upload_failure_uses_backoff_and_preserves_acknowledged_ledger(self):
        self.terminal_job()
        self.controller.publish_poll()
        previous = (self.root / 'uploaded.json').read_bytes()
        waits = []
        def wait(seconds):
            waits.append(seconds)
            self.controller.stop.set()
        with patch.object(self.controller.publisher, 'publish', side_effect=GitError('offline')), \
                patch.object(self.controller.stop, 'wait', side_effect=wait), \
                patch('service.time.monotonic', side_effect=[10, 15]):
            self.controller.periodic('publish', self.controller.publish_poll)
        self.assertEqual(waits, [55])
        self.assertEqual((self.root / 'uploaded.json').read_bytes(), previous)

    def test_empty_pending_plan_does_not_busy_loop(self):
        self.terminal_job()
        with patch.object(self.controller, 'artifact_plan', return_value=({}, {}, 1)):
            self.assertFalse(self.controller.publish_poll())

    def test_long_push_timeout_is_scoped_to_push(self):
        repository = Git(self.base / 'long-push.git', str(self.remote), push_timeout=1800)
        with patch.object(repository, 'run', wraps=repository.run) as run:
            repository.publish(RESULT_BRANCH, {'status.json': b'{}'}, 'fixture status')
        calls = run.call_args_list
        push = next(call for call in calls if call.args[0] == 'push')
        fetch = next(call for call in calls if call.args[0] == 'fetch')
        self.assertEqual(push.kwargs['timeout'], 1800)
        self.assertNotIn('timeout', fetch.kwargs)

    def test_controller_stop_terminates_a_waiting_git_operation(self):
        stop = threading.Event()
        process = unittest.mock.Mock()
        process.pid = 12345
        process.communicate.side_effect = [subprocess.TimeoutExpired('git', 1), (b'', b'')]
        def is_set():
            return process.communicate.call_count > 0
        with patch.object(stop, 'is_set', side_effect=is_set), \
                patch('transport.subprocess.Popen', return_value=process), \
                patch('transport.os.name', 'nt'):
            with self.assertRaisesRegex(GitError, 'stopped with the controller'):
                Git.execute(['push'], self.base, timeout=1800, stop_event=stop)
        process.kill.assert_called_once()
        self.assertEqual(process.communicate.call_count, 2)

    def test_unchanged_reports_do_not_spawn_one_git_process_per_file_each_minute(self):
        publisher = Git(self.base / 'publish-fast.git', str(self.remote))
        files = {'reports/' + str(number) + '.txt': b'stable report' for number in range(50)}
        publisher.publish(RESULT_BRANCH, files, 'Reports')
        with patch.object(publisher, 'run', wraps=publisher.run) as run:
            publisher.publish(RESULT_BRANCH, dict(files, **{'status.json': b'new heartbeat'}), 'Heartbeat')
        hashes = [call for call in run.call_args_list if call.args[0] == 'hash-object']
        updates = [call for call in run.call_args_list if call.args[0] == 'update-index']
        self.assertEqual(len(hashes), 1)
        self.assertEqual(len(updates), 1)

    def test_live_logs_are_available_before_build_finishes(self):
        record = self.source_job()
        folder = self.root / 'jobs' / record['id']
        (folder / 'td.log').write_bytes(b'currently routing\n')
        self.controller.store.state(record['id'], 'RUNNING')
        files, unused_ledger, unused_pending = self.controller.artifact_plan()
        self.assertEqual(files['jobs/' + record['id'] + '/live/td.log'], b'currently routing\n')

    def test_finished_stage_logs_upload_in_full_while_the_next_stage_runs(self):
        record = self.source_job()
        folder = self.controller.jobs_root / record['id']
        runs = folder / 'checkout/candidate/fpga_prj/camera_Runs'
        native = runs / 'phy_1'
        native.mkdir(parents=True)
        body = b'place message before route overwrites it\n' * 4000
        (native / 'run.log').write_bytes(body)
        (native / 'run.logw').write_bytes(b'raw native message companion\n')
        (native / 'camera.tcl').write_bytes(b'native TD command trace\n')
        (native / 'run.sh').write_bytes(b'native TD launcher, archived only\n')
        (native / 'place.params').write_bytes(b'actual native place parameters\n')
        atomic_json(folder / 'paths.json', dict(run_root=str(runs)))
        capture_stage(folder, 'placement', 'phy_1', 'DONE')
        (native / 'run.log').write_bytes(b'now routing\n')
        self.controller.store.state(record['id'], 'RUNNING')
        self.controller.publisher = Git(self.root / 'git/results.git', str(self.remote))
        with patch.object(self.controller.publisher, 'publish', side_effect=GitError('offline during routing')):
            with self.assertRaises(GitError):
                self.controller.publish_poll()
        self.assertFalse((self.root / 'uploaded.json').exists())
        self.controller.publish_poll()
        receiver = Git(self.base / 'stage-receiver.git', str(self.remote))
        head = receiver.fetch(RESULT_BRANCH)
        destination = self.base / 'download-stage'
        result = receive(receiver, head, record['id'], destination)
        relative = 'stage-logs/placement/phy_1/run.log'
        self.assertIn(relative, result['received'])
        self.assertEqual((destination / relative).read_bytes(), body)
        self.assertEqual((destination / 'stage-logs/placement/phy_1/run.logw').read_bytes(),
                         b'raw native message companion\n')
        self.assertEqual((destination / 'stage-logs/placement/phy_1/camera.tcl').read_bytes(), b'native TD command trace\n')
        self.assertEqual((destination / 'stage-logs/placement/phy_1/run.sh').read_bytes(),
                         b'native TD launcher, archived only\n')
        self.assertIn('stage-logs/placement/phy_1/place.params', result['received'])
        self.assertFalse(any(path.endswith('camera_Runs/phy_1/run.log') for path in result['received']))

    def failing_worker(self, cancelled):
        record = self.source_job()
        folder = self.controller.jobs_root / record['id']
        def finish():
            paths = read_json(folder / 'paths.json')
            native = Path(paths['run_root']) / 'phy_1'
            native.mkdir(parents=True)
            (native / 'run.log').write_bytes(b'ROUTE-1000 WARNING: unfinished native route\n' * 3000)
            (native / 'run.logw').write_bytes(b'raw failure companion\n')
            (folder / 'td.log').write_text('TD_SIMPLE_STAGE synthesis DONE\nTD_SIMPLE_STAGE routing START\n')
            if cancelled:
                (folder / 'CANCEL').touch()
            return 130 if cancelled else 1
        with patch('worker.subprocess.Popen', return_value=SimpleNamespace(wait=finish)):
            self.assertEqual(worker.execute(self.root, record['id']), 1)
        result = read_json(folder / 'result.json')
        self.assertEqual(result['state'], 'CANCELLED' if cancelled else 'FAILED')
        self.assertEqual(result['log_capture']['state'], 'CAPTURED', result['log_capture'])
        self.assertEqual((folder / 'stage-logs/routing/phy_1/run.log').read_bytes(),
                         b'ROUTE-1000 WARNING: unfinished native route\n' * 3000)
        self.assertTrue((folder / 'warnings.csv').is_file())
        return folder

    def test_failed_worker_preserves_the_partial_native_stage(self):
        self.failing_worker(False)

    def test_cancelled_worker_preserves_the_partial_native_stage(self):
        self.failing_worker(True)

    def test_twenty_four_seeds_persist_with_per_seed_thread_overrides(self):
        self.source_job()
        request = dict(schema=1, id='batch24', action='build', project='camera',
                       seeds=list(range(1, 25)), threads=8, seed_threads={'24': 4})
        receipt = self.controller.apply_command('batch24', request)
        self.assertEqual(len(receipt['jobs']), 24)
        self.controller.apply_command('batch24', request)
        restarted = Controller(self.root)
        records = [record for record in restarted.store.jobs() if record['spec']['trigger'] == 'batch24']
        self.assertEqual(len(records), 24)
        self.assertTrue(all(record['state'] == 'QUEUED' for record in records))
        self.assertEqual(records[-1]['spec']['project']['seed_threads'], {'24': 4})

    def test_multiseed_build_queues_one_shared_synthesis_before_all_physical_seeds(self):
        self.source_job()
        receipt = self.controller.apply_command('batch8', dict(schema=1, id='batch8', action='build',
                                                project='camera', seeds=list(range(1, 9)), threads=8))
        self.controller.prepare_sources()
        self.assertEqual(len(receipt['jobs']), 8)
        self.assertIsNotNone(receipt['synthesis_job'])
        self.assertTrue((self.controller.jobs_root / receipt['synthesis_job'] / 'READY').exists())
        for job_id in receipt['jobs']:
            self.assertFalse((self.controller.jobs_root / job_id / 'READY').exists())
            self.assertFalse((self.controller.jobs_root / job_id / 'checkout').exists())
        self.assertEqual(sum(record['spec']['project']['target'] == 'synth' for record in self.controller.store.jobs()), 1)

    def test_failed_shared_synthesis_returns_failure_without_starting_any_physical_seed(self):
        self.source_job()
        receipt = self.controller.apply_command('batch8', dict(schema=1, id='batch8', action='build',
                                                project='camera', seeds=list(range(1, 9))))
        self.controller.store.state(receipt['synthesis_job'], 'FAILED', 'native synthesis error')
        self.controller.prepare_sources()
        children = [record for record in self.controller.store.jobs() if record['id'] in receipt['jobs']]
        self.assertTrue(all(record['state'] == 'FAILED' for record in children))
        self.assertTrue(all('Shared synthesis failed' in record['error'] for record in children))

    def test_fresh_bitgen_output_is_returned_through_real_git_and_download(self):
        record = self.source_job()
        folder = self.controller.jobs_root / record['id']
        runs = folder / 'checkout/candidate/fpga_prj/camera_Runs'
        (runs / 'phy_1').mkdir(parents=True)
        (runs / 'phy_1/camera.bit').write_bytes(b'bitgen output fixture')
        (folder / 'td.log').write_text('TD_SIMPLE_STAGE bitgen DONE\nTD_SIMPLE_COMPLETE\n')
        atomic_json(folder / 'paths.json', dict(run_root=str(runs)))
        self.controller.store.state(record['id'], 'DONE')
        self.controller.publish_poll()
        receiver = Git(self.base / 'bit-receiver.git', str(self.remote))
        head = receiver.fetch(RESULT_BRANCH)
        destination = self.base / 'download-bit'
        result = receive(receiver, head, record['id'], destination)
        relative = 'checkout/candidate/fpga_prj/camera_Runs/phy_1/camera.bit'
        self.assertIn(relative, result['received'])
        self.assertEqual((destination / relative).read_bytes(), b'bitgen output fixture')

    def test_per_seed_threads_reach_both_native_runs(self):
        record = self.source_job()
        spec = dict(record['spec'], seed=6, project=dict(record['spec']['project'], seed_threads={'6': 4}))
        folder = self.root / 'jobs' / record['id']
        build_script(folder / 'checkout', spec, folder / 'build.tcl')
        text = (folder / 'build.tcl').read_text()
        self.assertIn('td_set_threads syn_1 4 ', text)
        self.assertIn('td_set_threads phy_1 4 ', text)
        self.assertIn('set_param -run phy_1 place seed 6', text)

    def checkpoint_job(self, level=1, failed_at=None):
        record = self.source_job()
        folder = self.controller.jobs_root / record['id']
        project, runs = build_script(folder / 'checkout', record['spec'], folder / 'build.tcl')
        stages = dict.fromkeys(('synthesis', 'placement', 'routing', 'bitgen', 'reports', 'reopen'), 'NOT_RUN')
        for stage, run, suffix, step in (
                ('synthesis', 'syn_1', 'gate', 'opt_gate'), ('placement', 'phy_1', 'place', 'opt_place'),
                ('routing', 'phy_1', 'pr', 'opt_route'))[:level]:
            directory = runs / run
            directory.mkdir(parents=True, exist_ok=True)
            (directory / ('.' + step + '.end.f')).touch()
            (directory / ('camera_' + suffix + '.db')).write_bytes(('native fixture ' + stage).encode())
            stages[stage] = 'DONE'
        if failed_at:
            stages[failed_at] = 'RUNNING'
        state = 'FAILED' if failed_at else 'DONE'
        atomic_json(folder / 'paths.json', dict(project=str(project), run_root=str(runs)))
        atomic_json(folder / 'result.json', dict(state=state, stages=stages))
        self.controller.store.state(record['id'], state)
        return self.controller.store.jobs()[0], folder

    def continue_job(self, parent, target, **fields):
        request = dict(schema=1, id='advance', action='continue', job=parent['id'], target=target, **fields)
        receipt = self.controller.apply_command('advance', request)
        return next(record for record in self.controller.store.jobs() if record['id'] == receipt['jobs'][0])

    def test_continue_synthesis_to_twenty_four_physical_seeds_without_git_or_new_synthesis(self):
        parent, folder = self.checkpoint_job()
        self.controller.source = None
        receipt = self.controller.apply_command('advance24', dict(schema=1, id='advance24', action='continue',
                                                job=parent['id'], target='full', seeds=list(range(1, 25))))
        self.assertEqual(len(receipt['jobs']), 24)
        self.assertTrue(all(record['spec']['resume']['checkpoint_level'] == 1
                            for record in self.controller.store.jobs() if record['id'] in receipt['jobs']))
        child = next(record for record in self.controller.store.jobs() if record['id'] == receipt['jobs'][0])
        job = self.controller.jobs_root / child['id']
        copy_checkpoint(self.controller.jobs_root, job, child['spec'])
        build_script(job / 'checkout', child['spec'], job / 'build.tcl')
        text = (job / 'build.tcl').read_text()
        self.assertNotIn('reset_runs syn_1', text)
        self.assertNotIn('td_stage synthesis syn_1', text)
        self.assertIn('synthesis REUSED', text)
        copied = job / 'checkout/candidate/fpga_prj/camera_Runs/syn_1/camera_gate.db'
        original = folder / 'checkout/candidate/fpga_prj/camera_Runs/syn_1/camera_gate.db'
        self.assertEqual(copied.read_bytes(), original.read_bytes())
        copied.write_bytes(b'child is independent')
        self.assertNotEqual(copied.read_bytes(), original.read_bytes())

    def test_route_to_bitgen_launches_only_bitgen(self):
        parent, unused_folder = self.checkpoint_job(3)
        record = self.continue_job(parent, 'bitgen')
        job = self.controller.jobs_root / record['id']
        copy_checkpoint(self.controller.jobs_root, job, record['spec'])
        build_script(job / 'checkout', record['spec'], job / 'build.tcl')
        text = (job / 'build.tcl').read_text()
        for stage in ('synthesis', 'placement', 'routing'):
            self.assertNotIn('td_stage ' + stage + ' ', text)
            self.assertIn(stage + ' REUSED', text)
        self.assertIn('td_stage bitgen phy_1', text)

    def test_property_edits_invalidate_only_the_necessary_upstream_stage(self):
        parent, unused_folder = self.checkpoint_job(3)
        for options, level in (({'phy_1': {'route': {'fix_hold': 'high'}}}, 2),
                               ({'phy_1': {'place': {'effort': 'high'}}}, 1),
                               ({'syn_1': {'gate': {'pack_effort': 'high'}}}, 0)):
            request_id = 'change' + str(level)
            receipt = self.controller.apply_command(request_id, dict(schema=1, id=request_id, action='continue',
                                                     job=parent['id'], target='full', td_options=options))
            record = next(record for record in self.controller.store.jobs() if record['id'] == receipt['jobs'][0])
            self.assertEqual(record['spec']['resume']['checkpoint_level'], level)

    def test_failed_route_can_continue_from_completed_placement(self):
        parent, unused_folder = self.checkpoint_job(2, failed_at='routing')
        record = self.continue_job(parent, 'full')
        self.assertEqual(record['spec']['resume']['checkpoint_level'], 2)
        self.assertEqual(record['spec']['resume']['rollback_steps'], 1)

    def test_bitgen_rejects_missing_route_or_changes_that_require_new_placement(self):
        parent, unused_folder = self.checkpoint_job()
        with self.assertRaisesRegex(ValueError, 'completed routing'):
            self.continue_job(parent, 'bitgen')
        self.assertEqual(len(self.controller.store.jobs()), 1)

    def test_source_bound_continuation_rejects_an_active_parent(self):
        parent = self.source_job()
        with self.assertRaisesRegex(ValueError, 'Wait for the source job'):
            self.continue_job(parent, 'full')

    def test_native_run_properties_are_applied_before_launch_without_script_hooks(self):
        record = self.source_job()
        spec = dict(record['spec'], project=dict(record['spec']['project'], td_options={
                    'syn_1': {'gate': {'pack_effort': 'high'}},
                    'phy_1': {'place': {'logic_level_opt': 'off'}, 'route': {'post_route_opt': 'medium'}}}))
        folder = self.controller.jobs_root / record['id']
        build_script(folder / 'checkout', spec, folder / 'build.tcl')
        text = (folder / 'build.tcl').read_text()
        self.assertIn('set_param -run "syn_1" "gate" "pack_effort" "high"', text)
        self.assertLess(text.index('set_param -run "phy_1"'), text.index('reset_runs syn_1'))
        self.assertIn('set_param -run phy_1 flow enable_seed off', text)

    def test_a_copied_old_bit_is_not_returned_as_new_bitgen_output(self):
        record = self.source_job()
        folder = self.controller.jobs_root / record['id']
        runs = folder / 'checkout/candidate/fpga_prj/camera_Runs'
        (runs / 'phy_1').mkdir(parents=True)
        (runs / 'phy_1/camera.bit').write_bytes(b'old inherited bit')
        atomic_json(folder / 'paths.json', dict(run_root=str(runs)))
        files, unused_ledger, unused_pending = self.controller.artifact_plan()
        artifacts = json.loads(files['jobs/' + record['id'] + '/artifacts.json'])['files']
        self.assertFalse(any(item['path'].endswith('.bit') for item in artifacts))

    def test_resource_samples_are_published_while_build_is_running(self):
        record = self.source_job()
        folder = self.root / 'jobs' / record['id']
        atomic_json(folder / 'resources.json', dict(stage='placement', cpu_cores=8, rss_gib=12))
        (folder / 'resources.csv').write_text('epoch,stage,cpu_cores\n1000,placement,8\n')
        self.controller.store.state(record['id'], 'RUNNING')
        files, unused_ledger, unused_pending = self.controller.artifact_plan()
        self.assertIn('jobs/' + record['id'] + '/resources.json', files)
        self.assertIn(b'placement', files['jobs/' + record['id'] + '/live/resources.csv'])

    def test_dispatch_starts_eight_at_most_and_leaves_sixteen_queued_then_refills(self):
        old = self.source_job()
        self.controller.store.state(old['id'], 'DONE')
        receipt = self.controller.apply_command('batch24', dict(schema=1, id='batch24', action='build',
                                               project='camera', seeds=list(range(1, 25)), threads=8))
        self.controller.prepare_sources()
        synthesis = next(record for record in self.controller.store.jobs() if record['id'] == receipt['synthesis_job'])
        synthesis_folder = self.controller.jobs_root / synthesis['id']
        project, runs = build_script(synthesis_folder / 'checkout', synthesis['spec'], synthesis_folder / 'build.tcl')
        (runs / 'syn_1').mkdir(parents=True)
        (runs / 'syn_1/.opt_gate.end.f').touch()
        (runs / 'syn_1/camera_gate.db').write_bytes(b'shared native gate checkpoint fixture')
        atomic_json(synthesis_folder / 'result.json', dict(state='DONE', stages={'synthesis': 'DONE'}))
        self.controller.store.state(synthesis['id'], 'DONE')
        self.controller.prepare_sources()
        self.controller.config['max_parallel'] = 8
        clock = [1000]
        sample = dict(complete=True, state='READY', sampled_at=1000, effective_cpu_cores=256,
                      host_cpu_count=256, td_cpu_cores=0, td_rss_gib=0, host_busy_cores=0,
                      memory_headroom_gib=1000, groups={})
        self.controller.resources.value = sample
        leases = []
        process = SimpleNamespace(poll=lambda: None)
        try:
            with patch.object(self.controller.resources, 'sample', return_value=sample), \
                    patch('resources.time.time', side_effect=lambda: clock[0]), \
                    patch('service.subprocess.Popen', return_value=process) as launch:
                for number in range(8):
                    sample['sampled_at'] = clock[0]
                    self.controller.dispatch()
                    self.assertEqual(launch.call_count, number + 1)
                    active = next(record for record in self.controller.store.jobs()
                                  if record['state'] == 'STARTING' and record['id'] not in {name for name, unused in leases})
                    job = self.controller.jobs_root / active['id']
                    (job / 'td.log').write_text('TD_SIMPLE_STAGE synthesis DONE\nTD_SIMPLE_STAGE placement START\n')
                    lease = FileLock(job / 'worker.lock')
                    self.assertTrue(lease.acquire())
                    leases.append((active['id'], lease))
                    clock[0] += self.controller.config['start_interval_seconds']
                sample['sampled_at'] = clock[0]
                self.controller.dispatch()
                self.assertEqual(launch.call_count, 8)
                self.assertEqual(self.controller.admission, 'WAITING_FOR_PARALLEL_SLOT')
                records = self.controller.store.jobs()
                self.assertEqual(sum(record['state'] == 'QUEUED' for record in records), 16)
                finished, lease = leases.pop(0)
                atomic_json(self.controller.jobs_root / finished / 'result.json', dict(state='DONE'))
                lease.close()
                clock[0] += 20
                sample['sampled_at'] = clock[0]
                self.controller.dispatch()
                self.assertEqual(launch.call_count, 9)
                self.assertEqual(sum(record['state'] == 'QUEUED' for record in self.controller.store.jobs()), 15)
        finally:
            for unused_name, lease in leases:
                lease.close()

    def test_offline_attempt_retries_at_the_next_minute(self):
        class StopAfterOneWait:
            def __init__(self):
                self.stopped = False
                self.waits = []
            def is_set(self):
                return self.stopped
            def wait(self, seconds):
                self.waits.append(seconds)
                self.stopped = True
        stop = StopAfterOneWait()
        self.controller.stop = stop
        with patch('service.time.monotonic', side_effect=[10, 15]):
            self.controller.periodic('source', lambda: (_ for unused in ()).throw(GitError('offline')))
        self.assertEqual(stop.waits, [55])
        self.assertEqual(self.controller.store.get('network.source')['error'], 'offline')

    def evaluate_flow(self, failure=None):
        record = self.source_job()
        folder = self.root / 'jobs' / record['id']
        script = folder / 'flow.tcl'
        project, runs = build_script(folder / 'checkout', record['spec'], script)
        atomic_json(folder / 'paths.json', dict(project=str(project), run_root=str(runs)))
        interpreter = tkinter.Tcl()
        exits = []
        messages = []
        def launch(*arguments):
            step = arguments[1]
            run = runs / arguments[2]
            run.mkdir(parents=True, exist_ok=True)
            (run / 'run.log').write_text(step + ' full native log\n' + 'native message\n' * 6000)
            (run / 'run.logw').write_text(step + ' raw companion\n')
            if step != failure:
                (run / ('.' + step + '.end.f')).touch()
            if step == 'bitgen':
                (run / 'camera.bit').write_bytes(b'actual fake TD bitstream')
            return ''
        def report(*arguments):
            path = Path(arguments[-1])
            path.write_text('SWNS: 1.0 STNS: 0 HWNS: -0.25 HTNS: -1.0', encoding='utf-8')
            return ''
        for name in ('import_device', 'open_project', 'close_project', 'reset_runs',
                     'wait_run', 'open_run', 'update_timing'):
            interpreter.createcommand(name, lambda *arguments: '')
        native_threads = {}
        def configure(*arguments):
            if len(arguments)==5 and arguments[0]=='-run' and arguments[2:4]==('flow','thread'):
                native_threads[arguments[1]]=arguments[4]
            return ''
        def parameters(run,flag,path):
            Path(path).write_text('set_param flow thread '+native_threads.get(run,'auto')+'\n')
            return ''
        interpreter.createcommand('set_param',configure)
        interpreter.createcommand('report_run_param',parameters)
        interpreter.createcommand('launch_runs', launch)
        interpreter.createcommand('report_area', report)
        interpreter.createcommand('report_timing_summary', report)
        interpreter.createcommand('puts', lambda *arguments: messages.append(' '.join(arguments)) or '')
        interpreter.createcommand('flush', lambda *arguments: '')
        interpreter.createcommand('exit', lambda code: exits.append(int(code)) or '')
        previous = Path.cwd()
        try:
            interpreter.call('source', script.as_posix())
        finally:
            os.chdir(previous)
        return exits, messages, runs, script

    def test_normal_native_full_flow_preserves_negative_timing_as_a_separate_result(self):
        exits, messages, runs, script = self.evaluate_flow()
        self.assertEqual(exits, [0])
        self.assertTrue((runs / 'phy_1/camera.bit').is_file())
        self.assertEqual(timing_status(runs)['state'], 'NEGATIVE')
        self.assertIn('TD_SIMPLE_STAGE reopen DONE', messages)
        self.assertNotIn('audit', script.read_text().lower())
        self.assertNotIn('source ', script.read_text())

    def test_native_log_rollover_does_not_replace_earlier_stage_messages(self):
        exits, unused_messages, runs, script = self.evaluate_flow()
        self.assertEqual(exits, [0])
        for stage, run, step in (('synthesis', 'syn_1', 'opt_gate'), ('placement', 'phy_1', 'opt_place'),
                                 ('routing', 'phy_1', 'opt_route'), ('bitgen', 'phy_1', 'bitgen')):
            archive = script.parent / 'stage-logs' / stage / run
            self.assertEqual((archive / 'run.log').read_text(), step + ' full native log\n' + 'native message\n' * 6000)
            self.assertEqual((archive / 'run.logw').read_text(), step + ' raw companion\n')
        self.assertTrue((runs / 'phy_1/run.log').read_text().startswith('bitgen'))

    def test_wait_run_success_cannot_hide_a_failed_native_stage(self):
        exits, messages, runs, unused_script = self.evaluate_flow(failure='opt_route')
        self.assertEqual(exits[0], 1)
        self.assertFalse((runs / 'phy_1/camera.bit').exists())
        self.assertTrue(any('TD stage did not finish' in message for message in messages))
        capture = runs.parents[3] / 'stage-logs/routing'
        self.assertEqual(read_json(capture / 'capture.json')['state'], 'FAILED')
        self.assertTrue((capture / 'phy_1/run.log').read_text().startswith('opt_route full native log'))


class CampusNetworkTests(unittest.TestCase):
    def test_rsa_matches_a_synthetic_vector_from_the_actual_portal_security_javascript(self):
        modulus = ('94dd2a8675fb779e6b9f7103698634cd400f27a154afa67af6166a43fc26417222'
                   'a79506d34cacc7641946abda1785b7acf9910ad6a0978c91ec84d40b71d2891379'
                   'af19ffb333e7517e390bd26ac312fe940c340466b4a5d4af1d65c3b5944078f96'
                   'a1a51a5a53e4bc302818b7c9f63c4a1b07bd7d874cef1c3d4b2f5eb7871')
        expected = ('0b2df46c54785790743d423e7894bc9688a08d899a7bfbbea949c7077ab550fa3b'
                    '37c0302d288f306906228ca0902943894499124d0885153b6c47058063dd66d401d'
                    '44e71b97ac65a128cc463013ba80db59334c409284f295ca5f00dd854d568351c7'
                    '326e65c72e9bb0692e2ce7a78dc3b331cb9471c995471fe41cd1c6b68')
        self.assertEqual(network.encrypt_password('fixture-password', 'aa:bb:cc:dd:ee:ff', '10001', modulus), expected)

    def test_portal_query_requires_this_server_redirect_and_rejects_windows_success_session(self):
        self.assertIsNotNone(network.portal_query(network.PORTAL + 'index.jsp?wlanuserip=192.0.2.8&mac=aa'))
        self.assertIsNone(network.portal_query(network.PORTAL + 'success.jsp?userIndex=windows-session'))
        self.assertIsNone(network.portal_query('http://another.example/eportal/index.jsp?mac=aa'))

    def test_request_double_encoding_matches_the_portal_javascript(self):
        fields = dict(userId='test@example.invalid', password='abc+%&', queryString='mac=aa:bb&userip=192.0.2.8')
        decoded = urllib.parse.parse_qs(network.double_form(fields).decode())
        for key, value in fields.items():
            self.assertEqual(urllib.parse.unquote(decoded[key][0]), value)

    def test_online_network_never_submits_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            atomic_json(Path(directory) / 'network-auth.json', dict(portal=network.PORTAL, username='private-user', password='private-pass'))
            if os.name == 'posix':
                os.chmod(Path(directory) / 'network-auth.json', 0o600)
            with patch('network.opener'), patch('network.probe', return_value=(True, None)), patch('network.api') as api:
                self.assertEqual(network.reconnect(directory), {'state': 'ONLINE'})
                api.assert_not_called()

    def test_captcha_is_reported_without_a_login_attempt(self):
        with tempfile.TemporaryDirectory() as directory:
            atomic_json(Path(directory) / 'network-auth.json', dict(portal=network.PORTAL, username='private-user', password='private-pass'))
            if os.name == 'posix':
                os.chmod(Path(directory) / 'network-auth.json', 0o600)
            with patch('network.opener'), patch('network.probe', return_value=(False, 'mac=aa')):
                with patch('network.api', return_value={'validCodeUrl': '/captcha'}) as api:
                    result = network.reconnect(directory)
            self.assertEqual(result, {'state': 'MANUAL_CAPTCHA_OR_SMS_REQUIRED'})
            self.assertEqual(api.call_count, 1)
            self.assertNotIn('private', json.dumps(result))

    def test_offline_authentication_uses_the_current_server_redirect_and_no_logout(self):
        with tempfile.TemporaryDirectory() as directory:
            atomic_json(Path(directory) / 'network-auth.json', dict(portal=network.PORTAL, username='private-user', password='private-pass'))
            if os.name == 'posix':
                os.chmod(Path(directory) / 'network-auth.json', 0o600)
            page = dict(passwordEncrypt='true', publicKeyExponent='10001', publicKeyModulus='fixture', prefixValue='')
            query = 'wlanuserip=192.0.2.8&mac=server%3Amac'
            with patch('network.opener'), patch('network.probe', side_effect=[(False, query), (True, None)]), \
                    patch('network.encrypt_password', return_value='encrypted-fixture') as encrypt, \
                    patch('network.api', side_effect=[page, {'result': 'success'}]) as api:
                result = network.reconnect(directory)
            self.assertEqual(result, {'state': 'ONLINE'})
            encrypt.assert_called_once_with('private-pass', 'server%3Amac', '10001', 'fixture')
            self.assertEqual([call.args[2] for call in api.call_args_list], ['pageInfo', 'login'])
            self.assertNotIn('private', json.dumps(result))


class InstallerTests(unittest.TestCase):
    def test_application_upgrade_preserves_the_server_local_ssh_identity_wrapper(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source'
            application = Path(directory) / 'app'
            source.mkdir()
            application.mkdir()
            (source / 'git_ssh.sh').write_text('default wrapper')
            (source / 'service.py').write_text('updated service')
            (application / 'git_ssh.sh').write_text('server-local identity wrapper')
            (application / 'service.py').write_text('previous service')
            install.copy_application(source, application)
            self.assertEqual((application / 'git_ssh.sh').read_text(), 'server-local identity wrapper')
            self.assertEqual((application / 'service.py').read_text(), 'updated service')
            fresh = Path(directory) / 'fresh'
            fresh.mkdir()
            install.copy_application(source, fresh)
            self.assertEqual((fresh / 'git_ssh.sh').read_text(), 'default wrapper')

    def test_retirement_stops_only_matching_legacy_controllers_and_keeps_workers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'td_operator'
            farm = Path(directory) / 'td_farm'
            root.mkdir()
            farm.mkdir()
            atomic_json(root / 'config.json', dict(farm=str(farm)))
            record = dict(pid=12345, start='123', uid=1000,
                          argv=['python', '-B', str(root / 'releases' / ('a' * 64) / 'tools/td_operator.py'),
                                'run', '--root', str(root)])
            atomic_json(root / 'ha/broker.json', record)
            def matches(value):
                return value == record and not stopped
            stopped = []
            with patch('install.owned_directory', side_effect=lambda value: Path(value)), \
                    patch('install.matches_record', side_effect=matches), \
                    patch('install.os.kill', side_effect=lambda pid, unused_signal: stopped.append(pid)):
                result = install.retire_legacy(root, farm)
            self.assertEqual(stopped, [12345])
            self.assertEqual(result['existing_workers'], 'KEEP_RUNNING')
            self.assertTrue((root / 'STOP').is_file())
            self.assertTrue((farm / 'PAUSE').is_file())

    def test_cron_replacement_preserves_other_user_jobs(self):
        old = ('@reboot python /home/build-user/td_operator/supervisor.py /home/build-user/td_operator\n'
               '0 3 * * * /home/build-user/backup_documents.sh\n')
        calls = [SimpleNamespace(returncode=0, stdout=old.encode(), stderr=b''),
                 SimpleNamespace(returncode=0, stdout=b'', stderr=b'')]
        with patch('install.subprocess.run', side_effect=calls) as run:
            install.cron_update(Path('/home/build-user/td_simple'), Path('/home/build-user/td_operator'))
        text = run.call_args.kwargs['input'].decode()
        self.assertNotIn('td_operator/supervisor.py', text)
        self.assertIn('backup_documents.sh', text)
        self.assertEqual(text.count('# td-simple-build-server'), 1)

    def test_private_bundle_integrates_credentials_outside_the_versioned_program(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credentials = root / 'private/network-auth.json'
            document = dict(portal=network.PORTAL, username='fixture-user', password='fixture-only-password', service='')
            atomic_json(credentials, document)
            output = root / 'private/install.tar.gz'
            with patch('make_private_bundle.time.time', return_value=1792638000):
                bundle(credentials, output)
            with tarfile.open(output, 'r:gz') as archive:
                member = archive.getmember('private-install/network-auth.json')
                self.assertEqual(member.mode, 0o600)
                self.assertEqual(member.mtime, 1792638000)
                self.assertEqual(json.load(archive.extractfile(member)), document)
                self.assertIn('private-install/server/td/simple/install.py', archive.getnames())
                self.assertFalse(any('/local/' in name or '.git/' in name for name in archive.getnames()))


if __name__ == '__main__':
    unittest.main()
