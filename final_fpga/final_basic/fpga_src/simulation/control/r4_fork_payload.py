"""Source-bound R3/current whole-module fork payload ownership equivalence."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
REPO=PROJECT.parents[1]
BASE='946d970c2f660eaf7dad85eea91931ec76c12200'
REL='refactor/hdr_jpeg_timing/src_fpga/rtl/stage3_stream_fork2.v'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',required=True,type=Path)
    a=ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name):ap.error('unsafe name')
    run=PROJECT/'tmp/r4_fork'/a.name;run.mkdir(parents=True,exist_ok=False)
    old=subprocess.check_output(['git','show',f'{BASE}:{REL}'],cwd=REPO)
    text,n=re.subn(r'\bmodule\s+stage3_stream_fork2\b','module r4_fork_reference',old.decode())
    if n!=1:raise RuntimeError('fixed reference module identity')
    reference=run/'r4_fork_reference.v';reference.write_text(text,newline='\n')
    source=REPO/REL;bench=HERE/'r4_fork_payload_tb.sv'
    identity=[{'path':str(p),'sha256':sha(p)} for p in [source,bench,Path(__file__)]]
    result={'status':'IN_PROGRESS','reference_commit':BASE,'reference_path':REL,
        'reference_sha256':hashlib.sha256(old).hexdigest(),'inputs':identity,
        'modelsim_bin':str(a.modelsim_bin),'timing':'NOT_RUN','physical':'NOT_RUN','board':'NOT_RUN'}
    def execute(exe,args):
        p=subprocess.run([str(a.modelsim_bin/exe)]+list(map(str,args)),cwd=run,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        if p.returncode:raise RuntimeError(p.stdout[-9000:])
    try:
        execute('vmap.exe',['-c']);execute('vlib.exe',['work']);execute('vmap.exe',['work','work'])
        execute('vlog.exe',['-quiet','-l','rtl.log',source,reference])
        execute('vlog.exe',['-quiet','-sv','-l','bench.log',bench])
        execute('vsim.exe',['-c','work.r4_fork_payload_tb','-l','run.log','-do',
            'onerror {quit -code 1}; run -all; quit -f'])
        body=(run/'run.log').read_text()
        if 'RESULT: PASS r4_fork_all' not in body:raise RuntimeError(body[-9000:])
        for name in ['rtl.log','bench.log','run.log']:
            if re.search(r'\*\*\s+(Warning|Error|Fatal):',(run/name).read_text()):
                raise RuntimeError('unclassified diagnostic in '+name)
        for row in identity:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('input changed '+row['path'])
        result['status']='PASS';result['metrics']=[s.strip('# ') for s in body.splitlines() if 'RESULT: PASS' in s]
        print('\n'.join(result['metrics']))
    except Exception as error:
        result['status']='FAIL';result['error']=str(error);raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print(run/'RESULTS.json')
if __name__=='__main__':main()
