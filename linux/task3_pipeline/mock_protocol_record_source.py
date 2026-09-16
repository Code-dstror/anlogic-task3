"""Deterministic in-memory source for complete PCIe v1 record test inputs."""

from __future__ import annotations

from threading import Event
from time import monotonic_ns
from typing import Any, Callable, Iterable, Mapping

from .errors import ConfigurationError, SourceError
from .interfaces import FrameSource
from .models import FrameEvent, FrameEventKind, SourceHealth
from .pcie_v1_record_mapper import map_pcie_v1_record_to_encoded_frame
from .pcie_v1_record_parser import PcieV1RecordParser


class MockProtocolRecordSource(FrameSource):
    """Publish one parsed PCIe v1 record per call from caller-owned memory.

    ``records`` contains already complete ``[64-byte header][payload]`` PCIe
    v1 records.  This source does not frame chunks, combine reads, or access
    devices.  Each record is handed directly to :class:`PcieV1RecordParser`,
    preserving its bytes-like input and validation semantics.

    Parser and mapper errors deliberately escape unchanged.  A consumed
    invalid record is never retried; the lifecycle runner owns classification
    and metrics policy.  ``ingest_id`` is allocated locally only after a
    successful mapping and is independent of the record's wire sequence.
    """

    def __init__(
        self,
        records: Iterable[bytes | bytearray | memoryview],
        *,
        clock: Callable[[], int] = monotonic_ns,
    ) -> None:
        self._records = tuple(records)
        self._clock = clock
        self._parser = PcieV1RecordParser()
        self._next_index = 0
        self._next_ingest_id = 0
        self._closed = False
        self._started = False
        self._exhausted = False
        self._health = SourceHealth.STOPPED

    def start(self, config: Mapping[str, Any] | None = None) -> None:
        """Reset the record position for one deterministic pass."""

        if self._closed:
            raise SourceError(
                "cannot start a closed mock protocol record source",
                stage="mock_protocol_record_source",
                code="source_closed",
            )
        if self._started and not self._exhausted:
            raise SourceError(
                "mock protocol record source is already running",
                stage="mock_protocol_record_source",
                code="source_already_started",
            )
        if config:
            raise ConfigurationError(
                "MockProtocolRecordSource does not accept runtime configuration",
                stage="mock_protocol_record_source",
                code="unsupported_config",
            )

        self._next_index = 0
        self._started = True
        self._exhausted = False
        self._health = SourceHealth.READY

    def next_frame(self, stop_event: Event) -> FrameEvent:
        """Map one complete record, or return the common EOF event."""

        if not self._started or self._closed or self._exhausted:
            return FrameEvent(FrameEventKind.END_OF_STREAM)
        if stop_event.is_set():
            self.stop()
            return FrameEvent(FrameEventKind.END_OF_STREAM, detail="stop requested")
        if self._next_index >= len(self._records):
            self._finish_pass()
            return FrameEvent(FrameEventKind.END_OF_STREAM)

        record_bytes = self._records[self._next_index]
        # Consume before parsing: a validation failure belongs to this complete
        # candidate record, and the caller can continue with the next one.
        self._next_index += 1
        record = self._parser.parse(record_bytes)
        received_monotonic_ns = self._clock()
        frame = map_pcie_v1_record_to_encoded_frame(
            record,
            ingest_id=self._next_ingest_id,
            received_monotonic_ns=received_monotonic_ns,
            source_name="mock_protocol_record",
        )
        self._next_ingest_id += 1
        return FrameEvent(FrameEventKind.FRAME, frame)

    def stop(self) -> None:
        """End the current pass; a later ``start()`` may begin another."""

        self._started = False
        self._exhausted = True
        self._health = SourceHealth.STOPPED

    def close(self) -> None:
        """Permanently close the source. Calling this method repeatedly is safe."""

        if self._closed:
            return
        self.stop()
        self._closed = True

    def health(self) -> SourceHealth:
        """Return the current source health without transport-specific detail."""

        return self._health

    def _finish_pass(self) -> None:
        self._started = False
        self._exhausted = True
        self._health = SourceHealth.STOPPED
