"""Shared, hardware-agnostic data types for the user-space pipeline.

These types intentionally do not describe PCIe wire records, BAR registers,
slot ownership, device names, or model-specific tensor layouts.  Such details
must be handled by source or adapter implementations after their contracts are
confirmed.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from math import floor, gcd, isfinite
from numbers import Integral, Real
from sys import maxsize
from threading import Lock
from types import MappingProxyType
from typing import Any, Mapping

import numpy as np


# Shared model/preprocessing contract, independent from any PCIe ABI limit.
PREPROCESS_MAX_IMAGE_DIMENSION = 0xFFFF

# Configured IMX415 camera-pipeline bounds. These constrain preprocessing
# allocation, unlike PREPROCESS_MAX_IMAGE_DIMENSION, which is only a field
# representation range. Packed RGB24/BGR24 at 3840x2160 is 24,883,200 bytes;
# the remaining 256 bytes per row are a safety budget, not a hardware stride
# guarantee.
PREPROCESS_MAX_INPUT_WIDTH = 3840
PREPROCESS_MAX_INPUT_HEIGHT = 2160
PREPROCESS_MAX_INPUT_PIXELS = 8_294_400
PREPROCESS_MAX_ROW_PADDING_BYTES = 256
PREPROCESS_MAX_INPUT_BYTES = 25_436_160

# Do not use ``isinstance(value, np.integer)`` at the resource boundary: a
# caller-controlled NumPy scalar subclass may override instance attributes or
# conversions.  These exact built-in scalar classes are the supported set.
_EXACT_NUMPY_RESOURCE_INTEGER_TYPES = tuple(
    np.dtype(name).type
    for name in ("int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64")
)


class ResizeRoundingStrategy(str, Enum):
    """Stable resize-dimension rounding rules for preprocessing geometry."""

    HALF_UP = "half_up"
    TRUNCATE_TOWARD_ZERO = "truncate_toward_zero"


class PreprocessProfile(str, Enum):
    """Named preprocessing profiles with explicitly versioned geometry."""

    RK3576_YOLOV5S_RELU_PCIE_V1 = "rk3576_yolov5s_relu_pcie_v1"


def _require_positive_integer(value: object, name: str) -> int:
    """Return a positive integer while rejecting bool and lossy coercions."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    value = int(value)
    if value <= 0:
        raise ValueError(f"{name} must be positive")
    return value


def _require_preprocess_image_dimension(value: object, name: str) -> int:
    """Normalize one bounded preprocessing image dimension to an exact int."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, (Integral, np.integer)):
        raise TypeError(f"{name} must be an integer")
    normalized = int(value)
    if not 1 <= normalized <= PREPROCESS_MAX_IMAGE_DIMENSION:
        raise ValueError(
            f"{name} must be between 1 and {PREPROCESS_MAX_IMAGE_DIMENSION}"
        )
    return normalized


def _require_non_negative_integer(value: object, name: str) -> int:
    """Return a non-negative integer while rejecting bool and lossy coercions."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    value = int(value)
    if value < 0:
        raise ValueError(f"{name} must be non-negative")
    return value


def _require_exact_resource_integer(value: object, name: str, *, positive: bool) -> int:
    """Normalize only trusted Python/NumPy integer scalars for resource checks."""
    value_type = type(value)
    if value_type is int:
        normalized = value
    elif any(value_type is allowed_type for allowed_type in _EXACT_NUMPY_RESOURCE_INTEGER_TYPES):
        # ``value_type`` is a trusted exact built-in class, so invoking its
        # class-level conversion cannot dispatch through a subclass instance.
        normalized = value_type.__int__(value)
    else:
        raise TypeError(f"{name} must be an exact Python or NumPy integer")
    if positive and normalized <= 0:
        raise ValueError(f"{name} must be positive")
    if not positive and normalized < 0:
        raise ValueError(f"{name} must be non-negative")
    return normalized


def validate_preprocess_input_resources(
    width: object,
    height: object,
    row_stride: object,
    buffer_nbytes: object,
) -> None:
    """Validate a bounded BGR24/RGB24 layout without inspecting its pixels.

    3840x2160 is the configured IMX415 camera-pipeline maximum.  The byte
    budget covers packed RGB24/BGR24 plus at most 256 extra bytes per row; it
    is a defensive allocation budget, not a statement about hardware stride.
    This pure helper neither creates buffers/views/arrays nor imports OpenCV.
    """
    normalized_width = _require_exact_resource_integer(width, "width", positive=True)
    normalized_height = _require_exact_resource_integer(height, "height", positive=True)
    if normalized_width > PREPROCESS_MAX_INPUT_WIDTH:
        raise ValueError("width exceeds PREPROCESS_MAX_INPUT_WIDTH")
    if normalized_height > PREPROCESS_MAX_INPUT_HEIGHT:
        raise ValueError("height exceeds PREPROCESS_MAX_INPUT_HEIGHT")
    if normalized_width * normalized_height > PREPROCESS_MAX_INPUT_PIXELS:
        raise ValueError("width * height exceeds PREPROCESS_MAX_INPUT_PIXELS")

    normalized_row_stride = _require_exact_resource_integer(
        row_stride, "row_stride", positive=True
    )
    packed_row_bytes = normalized_width * 3
    if normalized_row_stride < packed_row_bytes:
        raise ValueError("row_stride must be at least packed_row_bytes")
    if normalized_row_stride > packed_row_bytes + PREPROCESS_MAX_ROW_PADDING_BYTES:
        raise ValueError("row_stride exceeds packed_row_bytes + PREPROCESS_MAX_ROW_PADDING_BYTES")
    if normalized_row_stride * normalized_height > PREPROCESS_MAX_INPUT_BYTES:
        raise ValueError("row_stride * height exceeds PREPROCESS_MAX_INPUT_BYTES")

    normalized_buffer_nbytes = _require_exact_resource_integer(
        buffer_nbytes, "buffer_nbytes", positive=False
    )
    if normalized_buffer_nbytes > PREPROCESS_MAX_INPUT_BYTES:
        raise ValueError("buffer_nbytes exceeds PREPROCESS_MAX_INPUT_BYTES")
    minimum_required = (
        (normalized_height - 1) * normalized_row_stride + packed_row_bytes
    )
    if normalized_buffer_nbytes < minimum_required:
        raise ValueError("buffer_nbytes is smaller than minimum_required")


def _round_scaled_dimension(original_dimension: int, scale: float, axis: str) -> int:
    """Safely round one scaled size to nearest integer, with .5 rounded up."""
    error_message = f"scaled {axis} must be finite and roundable"
    try:
        scaled_dimension = original_dimension * scale
    except OverflowError:
        raise ValueError(error_message) from None
    if not isfinite(scaled_dimension):
        raise ValueError(error_message)
    try:
        rounded_input = scaled_dimension + 0.5
    except OverflowError:
        raise ValueError(error_message) from None
    if not isfinite(rounded_input):
        raise ValueError(error_message)
    try:
        return floor(rounded_input)
    except (OverflowError, ValueError):
        raise ValueError(error_message) from None


def _truncate_scaled_dimension(original_dimension: int, scale: float, axis: str) -> int:
    """Safely truncate one positive scaled dimension toward zero."""
    error_message = f"scaled {axis} must be finite and roundable"
    try:
        scaled_dimension = original_dimension * scale
    except OverflowError:
        raise ValueError(error_message) from None
    if not isfinite(scaled_dimension):
        raise ValueError(error_message)
    try:
        return int(scaled_dimension)
    except (OverflowError, ValueError):
        raise ValueError(error_message) from None


def _scaled_dimension(
    original_dimension: int,
    scale: float,
    axis: str,
    strategy: ResizeRoundingStrategy,
) -> int:
    """Derive one size using the transform's validated rounding strategy."""
    if strategy is ResizeRoundingStrategy.HALF_UP:
        return _round_scaled_dimension(original_dimension, scale, axis)
    return _truncate_scaled_dimension(original_dimension, scale, axis)


def _finite_real_as_integer_ratio(value: Real, name: str) -> tuple[int, int]:
    """Return an exact ratio for supported Python or NumPy scalar input only."""
    if isinstance(value, Integral):
        return int(value), 1
    if isinstance(value, np.floating):
        if not bool(np.isfinite(value)):
            raise ValueError(f"{name} must be finite")
        scalar_type = np.dtype(value.dtype).type
        as_integer_ratio = getattr(scalar_type, "as_integer_ratio", None)
        if not callable(as_integer_ratio):
            raise TypeError(f"{name} NumPy dtype lacks exact binary-ratio support")
        # Dispatch through the concrete NumPy scalar dtype, retaining e.g.
        # longdouble precision and avoiding any Python-float conversion.
        numerator, denominator = as_integer_ratio(value)
    elif isinstance(value, float):
        try:
            # Call the built-in implementation directly: a float subclass may
            # replace its instance attribute but cannot change its stored
            # binary64 payload.
            numerator, denominator = float.as_integer_ratio(value)
        except OverflowError:
            raise ValueError(f"{name} must be finite")
    else:
        raise TypeError(f"{name} must be a Python or NumPy real scalar")
    numerator, denominator = int(numerator), int(denominator)
    if denominator <= 0:
        raise ValueError(f"{name} has an invalid exact ratio")
    divisor = gcd(numerator, denominator)
    return numerator // divisor, denominator // divisor


def _compare_integer_ratios(
    left: tuple[int, int], right: tuple[int, int]
) -> int:
    """Compare exact rational values represented by positive-denominator ratios."""
    left_cross = left[0] * right[1]
    right_cross = right[0] * left[1]
    return (left_cross > right_cross) - (left_cross < right_cross)


def _validate_exact_floating_padding_value(value: Real, dtype: np.dtype) -> object:
    """Validate finite range and exact representability before storing a float padding value."""
    value_ratio = _finite_real_as_integer_ratio(value, "padding_value")
    limits = np.finfo(dtype)
    minimum_ratio = _finite_real_as_integer_ratio(limits.min, "dtype minimum")
    maximum_ratio = _finite_real_as_integer_ratio(limits.max, "dtype maximum")
    if (
        _compare_integer_ratios(value_ratio, minimum_ratio) < 0
        or _compare_integer_ratios(value_ratio, maximum_ratio) > 0
    ):
        raise ValueError("padding_value is outside the dtype range")
    try:
        with np.errstate(over="ignore", invalid="ignore"):
            converted = np.asarray(value, dtype=dtype)[()]
    except (OverflowError, TypeError, ValueError) as error:
        raise ValueError("padding_value is outside the dtype range") from error
    converted_ratio = _finite_real_as_integer_ratio(converted, "padding_value")
    if value_ratio != converted_ratio:
        raise ValueError("padding_value must be exactly representable by the dtype")
    return dtype.type(converted).item()


def _normalize_exact_binary64_scale(value: object) -> float:
    """Return a finite scale only when its exact value survives binary64 storage."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Real):
        raise TypeError("scale must be a Python or NumPy real scalar")
    value_ratio = _finite_real_as_integer_ratio(value, "scale")
    minimum_ratio = _finite_real_as_integer_ratio(np.finfo(np.float64).min, "scale minimum")
    maximum_ratio = _finite_real_as_integer_ratio(np.finfo(np.float64).max, "scale maximum")
    if (
        _compare_integer_ratios(value_ratio, minimum_ratio) < 0
        or _compare_integer_ratios(value_ratio, maximum_ratio) > 0
    ):
        raise ValueError("scale must be finite and exactly representable as a Python float")
    if isinstance(value, float) and not isinstance(value, np.floating):
        # ``np.asarray`` and ``float(value)`` dispatch a subclass's
        # ``__float__``. Calling these built-in descriptors directly instead
        # reconstructs an exact base float from the already-validated payload.
        return float.fromhex(float.hex(value))
    try:
        with np.errstate(over="ignore", invalid="ignore"):
            converted = np.asarray(value, dtype=np.float64)[()]
    except (OverflowError, TypeError, ValueError):
        raise ValueError("scale must be finite and exactly representable as a Python float") from None
    converted_ratio = _finite_real_as_integer_ratio(converted, "scale")
    if value_ratio != converted_ratio:
        raise ValueError("scale must be exactly representable as a Python float")
    return float(converted)


def _normalize_contract_string(value: object, name: str) -> str:
    """Copy a string subclass into an exact base string before validation."""
    if not isinstance(value, str):
        raise ValueError(f"{name} must be a string")
    normalized = str.__str__(value)
    return normalized if type(normalized) is str else str.__new__(str, normalized)


def _normalize_contract_enum(
    value: object,
    enum_type: type[Enum],
    name: str,
) -> Enum:
    """Accept only an exact enum or exact base-string representation.

    Contract enums must not retain string subclasses, other enums, or values
    whose equality/hash behaviour can change validation semantics.
    """
    if type(value) is enum_type:
        return value
    if type(value) is not str:
        raise TypeError(f"{name} must be an exact {enum_type.__name__} or string value")
    try:
        return enum_type(value)
    except ValueError:
        raise ValueError(f"{name} has an unsupported value") from None


def _normalize_tensor_shape(shape: object) -> tuple[int, ...]:
    """Validate the non-empty dimensions used by an immutable tensor."""
    try:
        dimensions = tuple(shape)  # type: ignore[arg-type]
    except TypeError as error:
        raise TypeError("shape must be a sequence of positive integers") from error
    normalized: list[int] = []
    for index, dimension in enumerate(dimensions):
        normalized.append(_require_positive_integer(dimension, f"shape[{index}]"))
    return tuple(normalized)


def _derive_c_tensor_layout(shape: tuple[int, ...], itemsize: int) -> tuple[tuple[int, ...], int]:
    """Derive C strides and exact bytes without allocating a tensor buffer."""
    if itemsize <= 0:
        raise ValueError("dtype must have a positive itemsize")

    stride = itemsize
    strides = [0] * len(shape)
    for index in range(len(shape) - 1, -1, -1):
        strides[index] = stride
        if shape[index] > maxsize // stride:
            raise ValueError("tensor shape is too large")
        stride *= shape[index]
    return tuple(strides), stride


def _normalize_c_strides(strides: object, expected: tuple[int, ...]) -> tuple[int, ...]:
    """Accept only the exact dense C-contiguous strides for a tensor."""
    try:
        supplied = tuple(strides)  # type: ignore[arg-type]
    except TypeError as error:
        raise TypeError("strides must be a sequence of integers") from error
    if len(supplied) != len(expected):
        raise ValueError("strides must have one entry per shape dimension")
    normalized: list[int] = []
    for index, stride in enumerate(supplied):
        if isinstance(stride, (bool, np.bool_)) or not isinstance(stride, Integral):
            raise TypeError(f"strides[{index}] must be an integer")
        normalized.append(int(stride))
    normalized_strides = tuple(normalized)
    if normalized_strides != expected:
        raise ValueError("strides must be the dense C-contiguous strides for shape and dtype")
    return normalized_strides


def _validate_immutable_tensor_dtype(dtype: object) -> np.dtype:
    """Return a non-object, non-subarray dtype with stable tensor metadata."""
    normalized_dtype = np.dtype(dtype)
    if normalized_dtype.subdtype is not None:
        raise TypeError("top-level subarray dtypes are not supported by ImmutableTensor")
    if normalized_dtype.hasobject:
        raise TypeError("object-containing dtypes are not supported by ImmutableTensor")
    return normalized_dtype


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
        dtype = _validate_immutable_tensor_dtype(dtype)
        normalized_shape = _normalize_tensor_shape(shape)
        expected_strides, expected_nbytes = _derive_c_tensor_layout(
            normalized_shape, dtype.itemsize
        )
        normalized_strides = _normalize_c_strides(strides, expected_strides)
        if type(backing) is bytes:
            frozen_backing = backing
        else:
            try:
                frozen_backing = memoryview(backing).tobytes()
            except TypeError as error:
                raise TypeError("backing must be a bytes-like buffer") from error
        if len(frozen_backing) != expected_nbytes:
            raise ValueError("backing length must exactly match the tensor layout")
        object.__setattr__(self, "_backing", frozen_backing)
        object.__setattr__(self, "_shape", normalized_shape)
        object.__setattr__(self, "_dtype", dtype)
        object.__setattr__(self, "_strides", normalized_strides)
        object.__setattr__(self, "_flags", _ImmutableTensorFlags())

    def __setattr__(self, name: str, value: object) -> None:
        raise AttributeError("ImmutableTensor header cannot be changed")

    @staticmethod
    def from_array(source: np.ndarray) -> "ImmutableTensor":
        """Copy ``source`` into an exact, C-contiguous ImmutableTensor.

        This deliberately constructs the base type even when invoked through
        an ``ImmutableTensor`` subclass.  A subclass can override conversion
        or metadata accessors and therefore cannot inherit this API's
        immutable-wrapper guarantee.
        """
        if not isinstance(source, np.ndarray):
            raise TypeError("source must be a NumPy array")
        contiguous = np.array(source, copy=True, order="C")
        # Validate the newly materialized base ndarray immediately before
        # serialization. An ndarray subclass can override metadata accessors,
        # so checking the caller object alone cannot guard ``tobytes()``.
        _validate_immutable_tensor_dtype(contiguous.dtype)
        backing = contiguous.tobytes(order="C")
        return ImmutableTensor(backing, contiguous.shape, contiguous.dtype, contiguous.strides)

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
        for name in ("width", "height"):
            object.__setattr__(
                self, name, _require_preprocess_image_dimension(getattr(self, name), name)
            )
        for name in ("batch_size", "channels"):
            object.__setattr__(self, name, _require_positive_integer(getattr(self, name), name))
        if self.batch_size != 1:
            raise ValueError("only batch_size=1 is supported by the ModelInput contract")
        if not isinstance(self.color_format, str):
            raise ValueError("color_format must be a non-empty string")
        color_format = _normalize_contract_string(self.color_format, "color_format")
        if not color_format.strip():
            raise ValueError("color_format must be a non-empty string")
        if not isinstance(self.layout, str):
            raise ValueError("layout must be NHWC or NCHW")
        layout = _normalize_contract_string(self.layout, "layout")
        if layout not in {"NHWC", "NCHW"}:
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
            padding_value = _validate_exact_floating_padding_value(self.padding_value, dtype)
        object.__setattr__(self, "color_format", color_format)
        object.__setattr__(self, "layout", layout)
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
    algorithms remain outside this shared-contract change.  ``scale`` is
    stored as an exact Python binary64 float, so callers must supply a
    supported Python or NumPy scalar whose exact value is representable there.
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
    rounding_strategy: ResizeRoundingStrategy | str = ResizeRoundingStrategy.HALF_UP
    profile: PreprocessProfile | str | None = None

    def __post_init__(self) -> None:
        for name in ("source_width", "source_height", "model_width", "model_height"):
            object.__setattr__(
                self, name, _require_preprocess_image_dimension(getattr(self, name), name)
            )
        for name in ("pad_left", "pad_top", "pad_right", "pad_bottom"):
            object.__setattr__(self, name, _require_non_negative_integer(getattr(self, name), name))
        scale = _normalize_exact_binary64_scale(self.scale)
        if scale <= 0:
            raise ValueError("scale must be finite and positive")
        object.__setattr__(self, "scale", scale)

        strategy = _normalize_contract_enum(
            self.rounding_strategy, ResizeRoundingStrategy, "rounding_strategy"
        )
        profile = (
            None
            if self.profile is None
            else _normalize_contract_enum(self.profile, PreprocessProfile, "profile")
        )
        if (
            profile is PreprocessProfile.RK3576_YOLOV5S_RELU_PCIE_V1
            and strategy is not ResizeRoundingStrategy.TRUNCATE_TOWARD_ZERO
        ):
            raise ValueError(
                "RK3576_YOLOV5S_RELU_PCIE_V1 requires truncate_toward_zero rounding_strategy"
            )
        object.__setattr__(self, "rounding_strategy", strategy)
        object.__setattr__(self, "profile", profile)

        scaled_width = _scaled_dimension(self.source_width, scale, "width", strategy)
        scaled_height = _scaled_dimension(self.source_height, scale, "height", strategy)
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
        """Width after applying this transform's documented rounding strategy."""
        return _scaled_dimension(self.source_width, self.scale, "width", self.rounding_strategy)

    @property
    def scaled_height(self) -> int:
        """Height after applying this transform's documented rounding strategy."""
        return _scaled_dimension(self.source_height, self.scale, "height", self.rounding_strategy)


@dataclass(frozen=True, slots=True)
class ModelInput:
    """Owned, immutable tensor plus its complete source-frame association.

    This object itself must be an exact :class:`ModelInput`; subclasses are
    rejected before any input member is read. An ndarray input, including an
    ndarray subclass, is copied into immutable ``bytes`` at this boundary.
    Only an exact :class:`ImmutableTensor` may be shared directly; this
    instance holds a strong reference for the complete synchronous inference
    call. ImmutableTensor subclasses are rejected before their overridable
    members are read, because they cannot inherit the base class's immutability
    guarantee. Neither accepted path exposes a mutable ndarray header.
    Metadata, transform, and specification inputs must be their exact base
    types; subclasses are rejected before their overridable members are read.
    The specification must be an exact
    :class:`ModelInputSpec`; subclasses are rejected before their overridable
    shape or dimension members are read.
    """
    metadata: "FrameMetadata"
    data: np.ndarray | ImmutableTensor
    spec: ModelInputSpec
    transform: PreprocessTransform

    def __init_subclass__(cls, **kwargs: object) -> None:
        """Seal this inference-boundary value from validation-bypassing subclasses."""
        raise TypeError("ModelInput subclasses are not supported")

    def __post_init__(self) -> None:
        if type(self) is not ModelInput:
            raise TypeError("ModelInput must be an exact ModelInput")
        if type(self.metadata) is not FrameMetadata:
            raise TypeError("metadata must be an exact FrameMetadata")
        if type(self.spec) is not ModelInputSpec:
            raise TypeError("spec must be an exact ModelInputSpec")
        if type(self.transform) is not PreprocessTransform:
            raise TypeError("transform must be an exact PreprocessTransform")
        data_type = type(self.data)
        if data_type is ImmutableTensor:
            tensor = self.data
        elif issubclass(data_type, ImmutableTensor):
            raise TypeError("ImmutableTensor subclasses are not supported by ModelInput")
        elif isinstance(self.data, np.ndarray):
            tensor = ImmutableTensor.from_array(self.data)
        else:
            raise TypeError("data must be a NumPy array or an exact ImmutableTensor")
        if self.spec.batch_size != 1:
            raise ValueError("ModelInput supports only batch_size=1")
        if self.transform.model_width != self.spec.width or self.transform.model_height != self.spec.height:
            raise ValueError("transform target dimensions must match spec")
        if tensor.shape != self.spec.shape:
            raise ValueError("data shape must match spec.shape")
        if tensor.dtype != self.spec.dtype:
            raise ValueError("data dtype must match spec.dtype")
        object.__setattr__(self, "data", tensor)


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

    ``preprocess_transform`` accepts ``None``, an exact validated
    :class:`PreprocessTransform`, an empty mapping (normalized to ``None``),
    or a mapping containing exactly the fields of ``PreprocessTransform``.
    Mapping inputs are snapshotted before validation. The stored value is
    always ``None`` or an exact validated structured transform.
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
_PREPROCESS_TRANSFORM_ROUNDING_FIELD = "rounding_strategy"
_PREPROCESS_TRANSFORM_PROFILE_FIELD = "profile"
_PREPROCESS_TRANSFORM_V2_FIELDS = (
    *_PREPROCESS_TRANSFORM_FIELDS,
    _PREPROCESS_TRANSFORM_ROUNDING_FIELD,
    _PREPROCESS_TRANSFORM_PROFILE_FIELD,
)


def _normalize_preprocess_transform(
    value: PreprocessTransform | Mapping[str, Any] | None,
) -> PreprocessTransform | None:
    """Normalize a transform without retaining mutable subclass or mapping state."""
    if value is None:
        return value
    if type(value) is PreprocessTransform:
        return value
    if isinstance(value, PreprocessTransform):
        raise TypeError("PreprocessTransform subclasses are not supported by DetectionResult")
    if not isinstance(value, Mapping):
        raise TypeError("preprocess_transform must be None, PreprocessTransform, or a mapping")
    expected_fields = set(_PREPROCESS_TRANSFORM_V2_FIELDS)
    normalized_keys: list[tuple[object, str]] = []
    seen_fields: set[str] = set()
    for raw_key in value:
        # Phase one never reads a mapping value. A str subclass can collide
        # with a legal key through hostile hash/equality overrides and would
        # otherwise be silently discarded by ``dict(value)``.
        if not isinstance(raw_key, str):
            raise ValueError("preprocess_transform contains a non-string field")
        key = _normalize_contract_string(raw_key, "preprocess_transform field")
        if key not in expected_fields:
            raise ValueError("preprocess_transform contains unknown fields")
        if key in seen_fields:
            raise ValueError("preprocess_transform contains duplicate fields")
        seen_fields.add(key)
        normalized_keys.append((raw_key, key))
    if not normalized_keys:
        return None

    missing_fields = set(_PREPROCESS_TRANSFORM_FIELDS) - seen_fields
    if missing_fields:
        raise ValueError(f"preprocess_transform is missing fields: {sorted(missing_fields)!r}")
    if (
        _PREPROCESS_TRANSFORM_PROFILE_FIELD in seen_fields
        and _PREPROCESS_TRANSFORM_ROUNDING_FIELD not in seen_fields
    ):
        raise ValueError("preprocess_transform with profile requires rounding_strategy")

    # Phase two starts only after every raw key has passed phase-one checks.
    # The snapshot is indexed by exact base strings and never retains key state.
    mapping: dict[str, Any] = {}
    for raw_key, key in normalized_keys:
        mapping[key] = value[raw_key]

    transform_values = {name: mapping[name] for name in _PREPROCESS_TRANSFORM_FIELDS}
    if _PREPROCESS_TRANSFORM_ROUNDING_FIELD in mapping:
        transform_values[_PREPROCESS_TRANSFORM_ROUNDING_FIELD] = mapping[
            _PREPROCESS_TRANSFORM_ROUNDING_FIELD
        ]
    if _PREPROCESS_TRANSFORM_PROFILE_FIELD in mapping:
        transform_values[_PREPROCESS_TRANSFORM_PROFILE_FIELD] = mapping[
            _PREPROCESS_TRANSFORM_PROFILE_FIELD
        ]
    return PreprocessTransform(**transform_values)


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
