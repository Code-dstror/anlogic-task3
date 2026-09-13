"""Diagnostic tracking for one linear, ordered wire-sequence ingest stream.

This module intentionally uses non-wrapping linear sequence semantics.  One
``SequenceTracker`` instance belongs to one ordered ingest stream and does not
promise thread-safe concurrent calls.  Sequence anomalies are diagnostic only:
they do not decide whether a valid payload continues through the pipeline.

Wire width, wrapping, stream epochs, and mapping an FPGA reset to ``reset()``
remain pending FPGA protocol confirmation.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .errors import ValidationError


class SequenceStatus(str, Enum):
    """Classification of one observed wire sequence value."""

    FIRST = "first"
    IN_ORDER = "in_order"
    DUPLICATE = "duplicate"
    GAP = "gap"
    OUT_OF_ORDER = "out_of_order"


@dataclass(frozen=True, slots=True)
class SequenceObservation:
    """An immutable diagnostic result for a single linear sequence value.

    The observation describes only sequence ordering.  It does not accept or
    drop a payload, allocate an ingest ID, or update runtime metrics.
    """

    status: SequenceStatus
    wire_sequence: int
    previous_sequence: int | None
    expected_sequence: int | None
    missing_count: int

    def __post_init__(self) -> None:
        if not isinstance(self.status, SequenceStatus):
            raise ValueError("status must be a SequenceStatus")
        _require_nonnegative_int(self.wire_sequence, "wire_sequence")
        _require_nonnegative_int(self.missing_count, "missing_count")

        if self.status is SequenceStatus.FIRST:
            if self.previous_sequence is not None or self.expected_sequence is not None:
                raise ValueError("FIRST observations must not have prior sequence values")
            if self.missing_count != 0:
                raise ValueError("FIRST observations must have zero missing_count")
            return

        if self.previous_sequence is None or self.expected_sequence is None:
            raise ValueError("non-FIRST observations require prior and expected sequences")
        _require_nonnegative_int(self.previous_sequence, "previous_sequence")
        _require_nonnegative_int(self.expected_sequence, "expected_sequence")
        if self.expected_sequence != self.previous_sequence + 1:
            raise ValueError("expected_sequence must follow previous_sequence")

        if self.status is SequenceStatus.IN_ORDER:
            if self.wire_sequence != self.expected_sequence or self.missing_count != 0:
                raise ValueError("IN_ORDER observations must match the expected sequence")
        elif self.status is SequenceStatus.DUPLICATE:
            if self.wire_sequence != self.previous_sequence or self.missing_count != 0:
                raise ValueError("DUPLICATE observations must repeat the previous sequence")
        elif self.status is SequenceStatus.GAP:
            expected_missing = self.wire_sequence - self.expected_sequence
            if expected_missing <= 0 or self.missing_count != expected_missing:
                raise ValueError("GAP observations require their exact positive missing_count")
        elif self.status is SequenceStatus.OUT_OF_ORDER:
            if self.wire_sequence >= self.previous_sequence or self.missing_count != 0:
                raise ValueError("OUT_OF_ORDER observations must precede the high-water mark")


class SequenceTracker:
    """Track sequence diagnostics for one non-wrapping ordered ingest stream.

    This class is not safe for concurrent calls.  It advances its high-water
    mark only for first, in-order, and gap observations.  Duplicate and
    out-of-order values remain diagnostics so valid payload processing can
    continue.  Wire width, wrapping, stream epochs, and FPGA-reset mapping are
    deliberately outside this hardware-agnostic component.
    """

    def __init__(self) -> None:
        self._last_sequence: int | None = None

    @property
    def last_sequence(self) -> int | None:
        """The current high-water mark, or ``None`` before the first value."""

        return self._last_sequence

    def observe(self, wire_sequence: int) -> SequenceObservation:
        """Classify ``wire_sequence`` and update the high-water mark if needed.

        Invalid values raise ``ValidationError(code="invalid_wire_sequence")``
        without changing tracker state.
        """

        if isinstance(wire_sequence, bool) or not isinstance(wire_sequence, int) or wire_sequence < 0:
            raise ValidationError(
                message="wire_sequence must be a non-boolean non-negative integer",
                stage="sequence_tracking",
                code="invalid_wire_sequence",
            )

        previous = self._last_sequence
        if previous is None:
            observation = SequenceObservation(
                status=SequenceStatus.FIRST,
                wire_sequence=wire_sequence,
                previous_sequence=None,
                expected_sequence=None,
                missing_count=0,
            )
            self._last_sequence = wire_sequence
            return observation

        expected = previous + 1
        if wire_sequence == expected:
            status = SequenceStatus.IN_ORDER
            missing_count = 0
            advance = True
        elif wire_sequence == previous:
            status = SequenceStatus.DUPLICATE
            missing_count = 0
            advance = False
        elif wire_sequence > expected:
            status = SequenceStatus.GAP
            missing_count = wire_sequence - expected
            advance = True
        else:
            status = SequenceStatus.OUT_OF_ORDER
            missing_count = 0
            advance = False

        observation = SequenceObservation(
            status=status,
            wire_sequence=wire_sequence,
            previous_sequence=previous,
            expected_sequence=expected,
            missing_count=missing_count,
        )
        if advance:
            self._last_sequence = wire_sequence
        return observation

    def reset(self) -> None:
        """Forget the high-water mark; reset timing is an upstream decision."""

        self._last_sequence = None


def _require_nonnegative_int(value: object, field_name: str) -> None:
    """Raise ``ValueError`` unless a dataclass field is a valid sequence int."""

    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{field_name} must be a non-boolean non-negative integer")
