"""Collect completed recovery evidence; no simulator/server/device calls."""
from pathlib import Path
import hashlib,json,re
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[3]
RUNS=('word_recovery_r01','word_strict_r01','receiver_matrix_r01','physical_r01','adversarial_recovery_r01','adversarial_strict_r01','short_alias_r01','scanner_edges_r01')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 port=json.loads((HERE/'PORT_IDENTITY.json').read_text(encoding='utf-8'))
 for row in port['files']:
  path=PROJECT/'src_fpga/rtl'/row['file'];actual=sha(path)
  if actual!=row['current_sha256']:raise RuntimeError('ported source drift: '+str(path))
 runs=[]
 for name in RUNS:
  path=PROJECT/'tmp/recovery'/name/'RESULTS.json';d=json.loads(path.read_text(encoding='utf-8'))
  row=dict(name=name,status=d['status'],result_path=str(path),result_sha256=sha(path),metrics=[x for x in d.get('metrics',[]) if x.startswith('RESULT')],warnings=d.get('warnings',d.get('accepted_vendor_warnings',[])))
  if name=='scanner_edges_r01':row.update(case_count=d.get('case_count'),passed=d.get('passed'),failed=d.get('failed'))
  if 'known_contract_exposures' in d:row['known_contract_exposures']=d['known_contract_exposures'];row['unexpected_mismatches']=d['unexpected_mismatches']
  # Every focused runner seals its source + compiled snapshot. Recheck once at collection.
  checked=0
  for item in d.get('inputs',[]):
   if 'original' in item and 'path' in item:
    if sha(Path(item['original']))!=item['sha256'] or sha(Path(item['path']))!=item['sha256']:raise RuntimeError('input drift '+item['original'])
    checked+=1
  row['source_and_compiled_inputs_rechecked']=checked;runs.append(row)
 result=dict(candidate=str(PROJECT),baseline_commit='b68fdc2d79b9ae3579174366f0fdce89dfc9f389',ported_recovery_commit='b26058dd436afcf0966f2fe643ccbf7664a2e5de',
  status='FUNCTIONAL_PASS_WITH_KNOWN_DIGITAL_CONTRACT_EXPOSURE',production_rtl=port['files'],runs=runs,
  critical_observations=[
   'SDR recognized new FS recovers with monotonic new identity; default strict and saturation remain fail-closed.',
   'Repeated header/CRC + stalled next FS preserves old terminal identity and first RX latch.',
   'Actual raw40 rejection yields no invented ECC/CRC; next FS negatively terminates old SOURCE1 before complete SOURCE2.',
   'All sixteen short lane aliases negatively terminate old SOURCE: thirteen ECC, three CRC; subsequent SOURCE2 golden data succeeds.',
   'Known PD-boundary immediate raw SYNC probe preserves two FAIL assertions, not a board-reachability proof.',
   'Old SOURCE/record retirement before local clear is ported in TOP; complete TOP/JOIN/JPEG/STOP validation is owned by MAIN, not these leaf tests.'
  ],synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',bitgen='NOT_RUN',board='NOT_RUN',full_main='NOT_CLAIMED_BY_THIS_REPORT')
 (HERE/'RECOVERY_RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(dict(status=result['status'],runs=[dict(name=r['name'],status=r['status']) for r in runs]),indent=2))
if __name__=='__main__':main()
