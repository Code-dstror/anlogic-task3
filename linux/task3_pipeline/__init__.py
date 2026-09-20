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
from .mock_protocol_record_source import MockProtocolRecordSource
from .opencv_jpeg_decoder import OpenCvJpegDecoder
from .pcie_v1_record_parser import PcieV1Record, PcieV1RecordParser
from .pcie_v1_record_mapper import map_pcie_v1_record_to_encoded_frame
from .models import (
    DecodedFrame,
    Detection,
    DetectionResult,
    EncodedFrame,
    FrameEvent,
    FrameEventKind,
    FrameMetadata,
    ImmutableTensor,
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
    "ImmutableTensor",
    "JpegPayloadValidator",
    "MockFileFrameSource",
    "ModelInput",
    "ModelInputSpec",
    "MockProtocolRecordSource",
    "OutputError",
    "OutputSink",
    "OpenCvJpegDecoder",
    "PipelineError",
    "PreprocessTransform",
    "PcieV1Record",
    "PcieV1RecordParser",
    "map_pcie_v1_record_to_encoded_frame",
    "RuntimeMetrics",
    "SourceError",
    "SourceHealth",
    "ValidationError",
]
