from pathlib import Path
import hashlib,json,re,shutil,subprocess
ROOT=Path(__file__).resolve().parents[4]
DOC=ROOT/'docs'
OUT=DOC/'validation/lane_timing_fix_r1_20261031'
OUT.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
result=dict(status='SIMULATION_PASS_PHYSICAL_NOT_RUN',baseline_commit=subprocess.check_output(['git','rev-parse','e700521176'],text=True).strip(),synthesis='NOT_RUN',place_route='NOT_RUN',routed_timing='NOT_RUN',board='NOT_RUN',old_routed_e700='FAIL',mapped_resource_delta='NOT_MEASURED',declared_added_state_bits_upper_bound=165,new_eram_or_dsp=0,production_sources=[],runs={},evidence=[])
(OUT/'source').mkdir(exist_ok=True)
for name in ['lane_ridge_candidates1_lutram.v','lane_quarter_fifo4_to1.v','lane_sparse_serial4.v']:
 p=ROOT/'src_fpga/rtl'/name
 old=subprocess.check_output(['git','show',result['baseline_commit']+':refactor/dual_lane_s1/src_fpga/rtl/'+name])
 result['production_sources'].append(dict(path=str(p),sha256=sha(p),changed_from_e700=p.read_bytes()!=old))
 shutil.copyfile(p,OUT/'source'/(name+'.txt'))
for run in ['timing_leaf_r1','timing_leaf_r2','timing_shared_r1','timing_fifo_stall_r1']:
 origin=ROOT/'tmp/lane_timing'/run;dest=OUT/run;dest.mkdir(exist_ok=True)
 raw=json.loads((origin/'RESULTS.json').read_text())
 result['runs'][run]={k:raw.get(k) for k in ['simulation','error','results','observations']}
 for name in ['RESULTS.json','compile.log','benches.log','tb_fifo.log','tb_ridge.log','tb_worker.log','tb_shared.log','tb_fifo_stall.log']:
  p=origin/name
  if p.exists():shutil.copyfile(p,dest/name)
 if raw['simulation']=='PASS':
  for item in raw['inputs']:
   p=Path(item['path'])
   if p.name not in ['lane_ridge_candidates1_lutram.v','lane_quarter_fifo4_to1.v']:continue
   data=p.read_bytes();lf=data.replace(b'\r\n',b'\n')
   recovered=next((b for b in [data,lf,lf.replace(b'\n',b'\r\n')] if hashlib.sha256(b).hexdigest()==item['sha256']),None)
   assert recovered is not None,p
   (dest/(p.name+'.source_used.txt')).write_bytes(recovered)
for p in (Path(__file__).parent/'fixed_e700').glob('*.txt'):shutil.copyfile(p,OUT/'source'/p.name)
for name in ['run.py','tb_worker.sv','tb_fifo.sv','tb_fifo_stall.sv','tb_ridge.sv','tb_shared.sv','collect_evidence.py']:
 shutil.copyfile(Path(__file__).parent/name,OUT/'source'/(name+'.txt'))
paths={};reports=[]
for seed in ['s1','s3','s9']:
 p=ROOT.parents[1]/'server/td/local/dual_lane_nodehaze_20261031/routed'/seed/'checkout/refactor/dual_lane_s1/fpga_prj/rfdual_lane_s1_Runs/phy_1/controller-reports/timing_detail.rpt'
 reports.append(dict(path=str(p),sha256=sha(p)))
 rows=[];first=None
 for block in re.split(r'\n(?=Slack\s+:)',p.read_text()):
  def one(key):
   m=re.search('^'+key+r'\s+:\s*(.*)',block,re.M);return m.group(1) if m else ''
  if not one('Begin Point') or '/lane/' not in one('Begin Point')+one('End Point'):continue
  rows.append({k:one(k) for k in ['Slack','Begin Point','End Point','Data Path Delay','Clock Skew','Logic Level','Max Fanout','Check Type']})
  if first is None and one('Check Type')=='setup':first=block
 paths[seed]=rows;(OUT/(seed+'_worst_lane_path.txt')).write_text(first)
(OUT/'old_routed_lane_paths.json').write_text(json.dumps(dict(sources=reports,paths=paths),indent=2)+'\n')
result['old_sta_reports']=reports
result['arrival_bound']={'primary_arbitrary_interval_quarter_groups': 'Q<=ceil(T/16)+222', 'native_half_input_groups': 'P<=ceil(T/4)+122', 'half_nonbottom_grants': 'H<=P+4', 'quarter_input_groups': 'G<=ceil(H/4)+62', 'quarter_output_inventory_groups': 8, 'independent_quarter_bottom_groups': 120, 'half_bottom_y': 539, 'half_bottom_selected': False, 'sample_service_II': 1, 'group_service_clocks': 4, 'startup_clocks': 3, 'last_low_occupancy_groups': 2, 'conservative_resident_groups_bound': 226, 'logical_fifo_depth': 256, 'spare_groups': 30, 'old_segment_debt_estimate_groups': 127, 'old_estimate_is_not_the_only_proof': True, 'terminal_drain_bound_clocks': 1152}
prior=DOC/'LANE_TIMING_FIX_R1_RESULTS_20261031.json'
if prior.exists():
 previous=json.loads(prior.read_text())
 if 'readonly_f22_followup' in previous:result['readonly_f22_followup']=previous['readonly_f22_followup']
for p in sorted(OUT.rglob('*')):
 if p.is_file():result['evidence'].append(dict(path=str(p.relative_to(DOC)),sha256=sha(p)))
(DOC/'LANE_TIMING_FIX_R1_RESULTS_20261031.json').write_text(json.dumps(result,indent=2)+'\n')
print('permanent evidence files',len(result['evidence']))
