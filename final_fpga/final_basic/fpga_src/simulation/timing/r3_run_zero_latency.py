"""Source-bound R1/current whole-module miters for three zero-cycle changes."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]
BASE='d86edbed408230828e6cd8a887bceec80c242307'
TARGETS=['full_filter_multiscale4','stage3_lane_candidates_terminal4','preprocess_dehaze_map_qualified']
WRAPPER='stage3_filter_color_analysis4'


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def clean(s):return re.sub(r'/\*.*?\*/|//[^\n]*','',s,flags=re.S)
def matching(s,start):
    depth=0
    for index in range(start,len(s)):
        if s[index]=='(':depth+=1
        elif s[index]==')':
            depth-=1
            if depth==0:return index
    raise ValueError('Unbalanced module header')


def header(source,name):
    body=clean(source);m=re.search(r'\bmodule\s+'+name+r'\b',body);at=m.end()
    while body[at].isspace():at+=1
    parameter='';parameters=[]
    if body[at]=='#':
        start=body.index('(',at);end=matching(body,start);parameter=body[at:end+1]
        parameters=re.findall(r'\b(\w+)\s*=(?!=)',parameter);at=end+1
    start=body.index('(',at);end=matching(body,start);port_text=body[start+1:end]
    ports=[];direction='';width=''
    for part in port_text.split(','):
        part=part.strip();d=re.match(r'(input|output)\b\s*',part)
        if d:
            direction=d.group(1);part=part[d.end():]
            part=re.sub(r'^(?:(?:wire|reg|signed)\s+)+','',part)
            w=re.match(r'(\[[^\]]+\])\s*',part);width=w.group(1) if w else ''
            if w:part=part[w.end():]
        assert direction and re.fullmatch(r'\w+',part),part
        ports.append((direction,width,part))
    return parameter,parameters,ports


def make_miter(run,name,short,body_file,overrides):
    source=(ROOT/'src_fpga/rtl'/f'{name}.v').read_text();param,params,ports=header(source,name)
    output=[p for p in ports if p[0]=='output'];connections=lambda prefix:','.join(
        '.'+n+'('+('ref_'+n if d=='output' and prefix else n)+')' for d,w,n in ports)
    forwards='#('+','.join('.'+p+'('+p+')' for p in params)+')' if params else ''
    declarations=',\n'.join(d+' wire '+w+' '+n for d,w,n in ports)
    compare='{'+','.join(n for d,w,n in output)+'} !== {'+','.join('ref_'+n for d,w,n in output)+'}'
    monitor=''
    if name=='preprocess_dehaze_map_qualified':
        monitor='''
        if(dut.state==dut.IDLE&&dut.owned)$fatal(1,"R3 invalid IDLE owner invariant");
        if(dut.owned&&dut.owned_context!==baseline.owned_context)$fatal(1,"R3 owned context changed");
'''
    miter='module r3_miter_'+short+' '+param+' (\n'+declarations+'\n);\n'
    miter+='\n'.join('wire '+w+' ref_'+n+';' for d,w,n in output)+'\n'
    miter+=name+' '+forwards+' dut('+connections(False)+');\n'
    miter+='r3_ref_'+name+' '+forwards+' baseline('+connections(True)+');\n'
    miter+='integer r3_checks=0;\nalways @(posedge clk)if(rst_n)begin #1; r3_checks=r3_checks+1;\n'
    miter+='if('+compare+')begin\n'
    for d,w,n in output:miter+='if('+n+'!==ref_'+n+')$display("R3 OUTPUT '+n+' differs new=%h old=%h",'+n+',ref_'+n+');\n'
    miter+='$fatal(1,"R3 '+short+' visible outputs differ");end\n'+monitor+'end\nendmodule\n'
    miter_path=run/f'r3_miter_{short}.sv';miter_path.write_text(miter)
    body=body_file.read_text();prefix='module r3_tb_'+short+';\n'
    if short=='lane':prefix+='localparam integer STRIPS=1;\n';body=body.replace('localparam integer STRIPS=1;','')
    for d,w,n in ports:prefix+=('reg ' if d=='input' else 'wire ')+w+' '+n+('=0' if d=='input' else '')+';\n'
    prefix+='always #4 clk=~clk;\n'
    chosen='#('+','.join('.'+p+'('+str(v)+')' for p,v in overrides.items())+')' if overrides else ''
    prefix+='r3_miter_'+short+' '+chosen+' device(.*);\n'
    tb=run/f'r3_tb_{short}.sv';tb.write_text(prefix+body+'\nendmodule\n')
    return [miter_path,tb,body_file]


def source_closure(fixture):
    paths=list(dict.fromkeys(ROOT/r['path'] for group in fixture['groups'].values() for r in group if 'path' in r))
    mapping={};bodies={}
    for p in paths:
        if p.suffix not in ('.v','.sv') or '.enc.' in p.name:continue
        body=p.read_text(errors='replace')
        if '`pragma protect begin_protected' in body:mapping[p.stem]=p;bodies[p]='';continue
        body=clean(body);bodies[p]=body
        for module in re.findall(r'\bmodule\s+(\w+)',body):mapping[module]=p
    selected=set();queue=[WRAPPER,'preprocess_dehaze_map_qualified']
    while queue:
        module=queue.pop();p=mapping[module]
        if p in selected:continue
        selected.add(p);words=set(re.findall(r'\b\w+\b',bodies[p]));queue += [n for n in mapping if n in words and mapping[n] not in selected]
    return {name:[ROOT/r['path'] for r in group if 'path' in r and ROOT/r['path'] in selected]
            for name,group in fixture['groups'].items()}


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',required=True,type=Path);ap.add_argument('--modelsim-bin',required=True,type=Path)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/r3_zero_latency'/a.name;run.mkdir(parents=True,exist_ok=False)
    originals={};baseline_files=[];origins=[]
    for module in TARGETS+[WRAPPER]:
        path='refactor/hdr_jpeg_timing/src_fpga/rtl/'+module+'.v'
        raw=subprocess.check_output(['git','show',BASE+':'+path],cwd=REPO);originals[module]=raw.decode()
        text=raw.decode()
        for old in TARGETS+[WRAPPER]:text=re.sub(r'\b'+old+r'\b','r3_ref_'+old,text)
        target=run/('r3_ref_'+module+'.v');target.write_text(text);baseline_files.append(target)
        origins.append({'commit':BASE,'path':path,'sha256':hashlib.sha256(raw).hexdigest()})
    # Explicitly prove that candidate winner data/coordinate functions were not edited.
    f22=(ROOT/'src_fpga/rtl/full_filter_multiscale4.v').read_text()
    block=lambda t:re.search(r'function \[55:0\] summarize;.*?endfunction',t,re.S).group()
    assert block(f22)==block(originals['full_filter_multiscale4'])
    f23=(ROOT/'src_fpga/rtl/stage3_lane_candidates_terminal4.v').read_text()
    block=lambda t:re.search(r'        wire low_first =.*?        wire \[12:0\] vector_peak_pixel_x =[^;]+;',t,re.S).group()
    assert block(f23)==block(originals['stage3_lane_candidates_terminal4'])
    generated=[]
    generated += make_miter(run,WRAPPER,'filter',HERE/'r3_filter_body.vh',{})
    generated += make_miter(run,'stage3_lane_candidates_terminal4','lane',HERE/'r3_lane_body.vh',{'STRIPS':1,'MONO_PRESET':0,'FULLHEIGHT_ROI_ENABLE':0})
    generated += make_miter(run,'preprocess_dehaze_map_qualified','map',HERE/'r3_map_body.vh',{'SOURCE_WIDTH':120,'SOURCE_HEIGHT':120,'FIXED_CONFIG_SESSION_ENABLE':1})
    fixture_path=ROOT/'src_fpga/simulation/MAIN_FIXTURE.json';fixture=json.loads(fixture_path.read_text());groups=source_closure(fixture)
    models=[a.td_root/p for p in fixture['models']];groups['compile.args'].insert(0,a.td_root/'sim_release/ph1/ph1_phy_gsr.v')
    compile_generated=[p for p in generated if p.suffix=='.sv'];groups['compile.args']+=baseline_files+compile_generated
    inputs=set(models+[Path(__file__),fixture_path]+generated)
    for group in groups.values():inputs.update(group)
    includes=[ROOT/p for p in fixture['include_dirs']];queue=list(inputs);visited=set()
    while queue:
        p=queue.pop()
        if p in visited:continue
        visited.add(p)
        if p.suffix in ('.v','.sv','.vh'):
            for name in re.findall(r'`include\s+"([^"]+)"',p.read_text(errors='replace')):
                q=next((x for x in [p.parent/name,*[d/name for d in includes]] if x.is_file()),None)
                if q and q not in inputs:inputs.add(q);queue.append(q)
    identity=[{'path':p.resolve().as_posix(),'sha256':sha(p)} for p in sorted(inputs)]
    report={'status':'IN_PROGRESS','baseline':origins,'inputs':identity,'scope':__doc__,'winner_data_trees_unchanged':True,
            'synthesis':'NOT_RUN','physical':'NOT_RUN','board':'NOT_RUN','tests':[]}
    def execute(exe,args):
        result=subprocess.run([str(a.modelsim_bin/exe),*[str(x) for x in args]],cwd=run,capture_output=True,text=True,errors='replace')
        if result.returncode:raise RuntimeError(result.stdout[-12000:]+result.stderr[-1000:])
    try:
        execute('vmap.exe',['-c'])
        for lib in ['work','ph1']:execute('vlib.exe',[lib]);execute('vmap.exe',[lib,lib])
        execute('vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        defs=['PH1','C15_F23_FULLHEIGHT_PROFILE=1']+['fdct_mac19s14s_z33s_p34_m1p1_USE_'+n+'=1' for n in ['A','CE','PH1A','RST','Y','Z']]
        for name,group in groups.items():
            if not group:continue
            args=['-quiet','-work','work','-l',name+'.log','-timescale','1ns/1ps']+(['-sv'] if name=='compile.args' else [])
            execute('vlog.exe',args+['+define+'+d for d in defs]+['+incdir+'+p.as_posix() for p in includes]+group)
            assert not re.search(r'\*\* (?:Warning|Error|Fatal):',(run/(name+'.log')).read_text(errors='replace'))
        for name in ['lane','filter','map']:
            execute('vsim.exe',['-c','-voptargs=+acc','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.r3_tb_'+name,
                '-l',name+'.log','-do','onerror {quit -code 1}; run -all; quit -f'])
            body=(run/(name+'.log')).read_text(errors='replace');assert 'RESULT: PASS R3_' in body and not re.search(r'\*\* (?:Error|Fatal):',body),body[-12000:]
            owned=[x for x in body.splitlines() if '** Warning:' in x and '/src_fpga/rtl/' in x.replace('\\','/')]
            assert not owned,owned
            metrics=[x for x in body.splitlines() if 'RESULT: PASS' in x];print('\n'.join(metrics))
            report['tests'].append({'name':name,'status':'PASS','metrics':metrics,'vendor_warning_count':sum('** Warning:' in x for x in body.splitlines())})
        for row in identity:assert sha(Path(row['path']))==row['sha256'],row['path']
        report['status']='PASS'
    except Exception as e:report.update(status='FAIL',error=str(e));raise
    finally:(run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n');print('Evidence',run)


if __name__=='__main__':main()
