"""Complete source-bound R3 ring miter with official TD2026.2 distributed RAM."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2];REPO=PROJECT.parents[1]
BASE='14df01dcce'
REL='refactor/dual_lane_s1/src_fpga/rtl/jpeg_frame_ring.v'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True);ap.add_argument('--td-root',type=Path,required=True)
    a=ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name):ap.error('unsafe name')
    run=PROJECT/'tmp/r4_ring_generation'/a.name;run.mkdir(parents=True,exist_ok=False)
    old=subprocess.check_output(['git','show',f'{BASE}:{REL}'],cwd=REPO)
    reference=run/'r4_ring_reference.v';reference.write_bytes(old.replace(b'module jpeg_frame_ring #(',b'module r4_ring_reference #(',1))
    header=re.sub(r'//[^\n]*','',old.decode().split('    localparam',1)[0])
    ports=[]
    for m in re.finditer(r'\b(input|output)\s+(?:wire|reg)\s*(\[[^\]]+\])?\s*(.*?)(?=\binput\b|\boutput\b|$)',header,re.S):
        direction,width,names=m.groups()
        for name in re.findall(r'\b[io]_\w+',names):ports.append((direction,width or '',name))
    if len(set(n for _,_,n in ports))!=len(ports) or len(ports)<140:raise RuntimeError('interface extraction')
    inputs=[(w,n) for d,w,n in ports if d=='input' and n!='i_clk'];outputs=[(w,n) for d,w,n in ports if d=='output']
    template=HERE/'r4_ring_generation_tb.sv';bench=template.read_text()
    declarations=[f'reg {w} {n};' for w,n in inputs]
    declarations += [f'wire {w} {prefix}_{n};' for w,n in outputs for prefix in ['dut','reference']]
    bench=bench.replace('__DECLARATIONS__','\n    '.join(declarations))
    for prefix,module in [('dut','DUT'),('reference','REFERENCE')]:
        connections=[f'.{n}({n if d=="input" else prefix+"_"+n})' for d,_,n in ports]
        bench=bench.replace('__'+module+'_PORTS__',',\n        '.join(connections))
        bench=bench.replace('__'+module+'_OUTPUTS__',','.join(prefix+'_'+n for _,n in outputs))
    bench=bench.replace('__INITIALIZE__','\n        '.join(n+'=0;' for _,n in inputs))
    benchpath=run/'r4_ring_tb.sv';benchpath.write_text(bench,newline='\n')
    rtl=PROJECT/'src_fpga/rtl'
    models=[a.td_root/'sim_release/ph1/ph1_logic_dram.v']
    sources=[rtl/'td_sdp_ram.v',rtl/'jpeg_ring_cold_bank.v',rtl/'jpeg_frame_ring.v',reference]
    identity=[{'path':str(p),'sha256':sha(p)} for p in models+sources+[template,Path(__file__)]]
    result={'status':'IN_PROGRESS','reference_commit':BASE,'reference_path':REL,
        'reference_sha256':hashlib.sha256(old).hexdigest(),'inputs':identity,
        'modelsim_bin':str(a.modelsim_bin),'td_root':str(a.td_root),'ports_compared':len(outputs),
        'physical':'NOT_RUN','timing':'NOT_RUN','board':'NOT_RUN'}
    def execute(exe,args):
        p=subprocess.run([str(a.modelsim_bin/exe)]+list(map(str,args)),cwd=run,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        if p.returncode:raise RuntimeError(p.stdout[-12000:])
    try:
        execute('vmap.exe',['-c']);execute('vlib.exe',['work']);execute('vmap.exe',['work','work'])
        execute('vlog.exe',['-quiet','-l','rtl.log']+models+sources)
        execute('vlog.exe',['-quiet','-sv','-l','bench.log',benchpath])
        execute('vsim.exe',['-c','work.r4_ring_generation_tb','-l','run.log','-do',
            'onerror {quit -code 1}; run -all; quit -f'])
        body=(run/'run.log').read_text()
        if 'RESULT: PASS r4_ring_generation_all' not in body:raise RuntimeError(body[-12000:])
        warnings=[]
        for name in ['rtl.log','bench.log','run.log']:
            for number,line in enumerate((run/name).read_text().splitlines(),1):
                if re.search(r'\*\*\s+(Error|Fatal):',line):raise RuntimeError('tool failure '+name+': '+line)
                if re.search(r'\*\*\s+Warning:',line):
                    # Official DRAM checks a padded filename part-select even
                    # for INIT_FILE="NONE"; no initialization file is read.
                    if not re.search(r'ph1_logic_dram\.v\(221\): \(vopt-2697\).*part-select into .INIT_FILE. is out of bounds',line):
                        raise RuntimeError('unclassified diagnostic '+name+': '+line)
                    warnings.append({'log':name,'line':number,'message':line})
        for row in identity:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('input changed '+row['path'])
        result['status']='PASS';result['accepted_vendor_warnings']=warnings
        result['metrics']=[s.strip('# ') for s in body.splitlines() if 'RESULT: PASS' in s]
        print('\n'.join(result['metrics']))
    except Exception as error:
        result['status']='FAIL';result['error']=str(error);raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print(run/'RESULTS.json')
if __name__=='__main__':main()
