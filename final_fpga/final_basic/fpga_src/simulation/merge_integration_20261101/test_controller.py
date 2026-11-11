"""Focused regression for the observed Windows sharing fault and PID ownership."""
from pathlib import Path
import os
import threading
import unittest
import binding
import supervise


class ControllerChecks(unittest.TestCase):
    def test_bounded_permission_retry(self):
        original_sleep = binding.time.sleep
        delays = []
        calls = []
        binding.time.sleep = delays.append
        try:
            def transient():
                calls.append(1)
                if len(calls) < 7:
                    raise PermissionError('transient Windows share lock')
                return 'recovered'
            self.assertEqual(binding.retry(transient), 'recovered')
            self.assertEqual(len(calls), 7)
            self.assertEqual(delays, [0.02,0.04,0.08,0.16,0.32,0.64])
            calls.clear()
            def persistent():
                calls.append(1)
                raise PermissionError('persistent share lock must remain failure')
            with self.assertRaises(PermissionError):
                binding.retry(persistent)
            self.assertEqual(len(calls), 7)
        finally:
            binding.time.sleep = original_sleep

    def test_atomic_reader(self):
        path = Path(__file__).resolve().parent / f'.controller_io_{os.getpid()}.json'
        errors = []
        stopped = threading.Event()
        binding.atomic(path, {'iteration': 0})
        def reader():
            while not stopped.is_set():
                try:
                    value = binding.read(path)
                    if set(value) != {'iteration'} or not isinstance(value['iteration'], int):
                        errors.append('partial JSON state')
                except Exception as error:
                    errors.append(repr(error))
                    break
        thread = threading.Thread(target=reader)
        thread.start()
        try:
            for number in range(100):
                binding.atomic(path, {'iteration': number})
        finally:
            stopped.set()
            thread.join()
            path.unlink()
            path.with_name(path.name + f'.{os.getpid()}.tmp').unlink(missing_ok=True)
        self.assertEqual(errors, [])

    def test_pid_creation_time(self):
        own = supervise.identity(os.getpid())
        self.assertTrue(supervise.alive(own))
        self.assertFalse(supervise.alive(dict(own, create_time_epoch=own['create_time_epoch']-1)))


if __name__ == '__main__':
    unittest.main(verbosity=2)
