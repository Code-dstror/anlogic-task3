"""Bounded digital repro against seed6's fixed source; never builds/programs FPGA."""
from pathlib import Path
import argparse,hashlib,json,subprocess

def main():
 p=argparse.ArgumentParser();p.add_argument('--name',required=True);p.add_argument('--modelsim-bin',required=True);a=p.parse_args()
 here=Path(__file__).resolve().parent;project=here.parents[2];repo=project.parents[1]
 assert a.name.replace('_','').isalnum()
 run=project/'tmp/calibration_repair_chain'/a.name;run.mkdir(parents=True,exist_ok=False)
 fixed='91a778d111dded43a6d973240be6e4e4e7a9ddcf';root='refactor/hdr_rx_repair/src_fpga/'
 names=['rtl/ph1a_rx_delay_scan.v','rtl/csi2_ph1_phy_wrapper.v','rtl/csi_clock_watchdog.v',
  'rtl/csi_rx_byte_align_observed.v','rtl/csi_rx_word_align_observed.v','rtl/physical_csi_word_core.v',
  'ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v','ip/vendor/anlogic_camera/phy/auto_delay_ctl.v']
 inputs=[]
 for name in names:
  data=(repo/root/name).read_bytes()
  f=run/'inputs'/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(data)
  inputs.append(dict(path=root+name,sha256=hashlib.sha256(data).hexdigest(),snapshot=str(f)))
 tbs=[here/'tb_calibration_repair_chain.sv']
 for f in tbs: inputs.append(dict(path=str(f),sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
 commands=[]
 def call(exe,args,label,limit=180):
  cmd=[str(Path(a.modelsim_bin)/exe),*args]
  r=subprocess.run(cmd,cwd=run,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=limit,creationflags=subprocess.CREATE_NO_WINDOW)
  (run/(label+'.console.log')).write_bytes(r.stdout);commands.append(dict(argv=cmd,exit=r.returncode,timeout=limit))
  if r.returncode:raise RuntimeError(r.stdout.decode(errors='replace'))
 call('vlib.exe',['work'],'vlib');call('vmap.exe',['-c'],'vmap')
 call('vlog.exe',['-sv','-work','work',*[str(run/'inputs'/n) for n in names],*map(str,tbs)],'compile')
 results=[]
 for top in ['tb_calibration_repair_chain']:
  call('vsim.exe',['-c','-lib','work',top,'-l',str(run/(top+'.log')),'-do','run -all; quit -f'],top)
  log=(run/(top+'.log')).read_text(errors='replace')
  ok='RESULT PASS' in log and '** Fatal:' not in log and '** Error:' not in log
  lines=[l for l in log.splitlines() if 'CASE ' in l or 'RESULT ' in l]
  results.append(dict(top=top,passed=ok,lines=lines));print('\n'.join(lines),flush=True)
  if not ok:
   (run/'RESULTS.json').write_text(json.dumps(dict(source_base=fixed,source_scope="working inputs bound by hashes",passed=False,inputs=inputs,commands=commands,results=results),indent=2));raise RuntimeError(log[-8000:])
 (run/'RESULTS.json').write_text(json.dumps(dict(source_base=fixed,source_scope="working inputs bound by hashes",passed=True,inputs=inputs,commands=commands,results=results,
  scope='Digital fixed RTL control/feedback; ideal deserialized byte boundary; no electrical or actual board trigger proof',production_edited=True,board_actions=0,server_builds=0),indent=2))
 print(run/'RESULTS.json')
if __name__=='__main__':main()
