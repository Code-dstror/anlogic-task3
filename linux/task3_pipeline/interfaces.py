"""Abstract contracts for interchangeable pipeline adapters."""

from __future__ import annotations

from abc import ABC, abstractmethod
from threading import Event
from typing import Any, Mapping

from .models import DetectionResult, FrameEvent, ModelInput, SourceHealth


class FrameSource(ABC):
    """Produces logical frames or lifecycle events without exposing wire ABI."""

    @abstractmethod
    def start(self, config: Mapping[str, Any] | None = None) -> None:
        """Prepare the source using source-local configuration."""

    @abstractmethod
    def next_frame(self, stop_event: Event) -> FrameEvent:
        """Return the next frame or a lifecycle event.

        Implementations must return promptly when ``stop_event`` is set.
        """

    @abstractmethod
    def stop(self) -> None:
        """Release source-local resources and stop producing events."""

    @abstractmethod
    def health(self) -> SourceHealth:
        """Return a transport-agnostic health summary."""


class InferenceBackend(ABC):
    """Owns model lifecycle and inference, but not acquisition or rendering."""

    @abstractmethod
    def load(self, model_config: Mapping[str, Any]) -> None:
        """Load or initialize a model backend."""

    @abstractmethod
    def infer(self, model_input: ModelInput) -> DetectionResult:
        """Run inference on a single structured model input."""

    @abstractmethod
    def close(self) -> None:
        """Release model and runtime resources."""


class OutputSink(ABC):
    """Consumes postprocessed results without controlling inference."""

    @abstractmethod
    def start(self, config: Mapping[str, Any] | None = None) -> None:
        """Prepare the sink using sink-local configuration."""

    @abstractmethod
    def write(self, result: DetectionResult) -> None:
        """Publish one result."""

    @abstractmethod
    def close(self) -> None:
        """Flush and release sink-local resources."""
