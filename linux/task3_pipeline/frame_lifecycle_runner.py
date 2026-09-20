"""Explicit single-step lifecycle control for one frame source."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from threading import Event
from typing import Any, Mapping, Protocol

from .errors import ConfigurationError, DecodeError, PipelineError, SourceError, ValidationError
from .frame_error_policy import FrameErrorDisposition, classify_frame_error
from .interfaces import FrameSource
from .models import (
    DecodedFrame,
    EncodedFrame,
    FrameEvent,
    FrameEventKind,
    RuntimeMetrics,
    SourceHealth,
)
from .sequence_tracker import SequenceTracker
from .single_frame_pipeline import SingleFramePipeline


class _FrameValidator(Protocol):
    """The validator capability used by ``SingleFramePipeline``."""

    def validate(self, frame: EncodedFrame) -> EncodedFrame: ...


class _FrameDecoder(Protocol):
    """The decoder capability used by ``SingleFramePipeline``."""

    def decode(self, frame: EncodedFrame) -> DecodedFrame: ...


class FrameStepOutcomeKind(str, Enum):
    """The result category of one explicit runner step."""

    DELIVERED = "delivered"
    EVENT = "event"
    DROPPED_FRAME = "dropped_frame"


@dataclass(frozen=True, slots=True)
class FrameStepOutcome:
    """Exactly one delivered frame, lifecycle event, or dropped-frame error."""

    kind: FrameStepOutcomeKind
    decoded_frame: DecodedFrame | None = None
    event: FrameEvent | None = None
    error: PipelineError | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.kind, FrameStepOutcomeKind):
            raise ValueError("kind must be a FrameStepOutcomeKind")

        fields = (self.decoded_frame, self.event, self.error)
        if sum(value is not None for value in fields) != 1:
            raise ValueError("a frame step outcome must carry exactly one value")
        if self.kind is FrameStepOutcomeKind.DELIVERED:
            if self.decoded_frame is None or self.event is not None or self.error is not None:
                raise ValueError("DELIVERED outcomes require only decoded_frame")
        elif self.kind is FrameStepOutcomeKind.EVENT:
            if self.event is None or self.decoded_frame is not None or self.error is not None:
                raise ValueError("EVENT outcomes require only event")
        elif self.kind is FrameStepOutcomeKind.DROPPED_FRAME:
            if self.error is None or self.decoded_frame is not None or self.event is not None:
                raise ValueError("DROPPED_FRAME outcomes require only error")


class _RunnerState(Enum):
    IDLE = "idle"
    RUNNING = "running"
    TERMINATED = "terminated"


class FrameLifecycleRunner:
    """Run one source event at a time with explicit lifecycle transitions."""

    def __init__(
        self,
        source: FrameSource,
        validator: _FrameValidator,
        decoder: _FrameDecoder,
        sequence_tracker: SequenceTracker,
        metrics: RuntimeMetrics,
    ) -> None:
        self._source = source
        self._metrics = metrics
        self._pipeline = SingleFramePipeline(
            source, validator, decoder, sequence_tracker, metrics
        )
        self._state = _RunnerState.IDLE

    def start(self, config: Mapping[str, Any] | None = None) -> None:
        """Start the source explicitly, without resetting sequence state."""

        if self._state is _RunnerState.RUNNING:
            raise ConfigurationError(
                "frame lifecycle runner is already running",
                stage="frame_lifecycle_runner",
                code="runner_already_running",
            )
        self._source.start(config)
        self._state = _RunnerState.RUNNING

    def step(self, stop_event: Event) -> FrameStepOutcome:
        """Process no more than one source event."""

        if self._state is not _RunnerState.RUNNING:
            raise ConfigurationError(
                "frame lifecycle runner is not running",
                stage="frame_lifecycle_runner",
                code="runner_not_running",
            )

        try:
            result = self._pipeline.process_next(stop_event)
        except (ValidationError, DecodeError) as error:
            try:
                disposition = classify_frame_error(error)
            except Exception:
                self._state = _RunnerState.TERMINATED
                raise
            if disposition is FrameErrorDisposition.CONTINUE_NEXT_FRAME:
                return FrameStepOutcome(FrameStepOutcomeKind.DROPPED_FRAME, error=error)
            self._state = _RunnerState.TERMINATED
            raise
        except SourceError:
            self._state = _RunnerState.TERMINATED
            raise
        except Exception:
            self._state = _RunnerState.TERMINATED
            raise

        if isinstance(result, DecodedFrame):
            return FrameStepOutcome(FrameStepOutcomeKind.DELIVERED, decoded_frame=result)

        if result.kind is FrameEventKind.NO_DATA:
            return FrameStepOutcome(FrameStepOutcomeKind.EVENT, event=result)
        if result.kind in (
            FrameEventKind.RECOVERABLE_DISCONNECT,
            FrameEventKind.FATAL_ERROR,
        ):
            self._metrics.record_source_error()
            self._state = _RunnerState.TERMINATED
        elif result.kind is FrameEventKind.END_OF_STREAM:
            self._state = _RunnerState.TERMINATED
        return FrameStepOutcome(FrameStepOutcomeKind.EVENT, event=result)

    def stop(self) -> None:
        """Delegate stop directly to the source."""

        self._source.stop()
        self._state = _RunnerState.IDLE

    def health(self) -> SourceHealth:
        """Return the source health without caching or reinterpretation."""

        return self._source.health()
