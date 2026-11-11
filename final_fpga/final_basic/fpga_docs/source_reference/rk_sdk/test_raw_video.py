"""Offline ARAW SOURCE identity and payload borrowing checks."""

from struct import pack
from unittest import TestCase

from raw_video import RawVideoError, RawVideoReceiver


def record(sequence, *, camera=0, session=9, epoch=2, width=8, height=2, job_id=1):
    payload = bytes(range(width // 4 * height * 5))
    header = pack("<4sHHIHHIII4BQQ16x", b"ARAW", 1, 64, len(payload), width, height,
                  sequence, session, epoch, camera, 1, 0, 0, 0, job_id)
    return bytearray(header + payload)


class RawVideoReceiverTests(TestCase):
    def setUp(self):
        self.receiver = RawVideoReceiver(session=9, mode_epoch=2, cameras=2, width=8, height=2)

    def test_eyes_advance_independently_with_gaps(self):
        for camera, sequence in ((0, 257), (1, 521), (0, 264), (1, 522), (0, 522)):
            frame = self.receiver.accept(record(sequence, camera=camera))
            self.assertEqual((frame.camera, frame.source_sequence), (camera, sequence))

    def test_invalid_identity_leaves_sequence_unchanged(self):
        self.receiver.accept(record(257))
        self.receiver.accept(record(521, camera=1))
        for name, invalid in (
            ("duplicate", record(257)), ("backward", record(256)),
            ("wrong session", record(999, session=8)), ("wrong epoch", record(999, epoch=3)),
            ("wrong geometry", record(999, width=4)), ("wrong camera", record(999, camera=2)),
            ("zero job", record(999, job_id=0)),
        ):
            with self.subTest(name=name), self.assertRaises(RawVideoError):
                self.receiver.accept(invalid)
        self.assertEqual(self.receiver.accept(record(258)).source_sequence, 258)
        self.assertEqual(self.receiver.accept(record(523, camera=1)).source_sequence, 523)

    def test_mono_requires_cam0(self):
        receiver = RawVideoReceiver(session=9, mode_epoch=2, cameras=1, width=8, height=2)
        with self.assertRaises(RawVideoError):
            receiver.accept(record(521, camera=1))
        self.assertEqual(receiver.accept(record(257)).camera, 0)

    def test_accept_preserves_original_payload_view(self):
        buffer = record(257)
        first = self.receiver.accept(memoryview(buffer))
        self.receiver.accept(record(521, camera=1))
        self.receiver.accept(record(260))
        self.assertIs(first.payload.obj, buffer)
        self.assertTrue(first.payload.readonly)
        self.assertEqual(first.payload, bytes(range(20)))
