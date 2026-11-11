"""Source-bound r3 control catalogue; capability CSRs remain authoritative.

This is the selected area's compact codec, not the generic schema1 field-width
contract. A field can exist on the wire while being fixed or disconnected here.
No FPGA exposure, image quality, bandwidth, or board qualification is implied.
"""
from dataclasses import asdict, fields

from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.advanced_config import AdvancedConfiguration
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration


R3_SOURCE = {
    'profile': 'r3',
    'source_commit': '8e2eecfc',
    'manifest': 'src_fpga/stages/r8_stage3/pending/area95_20261016/r3/SOURCE_MANIFEST.json',
    'manifest_sha256': '5be9c0f407cdb9a32b47a237adbe981c62fc4da8ef903dfce831cd0a54874c44',
    'codec': 'src_fpga/stages/r8_stage3/pending/mono_config_v2_20261015/legacy_stage2_config_transport.vh',
    'expected_schema1_supported': 0x3c,
    'expected_schema2_modes': 7,
    'expected_schema2_enables': 0x3f,
    'hdr_source': 'LAB_DIGITAL_SOURCE_SELECT_3',
    'physical_hdr_exposure': 'UNQUALIFIED',
    'board_validation': 'NOT_RUN',
}

BASE_MODES = {name: getattr(p, 'PCIE_CFG_MODE_' + name) for name in
              ('COLOR', 'GRAY', 'GAUSSIAN', 'HISTOGRAM')}
PRODUCT_MODES = {name: getattr(p, 'PCIE_CFG_V2_MODES_' + name) for name in
                 ('MONO_SDR', 'MONO_SDR_LZ', 'MONO_HDR')}
PROCESSING_ENABLES = {name: getattr(p, 'PCIE_CFG_V2_ENABLES_' + name) for name in
                      ('GRAY', 'DEHAZE', 'GAUSSIAN_IMAGE', 'HISTOGRAM', 'MULTISCALE', 'LANE')}
ADVANCED_ENABLES = {name: getattr(p, 'PCIE_CFG_EXT_FEATURE_' + name) for name in
                    ('CFS', 'NR', 'HDR', 'DEHAZE', 'F22', 'F23', 'F24', 'F25')}
BASE_FLAGS = {'ADAPTIVE_QUALITY': p.PCIE_CFG_FLAG_ADAPTIVE_QUALITY}

# Bit-for-bit stage2_unpack_extension values from the selected r3 source.
DEHAZE_PRESET = ((1 << 66) | (192 << 58) | (128 << 49) | (8 << 41) |
                 (16 << 32) | (32 << 24) | (16 << 16) | (200 << 8) | 24)
LANE_PRESET = {
    'pp_enable': 3, 'strip_count': 4, 'threshold': 40, 'gx_min': 1,
    'ratio_shift': 3, 'min_count': 1, 'min_paired_strips': 1,
    'strip_y_begin': (0, 67, 135, 202, 0, 0, 0, 0),
    'strip_y_end': (67, 135, 202, 270, 0, 0, 0, 0),
    'roi_left': (0,) * 8, 'roi_split': (240,) * 4 + (0,) * 4,
    'roi_right': (480,) * 4 + (0,) * 4,
}


def r3_schema1_preset(enable: int, *, dehaze_lut_generation: int = 0,
                      **hdr_fields) -> AdvancedConfiguration:
    """Build a complete preset; callers still supply HDR policy and LUT identity.

    Use schema0/None for an entirely disabled extension. F22/F23 are one fixed
    legacy preset; independent multiscale/lane selection belongs to schema2.
    """
    if type(enable) is not int or not enable or enable & ~0x3c or (enable & 0x30) not in (0, 0x30):
        raise ValueError('r3 schema1 enables require HDR, DEHAZE and/or paired F22+F23')
    allowed = {f.name for f in fields(AdvancedConfiguration) if f.name.startswith('hdr_')}
    if set(hdr_fields) - allowed:
        raise ValueError('unknown HDR policy field')
    values = {'enable': enable, 'dehaze_lut_generation': dehaze_lut_generation, **hdr_fields}
    if enable & p.PCIE_CFG_EXT_FEATURE_DEHAZE:
        values['dehaze_config'] = DEHAZE_PRESET
    if enable & p.PCIE_CFG_EXT_FEATURE_F22:
        values.update(LANE_PRESET)
    return AdvancedConfiguration(**values)


def validate_r3_preset(extension: AdvancedConfiguration) -> None:
    from linux.task3_pipeline.config_transaction import ConfigError
    try:
        expected = r3_schema1_preset(extension.enable,
            dehaze_lut_generation=extension.dehaze_lut_generation,
            **{f.name: getattr(extension, f.name) for f in fields(extension)
               if f.name.startswith('hdr_')})
    except ValueError as exc:
        raise ConfigError(str(exc)) from exc
    if extension != expected:
        raise ConfigError('r3 compact schema1 requires the exact fixed dehaze/lane preset')


def parameter_catalog() -> dict:
    """Return fresh JSON-compatible descriptions, never live capability claims."""
    base = []
    ranges = {'mode': (0, 3), 'quality': (1, 100), 'flags': (0, 1),
              'min_quality': (1, 100), 'frame_budget': (0, p.MAX_PAYLOAD),
              'restart_mcus': (0, 65535)}
    dependencies = {
        'mode': 'schema2 requires COLOR; other modes require SHARED_Y',
        'quality': 'min_quality <= quality; non-75 quality requires DYNAMIC_QUALITY',
        'flags': 'ADAPTIVE_QUALITY requires FRAME_BUDGET capability and nonzero frame_budget',
        'min_quality': '1 <= min_quality <= quality',
        'frame_budget': 'caller byte budget; nonzero requires FRAME_BUDGET capability',
        'restart_mcus': 'nonzero requires RESTART capability; unit is MCU',
    }
    for name, (minimum, maximum) in ranges.items():
        item = dict(path='base.' + name, minimum=minimum, maximum=maximum,
                    wire_bits=32, access='writable', depends_on=dependencies[name])
        if name == 'mode': item['symbols'] = dict(BASE_MODES)
        if name == 'flags': item['symbols'] = dict(BASE_FLAGS)
        base.append(item)
    schemas = {}
    for schema, cls, prefix in ((1, AdvancedConfiguration, 'PCIE_CFG_EXT'),
                                (2, MonoConfiguration, 'PCIE_CFG_V2')):
        rows = []
        preset = asdict(r3_schema1_preset(0x38, dehaze_lut_generation=1))
        for field in fields(cls):
            name = field.name
            bits = getattr(p, prefix + '_FIELD_WIDTH_' + name.upper())
            item = dict(path='extension.' + name, wire_bits=bits, minimum=0,
                        maximum=(1 << (13 if bits == 104 else bits)) - 1,
                        access='writable', depends_on='live advertised capability and complete tuple validation')
            if bits == 104: item['lanes'] = 8
            if name == 'schema':
                item.update(access='fixed', minimum=schema, maximum=schema, value=schema)
            elif name.startswith('hdr_'):
                item['depends_on'] = 'HDR enabled: LAB digital source only; otherwise zero'
                if name == 'hdr_ratio': item.update(minimum=0, maximum=4, enabled_minimum=1)
                if name == 'hdr_qualification':
                    item.update(enabled_value=15, note='policy mask; not physical exposure evidence')
            elif name == 'dehaze_lut_generation':
                item['depends_on'] = 'DEHAZE enabled: exact confirmed nonzero LUT generation; otherwise zero'
            elif schema == 2 and name == 'product_mode':
                item.update(maximum=2, symbols=dict(PRODUCT_MODES),
                            depends_on='live mode mask; HDR/LZ exclusive; transition permit for changes')
            elif schema == 2 and name == 'processing_enables':
                item.update(symbols=dict(PROCESSING_ENABLES),
                            depends_on='live enables mask; LANE requires MULTISCALE')
            elif schema == 1 and name == 'enable':
                item.update(symbols=dict(ADVANCED_ENABLES), source_supported_mask=0x3c,
                            depends_on='F22/F23 paired; lane needs base GAUSSIAN; zero uses schema0')
            elif schema == 1:
                item.update(access='fixed_by_preset', disabled_value=0,
                            enabled_value=preset[name],
                            depends_on='exact stage2 compact preset; no independent tuning')
                if name.startswith('nr_') or name in ('morph_mode', 'min_curvature'):
                    item.update(access='unsupported', value=0,
                                depends_on='NR/F24/F25 not connected in selected r3')
            rows.append(item)
        schemas[str(schema)] = rows
    return {
        'base': base, 'schemas': schemas,
        'compile_time': [
            {'name': 'geometry', 'access': 'read_only', 'value': [1920, 1080]},
            {'name': 'camera_present', 'access': 'read_only', 'value': 1},
            {'name': 'source_select', 'access': 'read_only', 'value': 3},
            {'name': 'strips', 'access': 'read_only', 'value': 4},
            {'name': 'HE_parameters', 'access': 'read_only', 'value': 'fixed config-session owner'},
            {'name': 'F21_parameters', 'access': 'read_only', 'value': 'fixed config-session preset'},
            {'name': 'gaussian_kernel', 'access': 'read_only', 'value': 'compiled RTL kernel'},
            {'name': 'LZ_geometry_format', 'access': 'read_only', 'value': '1920x1080 RAW10'},
            {'name': 'HDR_sensor_recipe', 'access': 'unsupported', 'value': 'not a control in this profile'},
        ],
        'lut': {'entry_count': 257, 'table': 'exact reciprocal_words()',
                'generation_minimum': 1, 'generation_maximum': 0xffffffff,
                'requires': 'this owner confirmed F21-off APPLIED; generation strictly increases'},
    }
