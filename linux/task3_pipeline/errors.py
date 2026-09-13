"""Project-level exceptions shared by pipeline stages."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(eq=False)
class PipelineError(Exception):
    """A pipeline failure with stable machine-readable context.

    ``stage`` and ``code`` are project-level identifiers, not transport ABI
    fields.  A later source implementation can attach the original exception
    in ``cause`` without exposing device-specific values to common code.
    """

    message: str
    stage: str
    code: str
    recoverable: bool = False
    cause: BaseException | None = None

    def __post_init__(self) -> None:
        Exception.__init__(self, self.message)


class ConfigurationError(PipelineError):
    """Raised for invalid local pipeline configuration."""


class SourceError(PipelineError):
    """Raised by a frame source when it cannot continue normally."""


class ValidationError(PipelineError):
    """Raised by a future transport or JPEG-payload validator."""


class DecodeError(PipelineError):
    """Raised by a future JPEG decoder adapter."""


class InferenceError(PipelineError):
    """Raised by an inference backend."""


class OutputError(PipelineError):
    """Raised by an output sink."""
