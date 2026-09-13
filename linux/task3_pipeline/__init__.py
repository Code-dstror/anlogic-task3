"""Hardware-agnostic user-space foundations for task 3.

Only shared types and abstract contracts live here.  Protocol parsing, SGDMA,
JPEG decoding, and RKNN integration deliberately belong to later stages.
"""

from .errors import (
    ConfigurationError,
    DecodeError,
    InferenceError,
    OutputError,
    PipelineError,
    SourceError,
    ValidationError,
)
from .interfaces import FrameSource, InferenceBackend, OutputSink
from .models import (
    DecodedFrame,
    Detection,
    DetectionResult,
    EncodedFrame,
    FrameEvent,
    FrameEventKind,
    FrameMetadata,
    RuntimeMetrics,
    SourceHealth,
)

__all__ = [
    "ConfigurationError",
    "DecodeError",
    "DecodedFrame",
    "Detection",
    "DetectionResult",
    "EncodedFrame",
    "FrameEvent",
    "FrameEventKind",
    "FrameMetadata",
    "FrameSource",
    "InferenceBackend",
    "InferenceError",
    "OutputError",
    "OutputSink",
    "PipelineError",
    "RuntimeMetrics",
    "SourceError",
    "SourceHealth",
    "ValidationError",
]
