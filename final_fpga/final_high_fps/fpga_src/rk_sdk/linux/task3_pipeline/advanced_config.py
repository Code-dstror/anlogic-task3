"""Private immutable CFG_EXT schema1 policy; never accepted as public AI args.

Words are little endian, with the same zero-reserved layout as the RTL owner.
Capabilities describe actual connected owners, not the availability of RTL files.
"""
from dataclasses import dataclass, fields
from . import pcie_protocol_v1 as p


def _reject(message, unsupported=False):
    from .config_transaction import ConfigError
    raise ConfigError(message, p.PCIE_CFG_ERROR_UNSUPPORTED if unsupported else p.PCIE_CFG_ERROR_INVALID)


@dataclass(frozen=True)
class AdvancedCapabilities:
    supported: int
    strips: int
    combinations: int = 0


@dataclass(frozen=True)
class AdvancedConfiguration:
    schema: int = 1
    enable: int = 0
    nr_history_reset: int = 0
    nr_motion_guard: int = 0
    nr_static_threshold: int = 0
    nr_weak_threshold: int = 0
    nr_motion_threshold: int = 0
    hdr_ratio: int = 0
    hdr_black_long: int = 0
    hdr_black_short: int = 0
    hdr_motion_base: int = 0
    hdr_motion_shift: int = 0
    hdr_qualification: int = 0
    hdr_max_delta_ns: int = 0
    hdr_max_wait_ns: int = 0
    hdr_max_age_ns: int = 0
    dehaze_config: int = 0
    dehaze_lut_generation: int = 0
    pp_enable: int = 0
    pp_history_reset: int = 0
    pp_camera: int = 0
    strip_count: int = 0
    threshold: int = 0
    gx_min: int = 0
    ratio_shift: int = 0
    direction_sign: int = 0
    min_paired_strips: int = 0
    min_count: int = 0
    morph_mode: int = 0
    min_curvature: int = 0
    strip_y_begin: tuple[int, ...] = (0,) * 8
    strip_y_end: tuple[int, ...] = (0,) * 8
    roi_left: tuple[int, ...] = (0,) * 8
    roi_split: tuple[int, ...] = (0,) * 8
    roi_right: tuple[int, ...] = (0,) * 8

    def _packed(self):
        snapshot = 0
        for field in fields(self):
            name = field.name.upper()
            value = getattr(self, field.name)
            width = getattr(p, 'PCIE_CFG_EXT_FIELD_WIDTH_' + name)
            if width == 104:
                if type(value) is not tuple or len(value) != 8 or any(
                        type(lane) is not int or not 0 <= lane < 8192 for lane in value):
                    _reject(f'{field.name} requires eight immutable unsigned 13-bit lanes')
                value = sum(lane << (13 * i) for i, lane in enumerate(value))
            elif type(value) is not int or not 0 <= value < (1 << width):
                _reject(f'{field.name} exceeds unsigned {width}-bit range')
            snapshot |= value << getattr(p, 'PCIE_CFG_EXT_OFFSET_' + name)
        return snapshot

    def words(self):
        snapshot = self._packed()
        return tuple((snapshot >> (32 * i)) & 0xffffffff for i in range(32))

    @classmethod
    def from_words(cls, words):
        if len(words) != 32 or any(type(word) is not int or not 0 <= word <= 0xffffffff for word in words):
            _reject('CFG_EXT requires exactly 32 unsigned words')
        for i, word in enumerate(words):
            if word & ~getattr(p, f'PCIE_CFG_EXT_ALLOWED_WORD_{i:02}'):
                _reject('CFG_EXT reserved bits must be zero')
        snapshot = sum(word << (32 * i) for i, word in enumerate(words))
        values = {}
        for field in fields(cls):
            name = field.name.upper()
            width = getattr(p, 'PCIE_CFG_EXT_FIELD_WIDTH_' + name)
            value = (snapshot >> getattr(p, 'PCIE_CFG_EXT_OFFSET_' + name)) & ((1 << width) - 1)
            values[field.name] = tuple((value >> (13*i)) & 8191 for i in range(8)) if width == 104 else value
        return cls(**values)

    def validate(self, capabilities: AdvancedCapabilities, *, width: int, height: int, camera_present: int):
        self._packed()
        if self.schema != 1:
            _reject('unsupported CFG_EXT schema')
        if self.enable & ~capabilities.supported:
            _reject('requested advanced feature is not connected to the production owner', True)
        nr = bool(self.enable & p.PCIE_CFG_EXT_FEATURE_NR)
        hdr = bool(self.enable & p.PCIE_CFG_EXT_FEATURE_HDR)
        dehaze = bool(self.enable & p.PCIE_CFG_EXT_FEATURE_DEHAZE)
        pyramid = bool(self.enable & p.PCIE_CFG_EXT_FEATURE_F22)
        candidate = bool(self.enable & p.PCIE_CFG_EXT_FEATURE_F23)
        morphology = bool(self.enable & p.PCIE_CFG_EXT_FEATURE_F24)
        refinement = bool(self.enable & p.PCIE_CFG_EXT_FEATURE_F25)
        if nr and hdr and not capabilities.combinations & p.PCIE_CFG_EXT_COMBINATION_HDR_THEN_NR:
            _reject('HDR then NR path is not connected in this production profile', True)
        if nr:
            if not 6 <= width <= 1920 or not 6 <= height <= 1080 or width % 6 or height % 6:
                _reject('NR geometry requires complete six-pixel groups')
        elif any((self.nr_history_reset, self.nr_motion_guard, self.nr_static_threshold, self.nr_weak_threshold, self.nr_motion_threshold)):
            _reject('disabled NR fields must be zero')
        if hdr:
            if width < 8 or width % 4 or height < 3 or not 1 <= self.hdr_ratio <= 4 or self.hdr_qualification != p.PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED:
                _reject('HDR geometry, ratio or required qualification policy invalid')
        elif any(getattr(self, field.name) for field in fields(self) if field.name.startswith('hdr_')):
            _reject('disabled HDR fields must be zero')
        if dehaze:
            config = self.dehaze_config
            tmin = (config >> 49) & 511
            if (not 6 <= width <= 1920 or not 6 <= height <= 1080 or width % 6 or height % 6
                    or not config >> 66 or not 128 <= tmin <= 256 or (config >> 41) & 255 > 32
                    or (config >> 32) & 511 > 64 or (config >> 24) & 255 > 128
                    or (config >> 16) & 255 > 128 or (config >> 8) & 255 < 128
                    or config & 255 > 64 or not self.dehaze_lut_generation):
                _reject('dehaze configuration or actual LUT generation invalid')
        elif self.dehaze_config or self.dehaze_lut_generation:
            _reject('disabled dehaze fields must be zero')
        if (candidate or morphology or refinement) and not pyramid:
            _reject('F23/F24/F25 require F22')
        advanced_fields = tuple(f for f in fields(self) if getattr(p, 'PCIE_CFG_EXT_OFFSET_' + f.name.upper()) >= 384)
        if not pyramid:
            if any(any(getattr(self, f.name)) if type(getattr(self, f.name)) is tuple else getattr(self, f.name)
                   for f in advanced_fields):
                _reject('disabled pyramid fields must be zero')
            return
        if (not self.pp_enable & 2 or not 4 <= width <= 3840 or width % 4 or not 1 <= height <= 2160
                or self.threshold > 2040 or not 1 <= capabilities.strips <= 8
                or self.strip_count != capabilities.strips or not camera_present & (1 << self.pp_camera)):
            _reject('F22 native Gaussian, geometry, strips or camera invalid')
        if candidate:
            if self.gx_min > 1020 or self.direction_sign == 3 or not self.min_count or not 1 <= self.min_paired_strips <= capabilities.strips:
                _reject('F23 threshold/count/direction invalid')
        elif any((self.gx_min, self.ratio_shift, self.direction_sign, self.min_paired_strips, self.min_count,
                  *self.strip_y_begin, *self.strip_y_end, *self.roi_left, *self.roi_split, *self.roi_right)):
            _reject('disabled F23 fields must be zero')
        for i in range(8):
            if candidate and i < capabilities.strips:
                if (not self.strip_y_begin[i] < self.strip_y_end[i] <= (height+3)//4
                        or not self.roi_left[i] < self.roi_split[i] < self.roi_right[i] <= (width+3)//4
                        or i and (self.strip_y_begin[i] != self.strip_y_end[i-1]
                                  or self.roi_left[i] > self.roi_left[i-1] or self.roi_right[i] < self.roi_right[i-1])):
                    _reject('F23 ROI/strip geometry invalid')
            elif any(vector[i] for vector in (self.strip_y_begin, self.strip_y_end, self.roi_left, self.roi_split, self.roi_right)):
                _reject('unused ROI lanes must be zero')
        if self.morph_mode > 4 or not morphology and self.morph_mode:
            _reject('F24 mode invalid or disabled')
        if refinement:
            if not 1 <= self.min_curvature <= 4080:
                _reject('F25 curvature invalid')
        elif self.min_curvature:
            _reject('disabled F25 curvature must be zero')
