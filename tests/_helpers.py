"""Shared test-only helpers for pipeline model fixtures."""

from __future__ import annotations

from linux.task3_pipeline import FrameMetadata


def make_metadata(**overrides: object) -> FrameMetadata:
    values: dict[str, object] = {
        "ingest_id": 7,
        "source_name": "mock_file",
        "payload_length": 3,
        "received_monotonic_ns": 100,
        "wire_sequence": 42,
    }
    values.update(overrides)
    return FrameMetadata(**values)  # type: ignore[arg-type]
