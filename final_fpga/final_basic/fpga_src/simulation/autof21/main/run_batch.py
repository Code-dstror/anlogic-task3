"""Event-wait long MAIN plus independent full-HD F21 history numerics.

Launch only after the candidate source is frozen. This worker waits on children
and completion futures; it never polls logs, processes, GitHub or the TD server.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
SIM=ROOT/'src_fpga/simulation'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',required=True,type=Path)
    ap.add_argument('--modelsim-bin',required=True,type=Path)
    args=ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,28}',args.name):ap.error('invalid batch name')
    batch=ROOT/'tmp/autof21/batch'/args.name
    batch.mkdir(parents=True,exist_ok=False)
    path=batch/'batch.json'
    report=dict(status='RUNNING',worker_pid=os.getpid(),started=time.time(),cases=[],command=sys.argv,
                wait_policy='subprocess.run + as_completed events; no polling',
                synthesis='NOT_RUN',physical='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    common=['--td-root',str(args.td_root),'--modelsim-bin',str(args.modelsim_bin)]
    cases=[]
    for tag,mode,extra in [('sdr','sdr',[]),('recovery','sdr',['--runtime-recovery','full']),('hdr','hdr',[])]:
        name=f'auto_{args.name}_{tag}'
        run=ROOT/'tmp/main'/name
        oracle=ROOT/'tmp/main'/(name+'_oracle')
        commands=[[sys.executable,'-B','-u',str(SIM/'run_main.py'),'--name',name,'--mode',mode,
                   '--readonly-uart',*common,*extra],
                  [sys.executable,'-B','-u',str(SIM/'check_main.py'),'--mode',mode,
                   '--run-directory',str(run),'--output-directory',str(oracle),
                   *(['--runtime-recovery'] if extra else [])]]
        cases.append(dict(tag=tag,commands=commands,qualification=str(run/'qualification.json'),oracle=str(oracle/'RESULTS.json')))
    history_name=f'auto_{args.name}_history'
    cases.append(dict(tag='f21_history',commands=[[sys.executable,'-B','-u',str(HERE/'run_history.py'),
        '--name',history_name,'--full-hd',*common]],
        qualification=str(ROOT/'tmp/autof21/history'/history_name/'qualification.json')))
    def case(row):
        row=dict(row,status='RUNNING',started=time.time(),console=str(batch/(row['tag']+'.console.log')))
        with Path(row['console']).open('w',encoding='utf-8') as stream:
            for index,command in enumerate(row['commands']):
                done=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
                if done.returncode:
                    row.update(status='FAIL',command_index=index,exit_code=done.returncode);break
            else:row['status']='PASS'
        row['finished']=time.time()
        return row
    # Run the smaller full-HD history job first; limit simultaneous ModelSim
    # instances to the previously qualified local three-process budget.
    cases=[cases[-1],*cases[:-1]]
    report['cases_planned']=cases
    report['max_parallel']=3
    path.write_text(json.dumps(report,indent=2)+'\n')
    with ThreadPoolExecutor(max_workers=3) as pool:
        for completed in as_completed([pool.submit(case,row) for row in cases]):
            row=completed.result();report['cases'].append(row)
            path.write_text(json.dumps(report,indent=2)+'\n')
            print(row['tag'],row['status'],flush=True)
    report.update(status='PASS' if all(row['status']=='PASS' for row in report['cases']) else 'FAIL',finished=time.time())
    path.write_text(json.dumps(report,indent=2)+'\n')
    print('AUTOF21_LONG_BATCH',report['status'],path,flush=True)
    return report['status']!='PASS'


if __name__=='__main__':sys.exit(main())
