"""Immutable schema2 policy on the existing CFG_EXT transaction, not a new bank.

Mode/enable capabilities must be read from the selected real hardware profile.
No defaults imply HDR, continuous LZ or color luminance Gaussian support.
"""
from dataclasses import dataclass, fields
from . import pcie_protocol_v1 as p


def _reject(message, unsupported=False):
    from .config_transaction import ConfigError
    raise ConfigError(message, p.PCIE_CFG_ERROR_UNSUPPORTED if unsupported else p.PCIE_CFG_ERROR_INVALID)


@dataclass(frozen=True)
class MonoCapabilities:
    modes: int = 0
    enables: int = 0

    def validate(self):
        if type(self.modes) is not int or self.modes & ~7 or self.modes < 0:
            _reject('invalid schema2 mode capability mask')
        if type(self.enables) is not int or self.enables & ~63 or self.enables < 0:
            _reject('invalid schema2 processing capability mask')


@dataclass(frozen=True)
class MonoConfiguration:
    schema: int = 2
    product_mode: int = p.PCIE_CFG_V2_MODES_MONO_SDR
    processing_enables: int = 0
    hdr_ratio: int = 0
    hdr_black_long: int = 0
    hdr_black_short: int = 0
    hdr_motion_base: int = 0
    hdr_motion_shift: int = 0
    hdr_qualification: int = 0
    hdr_max_delta_ns: int = 0
    hdr_max_wait_ns: int = 0
    hdr_max_age_ns: int = 0
    dehaze_lut_generation: int = 0

    def words(self):
        snapshot = 0
        for field in fields(self):
            value = getattr(self, field.name)
            width = getattr(p, 'PCIE_CFG_V2_FIELD_WIDTH_' + field.name.upper())
            if type(value) is not int or not 0 <= value < (1 << width):
                _reject(field.name + ' exceeds schema2 field width')
            snapshot |= value << getattr(p, 'PCIE_CFG_V2_OFFSET_' + field.name.upper())
        return tuple((snapshot >> (i * 32)) & 0xffffffff for i in range(32))

    @classmethod
    def from_words(cls, words):
        if len(words) != 32 or any(type(v) is not int or not 0 <= v <= 0xffffffff for v in words):
            _reject('schema2 requires exactly 32 unsigned words')
        for index, word in enumerate(words):
            if word & ~getattr(p, f'PCIE_CFG_V2_ALLOWED_WORD_{index:02}'):
                _reject('schema2 reserved bits must be zero')
        snapshot = sum(word << (32 * i) for i, word in enumerate(words))
        values = {f.name:(snapshot >> getattr(p, 'PCIE_CFG_V2_OFFSET_' + f.name.upper())) &
                  ((1 << getattr(p, 'PCIE_CFG_V2_FIELD_WIDTH_' + f.name.upper())) - 1) for f in fields(cls)}
        return cls(**values)

    def validate(self, capabilities: MonoCapabilities, *, width: int, height: int, camera_present: int):
        self.words()
        capabilities.validate()
        if self.schema != p.PCIE_CFG_V2_SCHEMA:
            _reject('unknown schema2 payload version')
        if self.product_mode == p.PCIE_CFG_V2_MODES_HDR_LZ_CONFLICT:
            _reject('HDR and LZ are mutually exclusive')
        if (self.processing_enables & p.PCIE_CFG_V2_ENABLES_LANE
                and not self.processing_enables & p.PCIE_CFG_V2_ENABLES_MULTISCALE):
            _reject('lane requires independent multiscale enable')
        if (width, height) != (p.PCIE_CFG_V2_WIDTH, p.PCIE_CFG_V2_HEIGHT) or camera_present not in (1, 3):
            _reject('unsupported geometry or physical camera set', True)
        if camera_present == 3:
            dual_enables = (p.PCIE_CFG_V2_ENABLES_GRAY | p.PCIE_CFG_V2_ENABLES_DEHAZE | p.PCIE_CFG_V2_ENABLES_GAUSSIAN_IMAGE
                            | p.PCIE_CFG_V2_ENABLES_HISTOGRAM)
            if self.product_mode not in (p.PCIE_CFG_V2_MODES_MONO_SDR, p.PCIE_CFG_V2_MODES_MONO_HDR) or self.processing_enables & ~dual_enables:
                _reject('unsupported dual-camera combination', True)
        if (not capabilities.modes & (1 << self.product_mode)
                or self.processing_enables & ~capabilities.enables):
            _reject('schema2 mode/processing owner is not connected in this profile', True)
        if self.product_mode == p.PCIE_CFG_V2_MODES_MONO_HDR:
            if not 1 <= self.hdr_ratio <= 4 or self.hdr_qualification != p.PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED:
                _reject('HDR policy requires valid ratio and complete qualification mask')
        elif any(getattr(self, f.name) for f in fields(self) if f.name.startswith('hdr_')):
            _reject('disabled HDR policy fields must be zero')
        if self.processing_enables & p.PCIE_CFG_V2_ENABLES_DEHAZE:
            if self.dehaze_lut_generation not in (0, 1):
                _reject('integrated dehaze accepts generation 0 (auto) or 1 (built-in)')
        elif self.dehaze_lut_generation:
            _reject('disabled dehaze requires zero LUT generation')
