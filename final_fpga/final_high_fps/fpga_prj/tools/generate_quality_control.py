"""Generate this candidate's additive CFG1/schema2 quality controls."""

import argparse
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / 'fpga_docs/quality_control_v1.json'
VERILOG = PROJECT / 'fpga_src/rtl/include/00_rtl/quality_control_v1.vh'
PYTHON = PROJECT / 'fpga_src/rk_sdk/linux/task3_pipeline/quality_control_v1.py'


def outputs():
    spec = json.loads(SOURCE.read_text(encoding='utf-8'))
    inherited = (SOURCE.parent / spec['extends']).resolve()
    base = json.loads(inherited.read_text(encoding='utf-8'))
    candidate = json.loads((SOURCE.parent / 'pcie_protocol_v1.json').read_text(encoding='utf-8'))
    schema = base['advanced_config_v2']
    cfg = base['config_transaction']
    feature = spec['feature_bit']
    if (schema != candidate['advanced_config_v2'] or cfg != candidate['config_transaction']
            or schema['schema'] != spec['schema'] or schema['word_count'] != 32
            or spec['feature_register'] != 'CFG_FEATURES' or feature in cfg['features'].values()
            or not 0 <= feature < 32):
        raise ValueError('quality control requires an unused feature bit on inherited CFG1/schema2')
    fields = spec['fields']
    masks = {1: 0, 12: 0}
    occupied = sum(((1 << f['width']) - 1) << f['offset'] for f in schema['fields'])
    names = set()
    constants = {'PCIE_CFG_V2_QUALITY_VERSION_V1': spec['version']}
    for field in fields:
        name, offset, width = field['name'], field['offset'], field['width']
        word, lsb = divmod(offset, 32)
        if (name in names or word not in masks or not 0 < width <= 32 - lsb
                or (((1 << width) - 1) << offset) & occupied):
            raise ValueError('quality control field overlaps inherited CFG or crosses word: ' + name)
        names.add(name)
        masks[word] |= ((1 << width) - 1) << lsb
        occupied |= ((1 << width) - 1) << offset
        constants[f'PCIE_CFG_V2_OFFSET_{name}'] = offset
        constants[f'PCIE_CFG_V2_FIELD_WIDTH_{name}'] = width
    for word, mask in masks.items():
        constants[f'PCIE_CFG_V2_QUALITY_ALLOWED_WORD_{word:02}'] = mask
    for name, value in spec['isp_wb'].items():
        constants[f'PCIE_CFG_V2_QUALITY_WB_{name.upper()}'] = value
    for control in ('tone', 'fusion'):
        for name, value in spec[f'{control}_presets'].items():
            constants[f'PCIE_CFG_V2_QUALITY_{control.upper()}_{name}'] = value
    feature_name = 'PCIE_CFG_FEATURE_' + spec['feature_name']
    comment = 'Generated from this project docs/quality_control_v1.json.'
    header = [f'// {comment}', '`ifndef QUALITY_CONTROL_V1_VH', '`define QUALITY_CONTROL_V1_VH',
              f'`define {feature_name} {feature}']
    python = [f'# {comment}', f'{feature_name} = {1 << feature}',
              f'QUALITY_FIELDS = {tuple(field["name"].lower() for field in fields)!r}']
    for name, value in constants.items():
        # Sized masks keep unary complement and AND in 32-bit word width.
        literal = f"32'h{value:08x}" if '_ALLOWED_WORD_' in name else str(value)
        header.append(f'`define {name} {literal}')
        python.append(f'{name} = {value}')
    return {VERILOG: '\n'.join([*header, '`endif', '']), PYTHON: '\n'.join([*python, ''])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for path, body in outputs().items():
        if args.check:
            if path.read_text(encoding='utf-8') != body:
                raise ValueError('stale generated file ' + str(path))
        else:
            path.write_text(body, encoding='utf-8', newline='\n')
    print('QUALITY_CONTROL_PROTOCOL_CHECKED' if args.check else 'QUALITY_CONTROL_PROTOCOL_GENERATED')


if __name__ == '__main__':
    main()
