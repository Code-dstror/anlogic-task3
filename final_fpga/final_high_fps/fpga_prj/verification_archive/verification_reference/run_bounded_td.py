"""Run one explicitly selected local TD operation with a process-tree deadline."""
import argparse, json, subprocess, sys, time
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--script',type=Path,required=True)
parser.add_argument('--td-root',required=True)
parser.add_argument('--log-dir',type=Path,required=True)
parser.add_argument('--seconds',type=int,default=180)
args=parser.parse_args()
root=Path(__file__).resolve().parents[3]
out=args.log_dir.resolve()
out.mkdir(parents=True,exist_ok=False)
script=args.script.resolve()
cmd=[sys.executable,'-B',str(root/'tools/run_td.py'),str(script),'--td-root',args.td_root,'--workdir',str(script.parent),'--log',str(out/'td.log')]
start=time.monotonic(); expired=False
with (out/'launcher.log').open('wb') as log:
    proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    try: code=proc.wait(timeout=args.seconds)
    except subprocess.TimeoutExpired:
        expired=True
        subprocess.run(['taskkill.exe','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=subprocess.STDOUT,timeout=5,check=False)
        code=proc.wait(timeout=5)
result={'command':cmd,'elapsed_s':round(time.monotonic()-start,3),'wall_budget_s':args.seconds,'exit_code':code,'timed_out':expired}
(out/'COMMAND.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
raise SystemExit(1 if expired else code)
