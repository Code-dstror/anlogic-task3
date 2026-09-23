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


class PreprocessError(PipelineError):
    """A model-preprocessing failure with stable ``stage`` and ``code``.

    Stable codes and their intended boundaries:

    * ``preprocess_invalid_frame_type``: unsupported frame object.
    * ``preprocess_unsupported_pixel_format``: input is not BGR24.
    * ``preprocess_invalid_dimensions``: invalid source dimensions.
    * ``preprocess_invalid_row_stride``: stride type, positivity, or packed-row
      coverage is invalid.
    * ``preprocess_invalid_pixel_buffer``: a required byte view cannot be made.
    * ``preprocess_pixel_buffer_too_small``: the last valid pixel is not covered.
    * ``preprocess_resource_limit_exceeded``: row padding above 256 bytes, the
      logical input span, or the supplied byte count exceeds its budget.
    * ``preprocess_color_conversion_failed``: OpenCV color conversion fails.
    * ``preprocess_resize_failed``: OpenCV resize fails.
    * ``preprocess_padding_failed``: OpenCV border padding fails.
    * ``preprocess_invalid_output``: output shape, dtype, dimensions, or
      contiguity violates the model-input contract.

    ``message`` is diagnostic text. Callers should classify by ``stage`` and
    ``code``; the default is fail-closed (``recoverable=False``).
    """

    def __init__(
        self,
        message: str,
        code: str,
        recoverable: bool = False,
        cause: BaseException | None = None,
    ) -> None:
        super().__init__(
            message=message,
            stage="model_preprocess",
            code=code,
            recoverable=recoverable,
            cause=cause,
        )


class InferenceError(PipelineError):
    """Raised by an inference backend."""


class OutputError(PipelineError):
    """Raised by an output sink."""
