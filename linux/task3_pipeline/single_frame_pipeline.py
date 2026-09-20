"""One-event orchestration for the hardware-agnostic JPEG pipeline."""

from __future__ import annotations

from threading import Event

from .errors import DecodeError, SourceError, ValidationError
from .frame_error_policy import is_transport_record_invalid_error
from .interfaces import FrameSource
from .jpeg_payload_validator import JpegPayloadValidator
from .models import DecodedFrame, FrameEvent, FrameEventKind, RuntimeMetrics
from .opencv_jpeg_decoder import OpenCvJpegDecoder
from .sequence_tracker import SequenceStatus, SequenceTracker


class SingleFramePipeline:
    """Process at most one source event without managing source lifecycle.

    The pipeline owns received, delivered, and dropped-frame metric updates for
    one ``FRAME`` event.  Non-frame events pass through unchanged, while source,
    validation, and decode errors retain their existing exception types. A
    source may report an allowlisted PCIe v1 record error only after it has
    assembled exactly one record candidate; those errors are counted here and
    still re-raised for the lifecycle runner to classify.
    """

    def __init__(
        self,
        source: FrameSource,
        validator: JpegPayloadValidator,
        decoder: OpenCvJpegDecoder,
        sequence_tracker: SequenceTracker,
        metrics: RuntimeMetrics,
    ) -> None:
        self._source = source
        self._validator = validator
        self._decoder = decoder
        self._sequence_tracker = sequence_tracker
        self._metrics = metrics

    def process_next(self, stop_event: Event) -> DecodedFrame | FrameEvent:
        """Process one source event, returning a decoded frame or passthrough event."""

        try:
            event = self._source.next_frame(stop_event)
        except ValidationError as error:
            if is_transport_record_invalid_error(error):
                self._metrics.record_transport_invalid(error.code)
                self._metrics.record_drop(f"transport_validation:{error.code}")
            raise
        except SourceError:
            self._metrics.record_source_error()
            raise

        if event.kind is not FrameEventKind.FRAME:
            return event

        frame = event.frame
        assert frame is not None
        self._metrics.record_received()

        if frame.metadata.wire_sequence is not None:
            try:
                observation = self._sequence_tracker.observe(frame.metadata.wire_sequence)
            except ValidationError as error:
                self._metrics.record_drop(f"sequence_validation:{error.code}")
                raise
            if observation.status is SequenceStatus.DUPLICATE:
                self._metrics.record_sequence_anomaly("duplicate")
            elif observation.status is SequenceStatus.GAP:
                self._metrics.record_sequence_anomaly("gap")
            elif observation.status is SequenceStatus.OUT_OF_ORDER:
                self._metrics.record_sequence_anomaly("out_of_order")

        try:
            validated_frame = self._validator.validate(frame)
        except ValidationError as error:
            self._metrics.record_jpeg_invalid(error.code)
            self._metrics.record_drop(f"jpeg_validation:{error.code}")
            raise

        try:
            decoded_frame = self._decoder.decode(validated_frame)
        except DecodeError as error:
            self._metrics.record_drop(f"jpeg_decode:{error.code}")
            raise

        self._metrics.record_delivered()
        return decoded_frame
