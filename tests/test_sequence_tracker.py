"""Unit tests for diagnostic-only linear wire-sequence tracking."""

from __future__ import annotations

import unittest

from linux.task3_pipeline.errors import ValidationError
from linux.task3_pipeline.sequence_tracker import (
    SequenceObservation,
    SequenceStatus,
    SequenceTracker,
)


class SequenceTrackerTests(unittest.TestCase):
    def test_initial_high_water_mark_is_none(self) -> None:
        self.assertIsNone(SequenceTracker().last_sequence)

    def test_first_zero_is_not_a_gap(self) -> None:
        tracker = SequenceTracker()

        observation = tracker.observe(0)

        self.assertEqual(observation.status, SequenceStatus.FIRST)
        self.assertEqual(observation.wire_sequence, 0)
        self.assertIsNone(observation.previous_sequence)
        self.assertIsNone(observation.expected_sequence)
        self.assertEqual(observation.missing_count, 0)
        self.assertEqual(tracker.last_sequence, 0)

    def test_first_large_value_is_not_a_gap(self) -> None:
        tracker = SequenceTracker()

        observation = tracker.observe(10**100)

        self.assertEqual(observation.status, SequenceStatus.FIRST)
        self.assertEqual(observation.missing_count, 0)
        self.assertEqual(tracker.last_sequence, 10**100)

    def test_consecutive_values_are_in_order(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(4)

        observation = tracker.observe(5)

        self.assertEqual(observation.status, SequenceStatus.IN_ORDER)
        self.assertEqual(observation.previous_sequence, 4)
        self.assertEqual(observation.expected_sequence, 5)
        self.assertEqual(observation.missing_count, 0)
        self.assertEqual(tracker.last_sequence, 5)

    def test_duplicate_does_not_advance_high_water_mark(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(4)

        observation = tracker.observe(4)

        self.assertEqual(observation.status, SequenceStatus.DUPLICATE)
        self.assertEqual(observation.expected_sequence, 5)
        self.assertEqual(tracker.last_sequence, 4)

    def test_duplicate_followed_by_next_value_is_in_order(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(4)
        tracker.observe(4)

        self.assertEqual(tracker.observe(5).status, SequenceStatus.IN_ORDER)

    def test_gap_reports_expected_value_and_exact_missing_count(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(10)

        observation = tracker.observe(13)

        self.assertEqual(observation.status, SequenceStatus.GAP)
        self.assertEqual(observation.previous_sequence, 10)
        self.assertEqual(observation.expected_sequence, 11)
        self.assertEqual(observation.missing_count, 2)

    def test_gap_advances_high_water_mark(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(10)
        tracker.observe(13)

        self.assertEqual(tracker.last_sequence, 13)

    def test_late_value_after_gap_is_out_of_order(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(10)
        tracker.observe(13)

        observation = tracker.observe(11)

        self.assertEqual(observation.status, SequenceStatus.OUT_OF_ORDER)
        self.assertEqual(observation.expected_sequence, 14)
        self.assertEqual(tracker.last_sequence, 13)

    def test_out_of_order_does_not_lower_high_water_mark(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(10)

        self.assertEqual(tracker.observe(8).status, SequenceStatus.OUT_OF_ORDER)
        self.assertEqual(tracker.last_sequence, 10)

    def test_out_of_order_followed_by_next_value_is_in_order(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(10)
        tracker.observe(8)

        self.assertEqual(tracker.observe(11).status, SequenceStatus.IN_ORDER)

    def test_reset_makes_next_value_first(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(10)
        tracker.reset()

        observation = tracker.observe(3)

        self.assertEqual(observation.status, SequenceStatus.FIRST)
        self.assertEqual(tracker.last_sequence, 3)

    def test_trackers_keep_independent_state(self) -> None:
        first = SequenceTracker()
        second = SequenceTracker()
        first.observe(7)
        second.observe(100)

        self.assertEqual(first.observe(8).status, SequenceStatus.IN_ORDER)
        self.assertEqual(second.observe(100).status, SequenceStatus.DUPLICATE)

    def test_arbitrarily_large_python_ints_are_tracked_linearly(self) -> None:
        tracker = SequenceTracker()
        large = 10**250
        tracker.observe(large)

        observation = tracker.observe(large + 1)

        self.assertEqual(observation.status, SequenceStatus.IN_ORDER)
        self.assertEqual(tracker.last_sequence, large + 1)

    def test_invalid_wire_sequences_raise_stable_validation_error_without_state_change(self) -> None:
        tracker = SequenceTracker()
        tracker.observe(7)

        for value in (None, True, False, 1.5, "7", b"7", -1):
            with self.subTest(value=value):
                before = tracker.last_sequence
                with self.assertRaises(ValidationError) as raised:
                    tracker.observe(value)  # type: ignore[arg-type]
                self.assertEqual(raised.exception.code, "invalid_wire_sequence")
                self.assertEqual(raised.exception.stage, "sequence_tracking")
                self.assertEqual(tracker.last_sequence, before)


class SequenceObservationTests(unittest.TestCase):
    def test_observation_is_immutable_and_has_no_dynamic_attributes(self) -> None:
        observation = SequenceObservation(SequenceStatus.FIRST, 0, None, None, 0)

        with self.assertRaises(AttributeError):
            observation.wire_sequence = 1  # type: ignore[misc]
        with self.assertRaises((AttributeError, TypeError)):
            observation.extra = "not allowed"  # type: ignore[attr-defined]

    def test_direct_construction_rejects_invalid_field_types_and_ranges(self) -> None:
        invalid_cases = (
            (SequenceStatus.FIRST, True, None, None, 0),
            (SequenceStatus.FIRST, 0, None, None, True),
            (SequenceStatus.FIRST, -1, None, None, 0),
            (SequenceStatus.IN_ORDER, 1, None, None, 0),
            (SequenceStatus.IN_ORDER, 1, True, 2, 0),
            (SequenceStatus.IN_ORDER, 1, 0, False, 0),
        )

        for args in invalid_cases:
            with self.subTest(args=args), self.assertRaises(ValueError):
                SequenceObservation(*args)

    def test_direct_construction_enforces_first_invariants(self) -> None:
        for args in (
            (SequenceStatus.FIRST, 0, 0, None, 0),
            (SequenceStatus.FIRST, 0, None, 1, 0),
            (SequenceStatus.FIRST, 0, None, None, 1),
        ):
            with self.subTest(args=args), self.assertRaises(ValueError):
                SequenceObservation(*args)

    def test_direct_construction_enforces_non_gap_missing_count_rules(self) -> None:
        for args in (
            (SequenceStatus.IN_ORDER, 2, 1, 2, 1),
            (SequenceStatus.DUPLICATE, 1, 1, 2, 1),
            (SequenceStatus.OUT_OF_ORDER, 0, 1, 2, 1),
            (SequenceStatus.GAP, 3, 1, 2, 0),
        ):
            with self.subTest(args=args), self.assertRaises(ValueError):
                SequenceObservation(*args)

    def test_direct_construction_enforces_status_sequence_relationships(self) -> None:
        invalid_cases = (
            (SequenceStatus.IN_ORDER, 3, 1, 2, 0),
            (SequenceStatus.DUPLICATE, 2, 1, 2, 0),
            (SequenceStatus.GAP, 2, 1, 2, 1),
            (SequenceStatus.GAP, 4, 1, 2, 1),
            (SequenceStatus.OUT_OF_ORDER, 1, 1, 2, 0),
            (SequenceStatus.OUT_OF_ORDER, 0, 1, 3, 0),
        )

        for args in invalid_cases:
            with self.subTest(args=args), self.assertRaises(ValueError):
                SequenceObservation(*args)
