"""Short source-bound RX diagnostic tests. No board or server access."""
from pathlib import Path
import argparse,subprocess,json,hashlib,importlib.util,re
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
p=argparse.ArgumentParser();p.add_argument('--name',required=True);p.add_argument('--modelsim-bin',type=Path,required=True);a=p.parse_args()
assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
run=ROOT/'tmp/rx_diag'/a.name;run.mkdir(parents=True,exist_ok=False)
names=['physical_csi_word_core.v','imx415_hdr2_config_owner.v','imx415_hdr2_recipe_rom.v','real_hdr_pair_cycle_gate.v','reset_release_sync.v','cfg_diag_snapshot.v','uart_observer_snapshot.v','uart_status_observer.v']
sources=[ROOT/'src_fpga/rtl'/n for n in names]+[HERE/'rx_diag_leaf_tb.sv',HERE/'rx_diag_uart_tb.sv']
identity=[dict(path=str(x),sha256=hashlib.sha256(x.read_bytes()).hexdigest()) for x in sources+[Path(__file__),ROOT/'tools/uart_observer.py']]
result=dict(status='IN_PROGRESS',inputs=identity,board='NOT_RUN',physical='NOT_RUN')
def call(exe,args):
 r=subprocess.run([str(a.modelsim_bin/exe)]+list(map(str,args)),cwd=run,capture_output=True,text=True)
 if r.returncode:raise RuntimeError(r.stdout[-12000:]+r.stderr[-2000:])
try:
 call('vmap.exe',['-c']);call('vlib.exe',['work']);call('vmap.exe',['work','work'])
 call('vlog.exe',['-quiet','-sv','+incdir+'+str(ROOT/'src_fpga/rtl/include/04_include'),'-l','compile.log']+sources)
 for top in ['rx_diag_leaf_tb','rx_diag_uart_tb']:
  call('vsim.exe',['-c','work.'+top,'-l',top+'.log','-do','onerror {quit -code 1}; run -all; quit -f'])
  body=(run/(top+'.log')).read_text();assert 'RESULT: PASS' in body,body[-8000:]
  assert not re.search(r'\*\*\s+(Error|Fatal):',body),body[-8000:]
 spec=importlib.util.spec_from_file_location('rx_parser',ROOT/'tools/uart_observer.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 raw=(run/'rx_diag_wire.bin').read_bytes();d=m.FrameDecoder();frames=d.feed(raw)
 assert d.crc_errors==0 and d.discarded_bytes==0 and len(frames)==12 and d.rx_frames==4,d.summary()
 samples=[f for f in frames if f.get('frame_type')=='rx'];assert samples[0]['fresh_mask']&1==0 and samples[-1]['fresh_mask']==7
 assert samples[-1]['words'][0]==[9,8,7,6],samples[-1]
 # RX is consumed atomically even if held words contain another frame signature.
 packet=raw[-64:];bad=bytearray(packet);bad[20]^=128
 for split in range(len(packet)+1):
  parser=m.FrameDecoder();got=parser.feed(packet[:split])+parser.feed(packet[split:]);assert len(got)==1 and got[0]['frame_type']=='rx'
 parser=m.FrameDecoder();got=parser.feed(b'noise'+bytes(bad)+packet);assert len(got)==1 and parser.rx_crc_errors>=1
 for row in identity:assert hashlib.sha256(Path(row['path']).read_bytes()).hexdigest()==row['sha256']
 result.update(status='PASS',decoder=d.summary(),leaf='first_loss_and_actual_warmup_boundaries_PASS',split_points=65)
except Exception as e:
 result.update(status='FAIL',error=str(e));raise
finally:
 (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(dict(run=str(run),status=result['status'],error=result.get('error'))))
