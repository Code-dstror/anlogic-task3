"""Single production OB/CGv2/RX wire check after static RT retirement."""
import argparse
import binascii
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    a=ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}',a.name):ap.error('unsafe name')
    run=ROOT/'tmp/uart_no_rt'/a.name;run.mkdir(parents=True,exist_ok=False)
    top=ROOT/'src_fpga/rtl/anlogic2026.v';sdc=ROOT/'fpga_prj/constraints/observer_cdc.sdc'
    sources=[ROOT/'src_fpga/rtl'/name for name in ['reset_release_sync.v','uart_observer_snapshot.v','cfg_diag_snapshot.v','uart_status_observer.v']]
    bench=HERE/'tb_uart_no_rt.sv';decoder_path=ROOT/'tools/uart_observer.py'
    compact=re.sub(r'\s+','',top.read_text())
    for fragment in ['.RX_TRACE_ENABLE(0)','.RX_DIAG_ENABLE(1)','.CFG_DIAG_ENABLE(1)','.CFG_FRAME_VERSION(2)',
                     ".i_trace_ack(1'b0)",".i_trace_data(320'd0)",'.o_trace_request()','.o_trace_index()']:
        assert fragment in compact,fragment
    paths=sources+[bench,decoder_path,top,sdc,ROOT/'fpga_prj/constraints/stream_cdc.sdc',Path(__file__)]
    identity=[{'path':str(path),'sha256':sha(path)} for path in paths]
    result={'status':'IN_PROGRESS','inputs':identity,'commands':[],
            'scope':'ONE_OB_CGV2_RX_NO_RT_COMBINATION_WITH_STOPPED_WORD_USER_AND_RESETS',
            'physical':'NOT_RUN','timing':'NOT_RUN','board':'NOT_RUN','real_serial_access':'NOT_RUN'}
    def call(exe,words,label):
        argv=[str(a.modelsim_bin/exe),*map(str,words)];result['commands'].append(argv)
        p=subprocess.run(argv,cwd=run,capture_output=True,text=True,errors='replace',timeout=60)
        (run/(label+'.console.log')).write_text(p.stdout+p.stderr)
        if p.returncode:raise RuntimeError((p.stdout+p.stderr)[-8000:])
    try:
        call('vmap.exe',['-c'],'map');call('vlib.exe',['work'],'lib')
        call('vlog.exe',['-quiet','-l','rtl.log',*sources],'rtl')
        call('vlog.exe',['-quiet','-sv','-l','bench.log',bench],'bench')
        call('vsim.exe',['-c','work.tb_uart_no_rt','-l','run.log','-do','onerror {quit -code 1};run -all;quit -f'],'run')
        body=(run/'run.log').read_text()
        assert 'RESULT: PASS uart_no_rt' in body,body[-8000:]
        for name in ('rtl.log','bench.log','run.log'):
            assert not re.search(r'\*\*\s+(Warning|Error|Fatal):',(run/name).read_text()),name
        raw=(run/'uart_no_rt.bin').read_bytes();at=0;packets=[]
        while at<len(raw):
            magic=raw[at:at+2];length={b'OB':29,b'CG':68,b'RX':64}.get(magic)
            assert length,('retired/unknown magic',at,magic)
            packet=raw[at:at+length];assert len(packet)==length
            if magic!=b'OB':assert int.from_bytes(packet[-2:],'little')==binascii.crc_hqx(packet[:-2],65535)
            packets.append(packet);at+=length
        assert len(packets)==27 and [p[:2] for p in packets]==[b'OB',b'CG',b'RX']*9
        spec=importlib.util.spec_from_file_location('no_rt_parser',decoder_path)
        parser=importlib.util.module_from_spec(spec);spec.loader.exec_module(parser)
        d=parser.FrameDecoder();frames=d.feed(raw)
        assert len(frames)==27 and d.discarded_bytes==d.crc_errors==d.invalid_headers==0 and not d.buffer
        assert sum(f.get('frame_type')=='cfg' for f in frames)==9
        assert sum(f.get('frame_type')=='rx' for f in frames)==9
        assert not any(f.get('frame_type')=='trace' for f in frames)
        for row in identity:assert sha(Path(row['path']))==row['sha256'],row['path']
        result.update(status='PASS',metrics=[line.strip('# ') for line in body.splitlines() if 'RESULT: PASS' in line],
                      offline_decoder=d.summary(),wire_capture_sha256=sha(run/'uart_no_rt.bin'),wire_bytes=len(raw),
                      counts={'OB':9,'CGv2':9,'RX':9,'RT':0})
        (run/'decoded_frames.json').write_text(json.dumps(frames,indent=2)+'\n')
        print('\n'.join(result['metrics']));print('Offline decoder:',d.summary())
    except Exception as error:result.update(status='FAIL',error=str(error));raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__':main()
