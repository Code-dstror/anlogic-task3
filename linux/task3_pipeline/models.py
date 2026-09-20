"""Shared, hardware-agnostic data types for the user-space pipeline.

These types intentionally do not describe PCIe wire records, BAR registers,
slot ownership, device names, or model-specific tensor layouts.  Such details
must be handled by source or adapter implementations after their contracts are
confirmed.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from math import floor, isfinite
from numbers import Integral, Real
from threading import Lock
from types import MappingProxyType
from typing import Any, Mapping

import numpy as np


def _require_positive_integer(value: object, name: str) -> int:
    """Return a positive integer while rejecting bool and lossy coercions."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    value = int(value)
    if value <= 0:
        raise ValueError(f"{name} must be positive")
    return value


def _require_non_negative_integer(value: object, name: str) -> int:
    """Return a non-negative integer while rejecting bool and lossy coercions."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    value = int(value)
    if value < 0:
        raise ValueError(f"{name} must be non-negative")
    return value


def _round_scaled_dimension(original_dimension: int, scale: float) -> int:
    """Round a scaled size to nearest integer, with exact .5 values rounded up."""
    return floor(original_dimension * scale + 0.5)


class _ImmutableTensorFlags:
    """The immutable subset of ndarray flags exposed by :class:`ImmutableTensor`."""

    __slots__ = ()

    @property
    def c_contiguous(self) -> bool:
        return True

    @property
    def writeable(self) -> bool:
        return False

    def __setattr__(self, name: str, value: object) -> None:
        raise AttributeError("ImmutableTensor flags cannot be changed")


class ImmutableTensor:
    """A bytes-backed tensor whose content and public header cannot be changed.

    ``to_numpy()`` creates a temporary ndarray view for a synchronous backend.
    Its header may be changed independently, but its immutable bytes backing
    and any temporary header changes cannot alter this tensor's contract.
    """

    __slots__ = ("_backing", "_shape", "_dtype", "_strides", "_flags")

    def __init__(
        self,
        backing: object,
        shape: tuple[int, ...],
        dtype: np.dtype,
        strides: tuple[int, ...],
    ) -> None:
        if isinstance(backing, bytes):
            frozen_backing = backing
        else:
            try:
                frozen_backing = memoryview(backing).tobytes()
            except TypeError as error:
                raise TypeError("backing must be a bytes-like buffer") from error
        dtype = np.dtype(dtype)
        if dtype.hasobject:
            raise TypeError("object-containing dtypes are not supported by ImmutableTensor")
        object.__setattr__(self, "_backing", frozen_backing)
        object.__setattr__(self, "_shape", shape)
        object.__setattr__(self, "_dtype", dtype)
        object.__setattr__(self, "_strides", strides)
        object.__setattr__(self, "_flags", _ImmutableTensorFlags())

    def __setattr__(self, name: str, value: object) -> None:
        raise AttributeError("ImmutableTensor header cannot be changed")

    @classmethod
    def from_array(cls, source: np.ndarray) -> "ImmutableTensor":
        """Copy ``source`` into C-contiguous immutable bytes."""
        if np.dtype(source.dtype).hasobject:
            raise TypeError("object-containing dtypes are not supported by ImmutableTensor")
        contiguous = np.array(source, copy=True, order="C")
        backing = contiguous.tobytes(order="C")
        return cls(backing, contiguous.shape, contiguous.dtype, contiguous.strides)

    @property
    def shape(self) -> tuple[int, ...]:
        """The fixed tensor shape."""
        return self._shape

    @property
    def dtype(self) -> np.dtype:
        """The fixed tensor dtype."""
        return self._dtype

    @property
    def strides(self) -> tuple[int, ...]:
        """The fixed C-contiguous byte strides."""
        return self._strides

    @property
    def flags(self) -> _ImmutableTensorFlags:
        """Immutable flags; the tensor is always C-contiguous and read-only."""
        return self._flags

    @property
    def ndim(self) -> int:
        """The fixed number of dimensions."""
        return len(self._shape)

    @property
    def size(self) -> int:
        """The fixed number of elements."""
        return int(np.prod(self._shape, dtype=np.intp))

    def to_numpy(self, *, copy: bool = False) -> np.ndarray:
        """Return a temporary ndarray view, or an independent mutable copy.

        Header changes to the returned ndarray never change this immutable
        wrapper. The default view remains element-read-only because it is
        backed by ``bytes``; callers needing a mutable ndarray must request a
        copy explicitly.
        """
        view = np.ndarray(
            shape=self._shape,
            dtype=self._dtype,
            buffer=self._backing,
            strides=self._strides,
        )
        return view.copy() if copy else view

    def __array__(self, dtype: np.dtype | None = None, copy: bool | None = None) -> np.ndarray:
        """Allow NumPy conversion without exposing this wrapper's header."""
        view = self.to_numpy()
        if dtype is not None:
            view = view.astype(dtype, copy=False)
        return view.copy() if copy else view

    def __getitem__(self, key: object) -> Any:
        """Read an element or temporary read-only slice."""
        return self.to_numpy()[key]

    def __setitem__(self, key: object, value: object) -> None:
        raise TypeError("ImmutableTensor does not support item assignment")

    def setflags(self, *, write: bool | None = None, **_: object) -> None:
        """Reject ndarray-style attempts to make the tensor writeable."""
        raise ValueError("ImmutableTensor flags cannot be changed")


class FrameEventKind(str, Enum):
    """Kinds of events a :class:`FrameSource` can publish."""

    FRAME = "frame"
    NO_DATA = "no_data"
    RECOVERABLE_DISCONNECT = "recoverable_disconnect"
    FATAL_ERROR = "fatal_error"
    END_OF_STREAM = "end_of_stream"


class SourceHealth(str, Enum):
    """A source health summary that does not expose transport internals."""

    STOPPED = "stopped"
    STARTING = "starting"
    READY = "ready"
    DEGRADED = "degraded"
    FAILED = "failed"


@dataclass(frozen=True, slots=True)
class ModelInputSpec:
    """Explicit, configurable image-tensor contract for one model input.

    The currently verified YOLOv5 profile is selected by a caller explicitly
    providing ``width=640`` and ``height=640``.  Width and height deliberately
    have no constructor defaults, so 640x640 is not a system-wide fixed
    resolution.  A future model can provide a distinct specification without
    changing frame ownership or transform contracts.
    """
    width: int
    height: int
    batch_size: int = 1
    channels: int = 3
    color_format: str = "RGB"
    layout: str = "NHWC"
    dtype: np.dtype | str = np.dtype("uint8")
    padding_value: int | float = 0

    def __post_init__(self) -> None:
        for name in ("width", "height", "batch_size", "channels"):
            object.__setattr__(self, name, _require_positive_integer(getattr(self, name), name))
        if self.batch_size != 1:
            raise ValueError("only batch_size=1 is supported by the ModelInput contract")
        if not self.color_format:
            raise ValueError("color_format must not be empty")
        if self.layout not in {"NHWC", "NCHW"}:
            raise ValueError("layout must be NHWC or NCHW")
        try:
            dtype = np.dtype(self.dtype)
        except TypeError as error:
            raise ValueError("dtype must be a NumPy-compatible dtype") from error
        if dtype.kind not in {"u", "i", "f"}:
            raise ValueError("dtype must be an integer or floating-point image tensor dtype")
        if dtype.kind in {"u", "i"}:
            if isinstance(self.padding_value, (bool, np.bool_)) or not isinstance(
                self.padding_value, Integral
            ):
                raise TypeError("padding_value must be an integer for an integer dtype")
            padding_value = int(self.padding_value)
            limits = np.iinfo(dtype)
            if not limits.min <= padding_value <= limits.max:
                raise ValueError("padding_value is outside the dtype range")
            padding_value = dtype.type(padding_value).item()
        else:
            if isinstance(self.padding_value, (bool, np.bool_)) or not isinstance(
                self.padding_value, Real
            ):
                raise TypeError("padding_value must be a real number for a floating-point dtype")
            raw_value = np.asarray(self.padding_value)
            comparison_dtype = np.result_type(raw_value.dtype, dtype)
            try:
                candidate = np.asarray(self.padding_value, dtype=comparison_dtype)[()]
            except (OverflowError, TypeError, ValueError) as error:
                raise ValueError("padding_value is outside the dtype range") from error
            if not np.isfinite(candidate):
                raise ValueError("padding_value must be finite and within the dtype range")
            limits = np.finfo(dtype)
            if candidate < np.asarray(limits.min, dtype=comparison_dtype)[()] or candidate > np.asarray(
                limits.max, dtype=comparison_dtype
            )[()]:
                raise ValueError("padding_value is outside the dtype range")
            with np.errstate(over="ignore", invalid="ignore"):
                padding_value = np.asarray(self.padding_value, dtype=dtype)[()]
            if not np.isfinite(padding_value):
                raise ValueError("padding_value must be finite and within the dtype range")
            padding_value = dtype.type(padding_value).item()
        object.__setattr__(self, "dtype", dtype)
        object.__setattr__(self, "padding_value", padding_value)

    @property
    def shape(self) -> tuple[int, int, int, int]:
        """Tensor shape required by this specification, including its batch."""
        if self.layout == "NHWC":
            return (self.batch_size, self.height, self.width, self.channels)
        return (self.batch_size, self.channels, self.height, self.width)


@dataclass(frozen=True, slots=True)
class PreprocessTransform:
    """Source-to-model geometry recorded by a future preprocessor.

    This is descriptive data only.  Resize, letterbox, and coordinate mapping
    algorithms remain outside this shared-contract change.
    """
    source_width: int
    source_height: int
    model_width: int
    model_height: int
    scale: float
    pad_left: int
    pad_top: int
    pad_right: int
    pad_bottom: int

    def __post_init__(self) -> None:
        for name in ("source_width", "source_height", "model_width", "model_height"):
            object.__setattr__(self, name, _require_positive_integer(getattr(self, name), name))
        for name in ("pad_left", "pad_top", "pad_right", "pad_bottom"):
            object.__setattr__(self, name, _require_non_negative_integer(getattr(self, name), name))
        if isinstance(self.scale, (bool, np.bool_)) or not isinstance(self.scale, Real):
            raise TypeError("scale must be a real number")
        scale = float(self.scale)
        if not isfinite(scale) or scale <= 0:
            raise ValueError("scale must be finite and positive")
        object.__setattr__(self, "scale", scale)

        scaled_width = _round_scaled_dimension(self.source_width, scale)
        scaled_height = _round_scaled_dimension(self.source_height, scale)
        if scaled_width < 1 or scaled_height < 1:
            raise ValueError("scaled dimensions must round to at least 1")
        if scaled_width + self.pad_left + self.pad_right != self.model_width:
            raise ValueError("scaled width and horizontal padding must equal model_width")
        if scaled_height + self.pad_top + self.pad_bottom != self.model_height:
            raise ValueError("scaled height and vertical padding must equal model_height")

    @property
    def ratio(self) -> float:
        """Uniform source-to-model scale ratio."""
        return self.scale

    @property
    def scaled_width(self) -> int:
        """Width after applying the documented nearest, half-up rounding rule."""
        return _round_scaled_dimension(self.source_width, self.scale)

    @property
    def scaled_height(self) -> int:
        """Height after applying the documented nearest, half-up rounding rule."""
        return _round_scaled_dimension(self.source_height, self.scale)


@dataclass(frozen=True, slots=True)
class ModelInput:
    """Owned, immutable tensor plus its complete source-frame association.

    Construction copies the input into immutable ``bytes`` and exposes an
    :class:`ImmutableTensor`, rather than a mutable ndarray header. Its bytes
    backing remains referenced for the complete synchronous inference call.
    """
    metadata: "FrameMetadata"
    data: np.ndarray | ImmutableTensor
    spec: ModelInputSpec
    transform: PreprocessTransform

    def __post_init__(self) -> None:
        if not isinstance(self.metadata, FrameMetadata):
            raise TypeError("metadata must be FrameMetadata")
        if not isinstance(self.data, np.ndarray):
            raise TypeError("data must be a NumPy array")
        if not isinstance(self.spec, ModelInputSpec):
            raise TypeError("spec must be ModelInputSpec")
        if not isinstance(self.transform, PreprocessTransform):
            raise TypeError("transform must be PreprocessTransform")
        if self.spec.batch_size != 1:
            raise ValueError("ModelInput supports only batch_size=1")
        if self.transform.model_width != self.spec.width or self.transform.model_height != self.spec.height:
            raise ValueError("transform target dimensions must match spec")
        if self.data.shape != self.spec.shape:
            raise ValueError("data shape must match spec.shape")
        if self.data.dtype != self.spec.dtype:
            raise ValueError("data dtype must match spec.dtype")
        object.__setattr__(self, "data", ImmutableTensor.from_array(self.data))


@dataclass(frozen=True, slots=True)
class FrameMetadata:
    """Metadata associated with one logical encoded frame.

    ``ingest_id`` is a local, monotonically increasing identifier assigned to
    every successfully accepted frame.  ``wire_sequence`` is optional source
    metadata and must never be substituted for ``ingest_id``: it can repeat,
    jump, or wrap without breaking local result association.
    """

    ingest_id: int
    source_name: str
    payload_length: int
    received_monotonic_ns: int
    frame_id: str | None = None
    wire_sequence: int | None = None
    source_timestamp: int | None = None
    timestamp_domain: str | None = None
    transport: str | None = None
    encoding: str | None = None
    declared_width: int | None = None
    declared_height: int | None = None
    integrity: Mapping[str, Any] = field(default_factory=dict)
    protocol_version: int | None = None
    extensions: Mapping[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.ingest_id < 0:
            raise ValueError("ingest_id must be non-negative")
        if not self.source_name:
            raise ValueError("source_name must not be empty")
        if self.payload_length < 0:
            raise ValueError("payload_length must be non-negative")
        if self.received_monotonic_ns < 0:
            raise ValueError("received_monotonic_ns must be non-negative")
        if self.wire_sequence is not None and self.wire_sequence < 0:
            raise ValueError("wire_sequence must be non-negative when present")
        if self.declared_width is not None and self.declared_width <= 0:
            raise ValueError("declared_width must be positive when present")
        if self.declared_height is not None and self.declared_height <= 0:
            raise ValueError("declared_height must be positive when present")
        object.__setattr__(self, "integrity", MappingProxyType(dict(self.integrity)))
        object.__setattr__(self, "extensions", MappingProxyType(dict(self.extensions)))


@dataclass(frozen=True, slots=True)
class EncodedFrame:
    """A complete logical encoded payload ready for common processing."""

    metadata: FrameMetadata
    payload: bytes
    acquired_monotonic_ns: int
    payload_capacity: int | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.payload, (bytes, bytearray, memoryview)):
            raise TypeError("payload must be bytes, bytearray, or memoryview")
        # Frame instances may outlive a source buffer.  Copy mutable views at
        # this boundary so a frozen frame cannot be changed through that buffer.
        object.__setattr__(self, "payload", bytes(self.payload))
        if self.acquired_monotonic_ns < 0:
            raise ValueError("acquired_monotonic_ns must be non-negative")
        if len(self.payload) != self.metadata.payload_length:
            raise ValueError("payload length must match metadata.payload_length")
        if self.payload_capacity is not None:
            if self.payload_capacity < 0:
                raise ValueError("payload_capacity must be non-negative")
            if len(self.payload) > self.payload_capacity:
                raise ValueError("payload exceeds payload_capacity")


@dataclass(frozen=True, slots=True)
class DecodedFrame:
    """Decoded pixel data; the pixel format and stride are explicit."""

    metadata: FrameMetadata
    pixels: bytes
    width: int
    height: int
    pixel_format: str
    row_stride: int
    decoded_monotonic_ns: int

    def __post_init__(self) -> None:
        if not isinstance(self.pixels, (bytes, bytearray, memoryview)):
            raise TypeError("pixels must be bytes, bytearray, or memoryview")
        # Decoders commonly reuse their output buffers; publish a private,
        # immutable copy rather than retaining a caller-owned view.
        object.__setattr__(self, "pixels", bytes(self.pixels))
        if self.width <= 0 or self.height <= 0:
            raise ValueError("decoded dimensions must be positive")
        if not self.pixel_format:
            raise ValueError("pixel_format must not be empty")
        if self.row_stride <= 0:
            raise ValueError("row_stride must be positive")
        if self.decoded_monotonic_ns < 0:
            raise ValueError("decoded_monotonic_ns must be non-negative")


@dataclass(frozen=True, slots=True)
class Detection:
    """One postprocessed detection in an explicitly named coordinate space."""

    class_id: int
    score: float
    bbox: tuple[float, float, float, float]
    label: str | None = None
    coordinate_space: str = "decoded_image"

    def __post_init__(self) -> None:
        if not 0.0 <= self.score <= 1.0:
            raise ValueError("score must be in [0.0, 1.0]")
        if not self.coordinate_space:
            raise ValueError("coordinate_space must not be empty")


@dataclass(frozen=True, slots=True)
class DetectionResult:
    """Inference result associated with a local ingest and optional wire ID.

    ``preprocess_transform`` accepts ``None``, a validated
    :class:`PreprocessTransform`, an empty mapping (normalized to ``None``),
    or a mapping containing exactly the fields of ``PreprocessTransform``.
    The stored value is always ``None`` or a validated structured transform.
    """

    ingest_id: int
    inference_started_monotonic_ns: int
    inference_finished_monotonic_ns: int
    detections: tuple[Detection, ...] = ()
    model_id: str | None = None
    model_version: str | None = None
    frame_id: str | None = None
    wire_sequence: int | None = None
    source_timestamp: int | None = None
    preprocess_transform: PreprocessTransform | Mapping[str, Any] | None = None
    status: str = "ok"
    error: str | None = None

    def __post_init__(self) -> None:
        if self.ingest_id < 0:
            raise ValueError("ingest_id must be non-negative")
        if self.inference_started_monotonic_ns < 0:
            raise ValueError("inference_started_monotonic_ns must be non-negative")
        if self.inference_finished_monotonic_ns < self.inference_started_monotonic_ns:
            raise ValueError("inference_finished_monotonic_ns precedes start")
        if self.wire_sequence is not None and self.wire_sequence < 0:
            raise ValueError("wire_sequence must be non-negative when present")
        object.__setattr__(
            self,
            "preprocess_transform",
            _normalize_preprocess_transform(self.preprocess_transform),
        )


_PREPROCESS_TRANSFORM_FIELDS = (
    "source_width",
    "source_height",
    "model_width",
    "model_height",
    "scale",
    "pad_left",
    "pad_top",
    "pad_right",
    "pad_bottom",
)


def _normalize_preprocess_transform(
    value: PreprocessTransform | Mapping[str, Any] | None,
) -> PreprocessTransform | None:
    """Normalize the supported legacy mapping representation at the boundary."""
    if value is None or isinstance(value, PreprocessTransform):
        return value
    if not isinstance(value, Mapping):
        raise TypeError("preprocess_transform must be None, PreprocessTransform, or a mapping")
    if not value:
        return None

    actual_fields = set(value)
    expected_fields = set(_PREPROCESS_TRANSFORM_FIELDS)
    unknown_fields = actual_fields - expected_fields
    if unknown_fields:
        raise ValueError(f"preprocess_transform contains unknown fields: {sorted(unknown_fields)!r}")
    missing_fields = expected_fields - actual_fields
    if missing_fields:
        raise ValueError(f"preprocess_transform is missing fields: {sorted(missing_fields)!r}")
    return PreprocessTransform(**{name: value[name] for name in _PREPROCESS_TRANSFORM_FIELDS})


@dataclass(frozen=True, slots=True)
class FrameEvent:
    """One event returned by a frame source.

    Only ``FRAME`` events carry a frame.  Other events may contain a textual
    detail for logs, but leave transport-specific diagnostics inside the source.
    """

    kind: FrameEventKind
    frame: EncodedFrame | None = None
    detail: str | None = None

    def __post_init__(self) -> None:
        if self.kind is FrameEventKind.FRAME and self.frame is None:
            raise ValueError("FRAME events require an EncodedFrame")
        if self.kind is not FrameEventKind.FRAME and self.frame is not None:
            raise ValueError("only FRAME events may carry an EncodedFrame")


@dataclass(slots=True)
class RuntimeMetrics:
    """Thread-safe counters and queue watermarks for a pipeline run.

    This Stage-A type deliberately records counters only.  Histograms, FPS
    windows, and stage timers can be layered on later without changing model
    or source contracts.
    """

    _frames_received: int = field(default=0, init=False, repr=False)
    _frames_delivered: int = field(default=0, init=False, repr=False)
    _frames_dropped: int = field(default=0, init=False, repr=False)
    _transport_records_invalid: int = field(default=0, init=False, repr=False)
    _jpeg_payloads_invalid: int = field(default=0, init=False, repr=False)
    _sequence_duplicate: int = field(default=0, init=False, repr=False)
    _sequence_gap: int = field(default=0, init=False, repr=False)
    _sequence_out_of_order: int = field(default=0, init=False, repr=False)
    _source_reconnects: int = field(default=0, init=False, repr=False)
    _source_errors: int = field(default=0, init=False, repr=False)
    _drop_reasons: dict[str, int] = field(default_factory=dict, init=False, repr=False)
    _transport_invalid_reasons: dict[str, int] = field(
        default_factory=dict, init=False, repr=False
    )
    _jpeg_invalid_reasons: dict[str, int] = field(
        default_factory=dict, init=False, repr=False
    )
    _queue_depth: dict[str, int] = field(default_factory=dict, init=False, repr=False)
    _queue_high_watermark: dict[str, int] = field(
        default_factory=dict, init=False, repr=False
    )
    _lock: Lock = field(default_factory=Lock, init=False, repr=False, compare=False)

    @property
    def source_errors(self) -> int:
        """Current source-error count, read under the metrics lock."""

        with self._lock:
            return self._source_errors

    @property
    def source_reconnects(self) -> int:
        """Current source-reconnect count, read under the metrics lock."""

        with self._lock:
            return self._source_reconnects

    def record_received(self) -> None:
        with self._lock:
            self._frames_received += 1

    def record_delivered(self) -> None:
        with self._lock:
            self._frames_delivered += 1

    def record_drop(self, reason: str) -> None:
        with self._lock:
            self._frames_dropped += 1
            self._drop_reasons[reason] = self._drop_reasons.get(reason, 0) + 1

    def record_transport_invalid(self, reason: str) -> None:
        with self._lock:
            self._transport_records_invalid += 1
            self._transport_invalid_reasons[reason] = (
                self._transport_invalid_reasons.get(reason, 0) + 1
            )

    def record_jpeg_invalid(self, reason: str) -> None:
        with self._lock:
            self._jpeg_payloads_invalid += 1
            self._jpeg_invalid_reasons[reason] = (
                self._jpeg_invalid_reasons.get(reason, 0) + 1
            )

    def record_source_error(self) -> None:
        with self._lock:
            self._source_errors += 1

    def record_source_reconnect(self) -> None:
        with self._lock:
            self._source_reconnects += 1

    def record_sequence_anomaly(self, kind: str) -> None:
        """Record a diagnostic-only sequence anomaly without dropping a frame."""

        with self._lock:
            if kind == "duplicate":
                self._sequence_duplicate += 1
            elif kind == "gap":
                self._sequence_gap += 1
            elif kind in {"out_of_order", "backward_jump"}:
                self._sequence_out_of_order += 1
            else:
                raise ValueError(f"unknown sequence anomaly kind: {kind}")

    def set_queue_depth(self, queue_name: str, depth: int) -> None:
        if depth < 0:
            raise ValueError("queue depth must be non-negative")
        with self._lock:
            self._queue_depth[queue_name] = depth
            previous = self._queue_high_watermark.get(queue_name, 0)
            self._queue_high_watermark[queue_name] = max(previous, depth)

    def snapshot(self) -> Mapping[str, Any]:
        """Return an immutable, internally consistent metrics snapshot."""

        with self._lock:
            return MappingProxyType(
                {
                    "frames_received": self._frames_received,
                    "frames_delivered": self._frames_delivered,
                    "frames_dropped": self._frames_dropped,
                    "transport_records_invalid": self._transport_records_invalid,
                    "jpeg_payloads_invalid": self._jpeg_payloads_invalid,
                    "sequence_duplicate": self._sequence_duplicate,
                    "sequence_gap": self._sequence_gap,
                    "sequence_out_of_order": self._sequence_out_of_order,
                    "source_reconnects": self._source_reconnects,
                    "source_errors": self._source_errors,
                    "drop_reasons": MappingProxyType(dict(self._drop_reasons)),
                    "transport_invalid_reasons": MappingProxyType(
                        dict(self._transport_invalid_reasons)
                    ),
                    "jpeg_invalid_reasons": MappingProxyType(
                        dict(self._jpeg_invalid_reasons)
                    ),
                    "queue_depth": MappingProxyType(dict(self._queue_depth)),
                    "queue_high_watermark": MappingProxyType(
                        dict(self._queue_high_watermark)
                    ),
                }
            )
