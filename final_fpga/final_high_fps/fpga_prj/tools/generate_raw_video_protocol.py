"""Generate only the additive RAW constants; keep every legacy wire constant intact."""
from pathlib import Path
import argparse,json
ROOT=Path(__file__).resolve().parents[2]

def outputs():
    protocol=json.loads((ROOT/'fpga_docs/pcie_protocol_v1.json').read_text(encoding='utf8'))
    raw=protocol['raw_video']
    expected={'magic':0x57415241,'version':1,'header_bytes':64,'payload_max_bytes':16777216,
              'format_raw10':1,'flag_timestamp_valid':1,'request_product':0xfa8,'active_product':0xfac,
              'product_jpeg':0,'product_raw':1}
    for name,value in expected.items():
        if raw[name]!=value:raise ValueError('RAW v1 constant changed: '+name)
    fields=raw['fields']
    covered=[]
    for f in fields:covered.extend(range(f['offset'],f['offset']+f['bytes']))
    if sorted(covered)!=list(range(64)):raise ValueError('RAW header must cover exactly 64 bytes')
    values={key.upper():raw[key] for key in expected}
    vh='// Generated from this project docs/pcie_protocol_v1.json (raw_video only).\n'
    vh+='`ifndef RAW_VIDEO_V1_VH\n`define RAW_VIDEO_V1_VH\n'
    vh+=''.join(f"`define PCIE_RAW_VIDEO_{k} 32'd{v}\n" for k,v in values.items())
    vh+='`endif\n'
    py='# Generated from this project docs/pcie_protocol_v1.json (raw_video only).\n'
    py+=''.join(f'PCIE_RAW_VIDEO_{k} = {v}\n' for k,v in values.items())
    return {ROOT/'fpga_src/rtl/include/00_rtl/raw_video_v1.vh':vh,ROOT/'fpga_src/rk_sdk/raw_video_constants.py':py}

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--check',action='store_true');args=ap.parse_args()
    for path,body in outputs().items():
        if args.check:
            if path.read_text(encoding='utf8')!=body:raise ValueError('stale generated file '+str(path))
        else:path.write_text(body,encoding='utf8',newline='\n')
    print('RAW_VIDEO_PROTOCOL_CHECKED' if args.check else 'RAW_VIDEO_PROTOCOL_GENERATED')
