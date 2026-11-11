"""Extract actual R3/R1 tag blocks; test them with real admission and builder."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
REPO=PROJECT.parents[1]
BASE='d86edbed408230828e6cd8a887bceec80c242307'
TOP_PATH='refactor/hdr_jpeg_timing/src_fpga/rtl/anlogic2026.v'
FIXTURE_PATH='refactor/hdr_jpeg_timing/src_fpga/simulation/control/tb_admission_restart.sv'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def actual_tag_block(text):
    candidates=[]
    for match in re.finditer(r'always\s*@\(posedge pixel_clk or negedge pixel_rst_n\)\s*begin',text):
        depth=1
        for token in re.finditer(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\bbegin\b|\bend\b',text[match.end():],re.S):
            word=token.group()
            if word=='begin':depth+=1
            elif word=='end':depth-=1
            if depth==0:
                body=text[match.start():match.end()+token.end()]
                if re.search(r'record_product_next_tag\s*<=\s*1\s*;',body):candidates.append(body)
                break
    if len(candidates)!=1:
        raise RuntimeError('expected one actual namespace reset/update block')
    return candidates[0]


def declarations(text,names,prefix=''):
    widths={}
    for match in re.finditer(r'\breg\s*(?:signed\s+)?(\[[^\]]+\])?\s*([^;\n]+);',text):
        for name in re.findall(r'\b[A-Za-z_]\w*\b',match[2]):
            if name in names:widths[name]=match[1] or ''
    if set(widths)!=set(names):raise RuntimeError('missing assigned-register declarations '+str(set(names)-set(widths)))
    return '\n'.join(f'    reg {widths[name]} {prefix}{name};' for name in sorted(names))+'\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name',required=True)
    parser.add_argument('--modelsim-bin',type=Path,required=True)
    args=parser.parse_args()
    if not re.fullmatch(r'r3_[a-z0-9_]+',args.name):parser.error('fresh run name must start r3_')
    run=PROJECT/'tmp/r3_tags'/args.name;run.mkdir(parents=True,exist_ok=False)
    top=PROJECT/'src_fpga/rtl/anlogic2026.v';support=HERE/'r3_tag_support.vh'
    original_top=subprocess.check_output(['git','show',BASE+':'+TOP_PATH],cwd=REPO).decode().replace('\r\n','\n')
    original_fixture=subprocess.check_output(['git','show',BASE+':'+FIXTURE_PATH],cwd=REPO).decode().replace('\r\n','\n')
    current=top.read_text();new=actual_tag_block(current);old=actual_tag_block(original_top)
    assigned=lambda body:set(re.findall(r'\b([A-Za-z_]\w*)\s*(?:\[[^\]]+\])?\s*<=',body))
    actual_names,reference_names=assigned(new),assigned(old)
    assert {'record_product_advance_pending','record_writer_advance_pending'}<=actual_names
    assert actual_names-reference_names=={'record_product_advance_pending','record_writer_advance_pending'}
    renamed=re.sub(r'\b('+'|'.join(sorted(reference_names,key=len,reverse=True))+r')\b',lambda m:'r1_'+m[0],old)
    (run/'r3_actual_tag_logic.vh').write_text(new+'\n',newline='\n')
    (run/'r3_reference_tag_logic.vh').write_text(renamed+'\n',newline='\n')
    (run/'r3_tag_declarations.vh').write_text(declarations(current,actual_names)+
        declarations(original_top,reference_names,'r1_'),newline='\n')
    restart=re.search(r'always\s*@\(posedge pixel_clk\)\s*begin\s*if\(admission_state_idle\)\s*admitted_restart\s*<=\s*job_restart;\s*end',current)
    if restart is None:raise RuntimeError('original restart ownership block changed')
    (run/'r3_actual_restart_latch.vh').write_text(restart[0]+'\n',newline='\n')
    bench=original_fixture.replace('module tb_admission_restart;',
        '`include "pcie_protocol_v1.vh"\nmodule r3_tb_tag_allocation #(parameter integer R3_STATS_ENABLE=1);\n    wire record_product_available;')
    for before,after in [('"actual_restart_latch.vh"','"r3_actual_restart_latch.vh"'),
        ('.i_credit_grant(grant)', '.i_credit_grant(grant&&record_product_available)'),
        ('    task automatic check(', '    `include "r3_tag_support.vh"\n    task automatic check('),
        ('wait(admission_state_idle);','wait(admission_state_idle&&record_product_available);')]:
        if bench.count(before)!=1:raise RuntimeError('fixed fixture seam changed: '+before)
        bench=bench.replace(before,after)
    bench,count=re.subn(r'\$display\("RESULT: PASS ADMISSION_RESTART[^;]+;',
        'r3_extra_cases();\n        $display("RESULT: PASS r3_tag_allocation_all");',bench,flags=re.S)
    assert count==1
    test=run/'r3_tb_tag_allocation.sv';test.write_text(bench,newline='\n')
    rtl=PROJECT/'src_fpga/rtl';sources=[rtl/'jpeg_frame_admission.v',rtl/'frame_record_extension_builder.v']
    manifest=json.loads((PROJECT/'SOURCE_MANIFEST.json').read_text())
    includes=[PROJECT/directory for directory in manifest['include_dirs']]
    headers=[directory/'pcie_protocol_v1.vh' for directory in includes if (directory/'pcie_protocol_v1.vh').exists()]
    assert len(headers)==1
    generated=sorted(run.glob('r3_*.vh'))+[test]
    inputs=[top,support,Path(__file__)]+sources+headers+generated
    identity=[{'path':str(path),'sha256':sha(path)} for path in inputs]
    result={'status':'IN_PROGRESS','baseline':{'commit':BASE,'top_path':TOP_PATH,'fixture_path':FIXTURE_PATH,
        'reference_block_sha256':hashlib.sha256(old.encode()).hexdigest()},'inputs':identity,
        'actual_block_sha256':hashlib.sha256(new.encode()).hexdigest(),'tag_block':'full actual top always block, not a rewritten counter model',
        'scope':'Actual admission FSM, actual top allocation logic, actual1024-bit extension builder; capacity of other consumers modeled ready.',
        'permitted_difference':'Only unowned next counters may lag R1 by their pending increment; allocated tags/exhaustion/valid metadata/handshake cycles must be exact.',
        'synthesis':'NOT_RUN','physical_timing':'NOT_RUN','board':'NOT_RUN'}

    def command(name,exe,words):
        proc=subprocess.run([str(args.modelsim_bin/exe)]+list(map(str,words)),cwd=run,
            text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,errors='replace')
        (run/(name+'.console.log')).write_text(proc.stdout)
        if proc.returncode:raise RuntimeError(name+' failed '+proc.stdout[-10000:])

    try:
        command('map','vmap.exe',['-c']);command('lib','vlib.exe',['work'])
        inc=['+incdir+'+str(directory) for directory in [run,HERE]+includes]
        command('rtl','vlog.exe',['-quiet','-l','rtl.log']+inc+sources)
        command('bench','vlog.exe',['-quiet','-sv','-l','bench.log']+inc+[test])
        metrics=[]
        for stats in [0,1]:
            name='r3_stats'+str(stats)
            command(name,'vsim.exe',['-c','work.r3_tb_tag_allocation','-gR3_STATS_ENABLE='+str(stats),
                '-l',name+'.log','-do','run -all;quit -f'])
            log=(run/(name+'.log')).read_text()
            if 'RESULT: PASS r3_tag_allocation_all' not in log:raise RuntimeError(log[-12000:])
            metrics.extend(line.strip('# ') for line in log.splitlines() if 'RESULT: PASS r3_tags ' in line)
        for name in ['rtl.log','bench.log','r3_stats0.log','r3_stats1.log']:
            if re.search(r'\*\* (Warning|Error|Fatal):',(run/name).read_text()):raise RuntimeError('diagnostic '+name)
        for row in identity:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('executed source drift '+row['path'])
        result.update(status='PASS',metrics=metrics);print('\n'.join(metrics))
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        (run/'r3_RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Results:',run/'r3_RESULTS.json')


if __name__=='__main__':
    main()
