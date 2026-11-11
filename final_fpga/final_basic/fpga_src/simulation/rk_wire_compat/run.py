"""Decode actual accepted C2H bytes with the immutable seed1 release parser."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import zlib
import cv2
import numpy as np

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
REPO=PROJECT.parents[1]
DELIVERY=Path(os.environ.get('RK_SEED1_RUNTIME',REPO/'deliverables/DUAL_HDR_06a122ee70_seed1_RK_Debug_20261101/runtime')).resolve()
POLICY=Path(os.environ.get('RK_SEED1_POLICY_RUNTIME',REPO/'deliverables/DUAL_HDR补充/DUAL_HDR_seed1_顺序全功能三会话结果_20261101/phase-B/runtime-package/runtime')).resolve()
sys.path[:0]=[str(DELIVERY),str(POLICY)]
from linux.task3_pipeline import pcie_protocol_v1 as p,record_v2,record_v4
from linux.stream_diag import records
import dual_r3_stereo

SESSION=0x12345678
EPOCH=300
MODES=(0,48,0,0,15,15)
HDR=(False,False,True,False,False,True)
APPLIED=(False,False,False,False,False,True)


def sha(path):
    return sha256(path.read_bytes()).hexdigest()


def fixture(out):
    yy,xx=np.indices((1080,1920),dtype=np.uint16)
    ok,encoded=cv2.imencode('.jpg',((xx//96+yy//80)%8*27).astype(np.uint8),[cv2.IMWRITE_JPEG_QUALITY,75])
    assert ok
    jpeg=encoded.tobytes()
    if len(jpeg)%16==0:
        jpeg=jpeg[:2]+bytes.fromhex('fffe0003aa')+jpeg[2:]
    (out/'jpeg.hex').write_text('\n'.join(f'{b:02x}' for b in jpeg)+'\n')
    src=[];published=[];gold=[]
    for slot,mask in enumerate(MODES):
        seq=100+slot
        flags=p.PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY
        if HDR[slot]:
            flags|=p.PCIE_RECORD_V2_FLAG_PAIR|p.PCIE_RECORD_V2_FLAG_JOB|p.PCIE_RECORD_V2_FLAG_QUALIFIED|p.PCIE_RECORD_V2_FLAG_HDR_PRODUCT
        meta=dict(zip(p.RECORD_V2_EXTENSION_FIELD_NAMES,p.RECORD_V2_EXTENSION_STRUCT.unpack(bytes(128))))
        meta.update(p.RECORD_V2_EXTENSION_EXPECTED_VALUES)
        meta.update(validity_flags=flags,source_session=SESSION,source_epoch=EPOCH,source_sequence=seq,
                    source_camera=int(slot>=3),source_kind=1,source_format=1,exposure_role=int(HDR[slot]),
                    pair_id=seq if HDR[slot] else 0,job_id=seq if HDR[slot] else 0,processing_mode=0x80|mask,
                    record_flags=int(HDR[slot])|(4 if APPLIED[slot] else 0))
        ext=bytearray(2048)
        ext[:128]=p.RECORD_V2_EXTENSION_STRUCT.pack(*(meta[n] for n in p.RECORD_V2_EXTENSION_FIELD_NAMES))
        lane=slot==1
        struct.pack_into('<IBBBBBBHHH',ext,128,0x34565053,1,5,3 if lane else 0,3 if lane else 0,0,0,303 if lane else 0,169,269)
        if lane:
            for i in range(303):
                pt=(64+120*(i%3))|((169+i//3)<<11)|((100+i)<<20)|((1+i%8)<<31)|((1+i%2)<<35)
                ext[256+5*i:261+5*i]=pt.to_bytes(5,'little')
        src.append(ext.copy())
        struct.pack_into('<II',ext,24,SESSION,20+slot)
        published.append(ext)
        header=dict(zip(p.FRAME_HEADER_FIELD_NAMES,p.FRAME_HEADER_STRUCT.unpack(bytes(64))))
        header.update(p.FRAME_HEADER_EXPECTED_VALUES)
        header.update(protocol_version=4,header_length=2112,frame_sequence=seq,payload_length=len(jpeg),
                      width=1920,height=1080,compression=1,quality=75,slot_id=slot,payload_crc32=zlib.crc32(jpeg))
        gold.append(p.FRAME_HEADER_STRUCT.pack(*(header[n] for n in p.FRAME_HEADER_FIELD_NAMES))+ext+jpeg)
    bad=[src[i].copy() for i in (0,1,0,1,1,1)]
    struct.pack_into('<H',bad[0],138,304)
    bad[1][260]|=128
    bad[2][-1]=1
    bad[3][261:266]=((int.from_bytes(bad[3][261:266],'little')&~2047)|66).to_bytes(5,'little')
    bad[4][134]=bad[4][135]=1
    bad[5][137]=128
    for name,items in [('source',src),('expected',published),('bad',bad)]:
        (out/(name+'.hex')).write_text(''.join(bytes(reversed(x)).hex()+'\n' for x in items))
    original=PROJECT/'src_fpga/simulation/sparse_transport/tb_sparse_transport.sv'
    tb=original.read_text()
    tb=tb.replace('    integer order[0:5];',f'    localparam PAYLOAD_SIZE={len(jpeg)};\n'+(HERE/'monitor.svh').read_text()+'\n    integer order[0:5];')
    tb=re.sub(r'case\(n\)0:payload_length=.*?endcase','payload_length=PAYLOAD_SIZE;',tb)
    tb=tb.replace("32'hc0ffee01","32'h%08x"%zlib.crc32(jpeg))
    tb=tb.replace('payload_data[j*8+:8]=sent+j','payload_data[j*8+:8]=jpeg[sent+j]')
    # The fixture stops at the last invalid length's negedge. Capture its real
    # registered abort pulse on the following positive edge before closing.
    tb=tb.replace('$display("RESULT: PASS SPARSE_TRANSPORT','@(posedge clk);@(negedge clk);$fclose(stream_log);\n        $display("RESULT: PASS SPARSE_TRANSPORT')
    for index in ['n','0']:
        old=f'stage_extension(source[{index}]);'
        assert tb.count(old)==1
        tb=tb.replace(old,f'check(ctx_valid && ctx_data===source[{index}][1023:0],"real CTX2 bytes");stage_extension({{source[{index}][16383:1024],ctx_data}});')
    (out/original.name).write_text(tb)
    return jpeg,gold


def collect(trace):
    complete={};slot=None;data=bytearray();last=False;aborts=0;partials=0
    for line in trace.read_text().splitlines():
        words=line.split()
        if words[0]=='S':
            assert slot is None
            slot=int(words[1]);data=bytearray();last=False
        elif words[0]=='B':
            assert slot is not None and not last
            beat=int(words[1],16).to_bytes(16,'little');keep=int(words[2],16)
            assert keep and (keep&(keep+1))==0
            data.extend(beat[lane] for lane in range(16) if keep>>lane&1)
            last=words[3]=='1'
            assert last or keep==0xffff
            partials+=int(last and keep!=0xffff)
        elif words[0]=='D':
            assert last and slot not in complete
            complete[slot]=bytes(data);slot=None
        elif words[0]=='A':
            aborts+=1;slot=None;data=bytearray();last=False
        else:
            raise ValueError(line)
    assert slot is None and set(complete)==set(range(6)) and partials==6 and aborts==4
    return complete,aborts


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for n in ['td-root','modelsim-bin']:ap.add_argument('--'+n,type=Path,required=True)
    ap.add_argument('--name',required=True)
    a=ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,45}',a.name):ap.error('invalid fresh name')
    out=PROJECT/'tmp/rk_wire_compat'/a.name
    out.mkdir(parents=True)
    jpeg,gold=fixture(out)
    rel=[Path('rtl')/(name+'.v') for name in ('td_sdp_ram40','lane_sparse_extension_checker','ddr_extension_staging_ram',
          'jpeg_metadata_append5','jpeg_record_metadata_store','frame_record_extension_builder','c2h_frame_tx')]
    rel.insert(0,Path('ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v'))
    includes=[Path('rtl/include/04_include/pcie_protocol_v1.vh'),Path('rtl/include/01_include/pcie_record_v3_validate.vh')]
    sim=a.td_root/'sim_release'
    models=[sim/n for n in ('common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_phy_eram.v','ph1/ph1_logic_dram.v')]
    inputs=[HERE/'run.py',HERE/'monitor.svh',PROJECT/'src_fpga/simulation/sparse_transport/tb_sparse_transport.sv',
            Path(records.__file__),Path(record_v2.__file__),Path(record_v4.__file__),Path(p.__file__),Path(dual_r3_stereo.__file__),*models]
    assert all(Path(m.__file__).resolve().is_relative_to(DELIVERY.resolve()) for m in (p,records,record_v2,record_v4))
    frozen={records:'2f964c49ef6cadb81be9e566462d502be1cef5388d485223132a0c813d5ec7c7',
            record_v2:'f26d53d41360d030575487a9a940276d97d9584a02e520a6e2ad155c4f9deb9f',
            record_v4:'bdc3736b1ae9a7a4b21c7fc7d4a3f6172807f9d9b71c8f38f06203a2dae058bb',
            p:'4acdfa4b18adf8b27bf7f94e96e50e8dc450170473c3acbb9990194e9b56967e',
            dual_r3_stereo:'7275383bf8ee86488e2d1b617c5ff7f671264a46541e9f0dcaa4b2d81926edb0'}
    if any(sha(Path(mod.__file__))!=hash_value for mod,hash_value in frozen.items()):
        raise ValueError('expected unmodified seed1 release parser and field policy')
    result=dict(status='IN_PROGRESS',inputs={str(f):sha(f) for f in inputs},runs={},board='NOT_RUN')
    wires={}
    for variant in ['current','seed1']:
        d=out/variant;d.mkdir()
        for f in [*out.glob('*.hex'),out/'tb_sparse_transport.sv']:shutil.copyfile(f,d/f.name)
        for f in rel+includes:
            target=d/f.name
            if variant=='current':
                shutil.copyfile(PROJECT/'src_fpga'/f,target)
            else:
                blob='06a122ee70:refactor/dual_hdr_merge_r1/src_fpga/'+f.as_posix()
                target.write_bytes(subprocess.check_output(['git','show',blob],cwd=REPO))
        def tool(name,opts,label):
            cr=subprocess.run([str(a.modelsim_bin/(name+'.exe')),*map(str,opts)],cwd=d,capture_output=True,timeout=50)
            body=(cr.stdout+cr.stderr).decode(errors='replace');(d/(label+'.log')).write_text(body,encoding='utf8')
            if cr.returncode or re.search(r'\*\* (Fatal|Error):',body):raise RuntimeError(body[-2500:])
            return body
        tool('vmap',['-c'],'map')
        for lib in ('ph1','work'):tool('vlib',[lib],lib)
        tool('vlog',['-quiet','-work','ph1',*models],'models')
        tool('vlog',['-quiet','-timescale','1ns/1ps','+incdir+.',sim/'ph1/ph1_phy_gsr.v',*[d/f.name for f in rel]],'rtl')
        tool('vlog',['-sv','-quiet','+incdir+.',d/'tb_sparse_transport.sv'],'tb')
        log=tool('vsim',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_sparse_transport','-do','run -all; quit -f'],'run')
        assert 'RESULT: PASS SPARSE_TRANSPORT' in log
        wire,aborts=collect(d/'axis.txt');wires[variant]=wire
        row=dict(aborts=aborts,inputs={f.name:sha(d/f.name) for f in rel+includes},
                 transport_result=next(l.strip('# ') for l in log.splitlines() if 'RESULT: PASS SPARSE_TRANSPORT' in l),records=[])
        for slot,data in sorted(wire.items()):
            assert len(data)==len(gold[slot]),f'{variant} slot {slot} wire length'
            assert data==gold[slot],f'{variant} slot {slot}, first diff {next(i for i,(x,y) in enumerate(zip(data,gold[slot])) if x!=y)}'
            rec=records.parse_record(data,expected_version=4);m=rec.metadata;eye=int(slot>=3)
            assert (rec.jpeg,rec.sequence,rec.width,rec.height)==(jpeg,100+slot,1920,1080)
            assert (m.source.camera,m.source.session,m.source.epoch,m.source.sequence)==(eye,SESSION,EPOCH,100+slot)
            assert (m.processing_mode,m.record_flags)==(0x80|MODES[slot],int(HDR[slot])|int(APPLIED[slot])*4)
            assert (m.jpeg_slot,m.jpeg_session,m.jpeg_generation)==(slot,SESSION,20+slot)
            assert (m.source.role,bool(m.qualified),m.pair_id,m.job_id)==(int(HDR[slot]),HDR[slot],100+slot if HDR[slot] else None,100+slot if HDR[slot] else None)
            lane=rec.s07.f23
            if slot==1:
                assert lane.count==303 and all((v.native_x,v.quarter_y,v.strength,v.width_quarter,v.marking_class)==
                    (64+120*(i%3),169+i//3,100+i,1+i%8,1+i%2) for i,v in enumerate(lane.points))
            else:assert rec.s07.enabled==0 and lane is None
            try:dual_r3_stereo.validate_color_record(rec);color=True
            except dual_r3_stereo.StereoAdmissionError:color=False
            assert color==(slot in (0,3))
            (d/f'slot{slot}.ajpg').write_bytes(data)
            row['records'].append(dict(slot=slot,bytes=len(data),sha256=sha256(data).hexdigest(),legacy_color_policy=color,
                enable_mask=MODES[slot],hdr=HDR[slot],dehaze_used=APPLIED[slot],points=303 if lane else 0))
        result['runs'][variant]=row
    assert wires['seed1']==wires['current']
    assert result['inputs']=={str(f):sha(f) for f in inputs}
    result['status']='PASS'
    (out/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS: two actual formatter pipelines, six equal complete outputs, 303 old points, four discarded probes per pipeline')


if __name__=='__main__':
    main()
