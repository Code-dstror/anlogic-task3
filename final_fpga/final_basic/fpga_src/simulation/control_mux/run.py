"""Actual official FIFO A/B, with independent complete-message scoreboard."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--td-root',type=Path,required=True);p.add_argument('--modelsim-bin',type=Path,required=True);p.add_argument('--name',required=True);a=p.parse_args()
 run=ROOT/'tmp/control_mux'/a.name;run.mkdir(parents=True,exist_ok=False)
 old=subprocess.check_output(['git','show','ed50d4e7534b1574213d173e941dbfbcfdf20351:refactor/hdr_lane_sparse/src_fpga/rtl/control_message_fifo_ip.v'],cwd=ROOT)
 ref=run/'reference.v';ref.write_bytes(old.replace(b'module control_message_fifo_ip #(',b'module control_message_fifo_reference #('))
 models=[a.td_root/'sim_release'/f for f in ['common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v']]
 rtl=ROOT/'src_fpga/rtl';ip=ROOT/'src_fpga/ip/camera_control_fifo_40x512'
 src=[ip/'RTL/camera_control_fifo_40x512_soft_fifo_core.v',ip/'RTL/camera_control_fifo_40x512_soft_fifo.v',ip/'camera_control_fifo_40x512.v',rtl/'control_fifo_40x512.v',rtl/'control_message_fifo_ip.v',ref,HERE/'tb_control_mux.sv',a.td_root/'sim_release/ph1/ph1_phy_gsr.v']
 inputs={str(x.resolve()):hashlib.sha256(x.read_bytes()).hexdigest() for x in models+src+[Path(__file__)]}
 (run/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
 def call(exe,args,log):
  cmd=[str(a.modelsim_bin/(exe+'.exe'))]+[str(x) for x in args]
  with (run/log).open('w',encoding='utf-8') as f:code=subprocess.call(cmd,cwd=run,stdout=f,stderr=subprocess.STDOUT)
  if code:raise RuntimeError(f'{exe} failed: {log}')
 call('vlib',['ph1'],'vlib_ph1.log');call('vmap',['ph1','ph1'],'vmap_ph1.log')
 call('vlog',['-quiet','-work','ph1']+models,'ph1.log')
 call('vlib',['work'],'vlib_work.log');call('vmap',['work','work'],'vmap_work.log')
 call('vlog',['-sv','-quiet','+define+PH1']+src,'compile.log')
 results=[];start=time.monotonic()
 for w in [1,39,40,41,147,545,617,1280]:
  for b in [0,1]:
   log=f'w{w}_b{b}.log'
   call('vsim',['-c','-L','ph1','work.PH1_PHY_GSR','work.tb_control_mux',f'-gW={w}',f'-gBORROW={b}','-do','run -all; quit -f'],log)
   s=(run/log).read_text(errors='replace')
   if 'PASS_CONTROL_MUX' not in s or '** Error:' in s or '** Fatal:' in s:raise RuntimeError(log)
   results.append(next(x.strip() for x in s.splitlines() if 'PASS_CONTROL_MUX' in x))
 drift=[name for name,h in inputs.items() if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=h]
 if drift:raise RuntimeError(f'actual input drift: {drift}')
 result=dict(status='PASS',reference_commit='ed50d4e7534b1574213d173e941dbfbcfdf20351',reference_sha256=hashlib.sha256(old).hexdigest(),cases=results,elapsed_seconds=time.monotonic()-start,inputs=inputs)
 (run/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='inputs'},indent=2))
if __name__=='__main__':main()
