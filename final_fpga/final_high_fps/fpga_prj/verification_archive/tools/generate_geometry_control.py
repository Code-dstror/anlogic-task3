"""Generate additive cold geometry extension constants; legacy ABI is unchanged."""
import argparse,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def outputs():
    d=json.loads((ROOT/'docs/geometry_control_v1.json').read_bytes())
    assert d['registers']=={'REQUEST':0xFBC,'ACTIVE':0xFC0,'CAPABILITIES':0xFC4}
    codes=d['codes']
    assert codes=={'HD':0,'MONO_UHD15':1,'MONO_UHD20':2}
    values={f'PCIE_GEOMETRY_REG_{k}':(12,v) for k,v in d['registers'].items()}
    values.update({f'PCIE_GEOMETRY_CODE_{k}':(2,v) for k,v in codes.items()})
    values['PCIE_GEOMETRY_ABI_VERSION']=(8,d['abi_version'])
    values['PCIE_GEOMETRY_CAPABILITIES']=(32,(d['abi_version']<<8)|sum(1<<code for code in codes.values()))
    for fps in (15,20):
        profile=d[f'sensor_profile_uhd{fps}']
        # The cold mailbox carries the geometry code in the low two profile bits.
        assert profile==(4|codes[f'MONO_UHD{fps}'])
        values[f'GEOMETRY_SENSOR_UHD{fps}']=(3,profile)
    text='// Generated from docs/geometry_control_v1.json.\n`ifndef GEOMETRY_CONTROL_V1_VH\n`define GEOMETRY_CONTROL_V1_VH\n'
    text+=''.join(f"`define {k} {w}'h{v:x}\n" for k,(w,v) in values.items())+'`endif\n'
    python='# Generated from docs/geometry_control_v1.json.\n'+''.join(f'{k}=0x{v:x}\n' for k,(_,v) in values.items())
    return {ROOT/'src_fpga/rtl/include/00_rtl/geometry_control_v1.vh':text,ROOT/'rk_sdk/geometry_control_constants.py':python}
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
    for path,body in outputs().items():
        if a.check: assert path.read_text(encoding='utf-8')==body,str(path)
        else:path.write_text(body,encoding='utf-8',newline='\n')
if __name__=='__main__':main()
