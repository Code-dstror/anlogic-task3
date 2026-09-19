"""Hardware-agnostic user-space foundations for task 3.

Only shared types and abstract contracts live here. Protocol parsing, SGDMA,
and RKNN integration deliberately belong to later stages.
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
from .jpeg_payload_validator import JpegPayloadValidator
from .mock_file_source import MockFileFrameSource
from .opencv_jpeg_decoder import OpenCvJpegDecoder
from .models import (
    DecodedFrame,
    Detection,
    DetectionResult,
    EncodedFrame,
    FrameEvent,
    FrameEventKind,
    FrameMetadata,
    ModelInput,
    ModelInputSpec,
    PreprocessTransform,
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
    "JpegPayloadValidator",
    "MockFileFrameSource",
    "ModelInput",
    "ModelInputSpec",
    "OutputError",
    "OutputSink",
    "OpenCvJpegDecoder",
    "PipelineError",
    "PreprocessTransform",
    "RuntimeMetrics",
    "SourceError",
    "SourceHealth",
    "ValidationError",
]
