"""Convert simulation-only FS edge evidence into an explicit disposition log."""
from pathlib import Path
import argparse,csv,json
ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);a=ap.parse_args()
rows=list(csv.DictReader((a.run/'trace.csv').open()))
events=[];first=None
for r in rows:
    if r['event_valid']=='1' and r['event_kind']=='0':
        if first is None:first=int(r['cycle'])
        if r['event_ready']=='1':
            reasons=[]
            for field in ['busy_q','stop','cfg_pause','cfg_valid']:
                if r[field]=='1':reasons.append(field)
            for field in ['source_idle','idle_now','idle_q','record_available']:
                if r[field]=='0':reasons.append('no_'+field)
            events.append({'case':int(r['case']),'sequence':int(r['event_sequence']),
                           'first_offered_cycle':first,'consumed_cycle':int(r['cycle']),
                           'held_cycles':int(r['cycle'])-first,'credit':int(r['credit']),
                           'disposition':'OWNED' if r['credit']=='1' else 'IGNORED_NO_CREDIT',
                           'observed_low_gates':','.join(reasons) if reasons else ('NONE' if r['credit']=='1' else 'CREDIT_NOT_PUBLISHED_OR_UNLOGGED_GATE')})
            first=None
    elif r['event_valid']=='0':first=None
with (a.run/'FS_DISPOSITIONS.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=events[0].keys());w.writeheader();w.writerows(events)
r=json.loads((a.run/'RESULTS.json').read_text())
summary={'status':r['status'],'input_identity':'RESULTS.json:inputs','simulation_only':True,
         'consumed_fs':len(events),'owned':sum(e['credit'] for e in events),
         'ignored_no_credit':sum(1-e['credit'] for e in events),
         'scope':'Derived from simulated actual TOP consume+registered credit. Conditional cases are not hardware causal evidence.',
         'metrics':r.get('metrics',[])[-20:]}
(a.run/'FS_SUMMARY.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False,indent=2))
