"""Cancel-session identity checks without launching or signalling real TD."""
from pathlib import Path
import importlib.util
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'server/td/simple'))
from common import atomic_json
import process_control
import stop_jobs

spec = importlib.util.spec_from_file_location('simple_cancel_runner', ROOT / 'server/td/simple/tools/run_td.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class CancellationTests(unittest.TestCase):
    def setUp(self):
        self.record = dict(pid=12345, start='98765', uid=1000,
                           argv=['/bin/bash', '/td/bin/td.sh', '-b', '/owned/job/build.tcl'])

    def test_shell_exec_does_not_invalidate_owned_process_identity(self):
        current = dict(self.record, argv=['/td/bin/td', '-b', '/owned/job/build.tcl'])
        with patch('process_control.process_identity', return_value=current), \
                patch('process_control.os.getpgid', return_value=12345, create=True), \
                patch('process_control.os.killpg', create=True) as kill:
            self.assertTrue(process_control.signal_session(self.record, signal.SIGTERM))
            kill.assert_called_once_with(12345, signal.SIGTERM)

    def test_reused_pid_and_different_owner_never_receive_signals(self):
        for current in (None, dict(self.record, start='new'), dict(self.record, uid=2000)):
            with self.subTest(current=current), patch('process_control.process_identity', return_value=current), \
                    patch('process_control.os.killpg', create=True) as kill:
                self.assertFalse(process_control.signal_session(self.record, signal.SIGTERM))
                kill.assert_not_called()

    def test_other_process_group_is_rejected(self):
        with patch('process_control.process_identity', return_value=self.record), \
                patch('process_control.os.getpgid', return_value=1, create=True), \
                patch('process_control.os.killpg', create=True) as kill:
            with self.assertRaisesRegex(ValueError, 'outside its own session'):
                process_control.signal_session(self.record, signal.SIGTERM)
            kill.assert_not_called()

    def test_stopped_or_reused_identity_cannot_trigger_kill(self):
        with patch('process_control.same_process', return_value=self.record), \
                patch('process_control.os.getpgid', side_effect=ProcessLookupError, create=True), \
                patch('process_control.os.killpg', create=True) as kill:
            self.assertFalse(process_control.signal_session(self.record, signal.SIGTERM))
            kill.assert_not_called()

    def test_runner_uses_grace_period_then_the_same_checked_session(self):
        from unittest.mock import Mock
        process = Mock()
        process.wait.side_effect = [subprocess.TimeoutExpired('TD', 10), 0]
        with patch.object(runner, 'signal_session', return_value=True) as send, \
                patch.object(runner.signal, 'SIGKILL', 9, create=True):
            runner.terminate(process, self.record)
            self.assertEqual(send.call_args_list[0].args, (self.record, signal.SIGTERM))
            self.assertEqual(send.call_args_list[1].args, (self.record, signal.SIGKILL))
            self.assertEqual(process.wait.call_args_list[0].kwargs, {'timeout': 10})

    def test_runner_does_not_signal_a_reused_process(self):
        from unittest.mock import Mock
        process = Mock()
        with patch.object(runner, 'signal_session', return_value=False) as send:
            runner.terminate(process, self.record)
            send.assert_called_once_with(self.record, signal.SIGTERM)
            process.wait.assert_not_called()

    def test_manual_helper_keeps_completed_results_and_stops_only_bound_job(self):
        directory = ROOT / 'server/td/local/simple-tests'
        directory.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=directory) as temporary:
            root = Path(temporary)
            job = root / 'jobs/target'
            job.mkdir(parents=True)
            atomic_json(root / 'config.json', dict(jobs_root=str(root / 'jobs')))
            script = job / 'build.tcl'
            script.write_text('native controlled build')
            record = dict(self.record, argv=['/bin/bash', '/td/bin/td.sh', '-b', str(script)])
            atomic_json(job / 'td-process.json', dict(process=record))
            bit = job / 'keep.bit'; bit.write_bytes(b'already generated output')
            with patch('stop_jobs.same_process', side_effect=[dict(record, argv=['/td/bin/td']), None, None]), \
                    patch('stop_jobs.signal_session', return_value=True) as send:
                self.assertEqual(stop_jobs.stop_job(root, 'target')['state'], 'STOP_SENT')
                send.assert_called_once_with(record, signal.SIGTERM)
            self.assertTrue((job / 'CANCEL').is_file())
            self.assertEqual(bit.read_bytes(), b'already generated output')
            atomic_json(job / 'result.json', dict(state='DONE'))
            with patch('stop_jobs.signal_session') as send:
                self.assertEqual(stop_jobs.stop_job(root, 'target')['state'], 'ALREADY_TERMINAL')
                send.assert_not_called()


if __name__ == '__main__':
    unittest.main()
