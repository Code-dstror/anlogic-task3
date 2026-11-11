"""Run two source-bound MAINs and record completion events, never poll progress.

The 15-minute thread heartbeat reads the record; this worker only waits for the
two child process exits. It does not query or control any server or board.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

PROJECT=Path(__file__).resolve().parents[3]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source',required=True)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    ap.add_argument('--record',type=Path,required=True)
    a=ap.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}',a.source) or not re.fullmatch(r'[a-z][a-z0-9_]{0,32}',a.name):
        ap.error('fixed source/name required')
    path=a.record.resolve();path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists():raise ValueError('Do not overwrite existing completion record')
    record={'source_commit':a.source,'started_utc_unix':time.time(),'pid':os.getpid(),
            'status':'IN_PROGRESS','mode':'COMPLETION_EVENTS_NOT_PROGRESS_POLLING','runs':{}}
    def save():
        pending=path.with_suffix('.next.json')
        pending.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
        os.replace(pending,path)
    children={};streams=[]
    for mode in ['hdr','sdr']:
        name=mode+'_'+a.name
        run=PROJECT/'tmp/main'/name
        if run.exists():raise ValueError('Run already exists: '+str(run))
        cmd=[sys.executable,'-B',str(PROJECT/'src_fpga/simulation/run_main.py'),
             '--mode',mode,'--name',name,'--td-root',str(a.td_root),
             '--modelsim-bin',str(a.modelsim_bin),'--readonly-uart']
        output=path.parent/(name+'.console.txt')
        stream=output.open('x',encoding='utf-8');streams.append(stream)
        child=subprocess.Popen(cmd,cwd=PROJECT,stdout=stream,stderr=subprocess.STDOUT,
            creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        children[mode]=child
        record['runs'][mode]={'name':name,'pid':child.pid,'command':cmd,
            'run':str(run),'qualification':str(run/'qualification.json'),
            'source_identity':str(run/'source_identity.json'),'console':str(output),'status':'IN_PROGRESS'}
    save()
    # Completion waits are event-driven. No log-tail, file polling or status RPC.
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures={pool.submit(child.wait):mode for mode,child in children.items()}
        for future in concurrent.futures.as_completed(futures):
            mode=futures[future];code=future.result();row=record['runs'][mode]
            qpath=Path(row['qualification'])
            qual=json.loads(qpath.read_text()) if qpath.is_file() else None
            row.update(exit_code=code,finished_utc_unix=time.time(),qualification_result=qual,
                status='PASS' if code==0 and qual and qual.get('status')=='PASS_'+mode.upper()+'_MAIN' else 'FAIL')
            if row['status']=='FAIL':record['status']='FAIL'
            save()
    for stream in streams:stream.close()
    record['status']='PASS' if all(x['status']=='PASS' for x in record['runs'].values()) else 'FAIL'
    record['finished_utc_unix']=time.time();save()
    return 0 if record['status']=='PASS' else 1

if __name__=='__main__':sys.exit(main())
