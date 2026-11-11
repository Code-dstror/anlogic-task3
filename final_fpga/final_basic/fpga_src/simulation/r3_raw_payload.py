"""R1 full-module RAW data miter plus exhaustive selector/X-law proofs."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import itertools
import json
import re
import subprocess

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
REPO=PROJECT.parents[1]
BASE='d86edbed408230828e6cd8a887bceec80c242307'
BASE_PATH='refactor/hdr_jpeg_timing/src_fpga/rtl/shared_raw10_frame_ingress.v'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def selector_proof():
    count=0
    for state,fire,user,enable,abort,rawfire,sof,negative,stall,bad,pending,due,enddue,seen,okay in itertools.product(
        range(8),range(2),range(4),*[range(2)]*7,range(4),*[range(2)]*4):
        active=state in (1,2);wait=state==5
        allowed=state==0 or(fire and((state==3 and user==2)or(state==4 and user==3)))
        run=enable and not abort;start=allowed and run and rawfire and sof
        fault=abort or not enable or negative or stall or(rawfire and bad)
        context=not start and active and not fault and pending!=0
        stream=not start and active and not fault and pending==0 and due
        end=not start and((active and not fault and pending==0 and not due and enddue)or
            (wait and not abort and enable and not rawfire and not negative and seen and okay))
        original=tuple(map(bool,(start,context,stream and rawfire,stream and not rawfire,end)))
        healthy=active and not(negative or stall or(rawfire and bad))
        candidates=(allowed and rawfire and sof,healthy and pending!=0,
            healthy and pending==0 and due and rawfire,healthy and pending==0 and due and not rawfire,
            (healthy and pending==0 and not due and enddue)or(wait and not rawfire and not negative and seen and okay))
        assert original==tuple(bool(run and item) for item in candidates)
        count+=1

    def vand(*values):
        return 0 if 0 in values else 1 if all(x==1 for x in values) else None

    def vor(*values):
        return 1 if 1 in values else 0 if all(x==0 for x in values) else None

    def inv(value):
        return None if value is None else 1-value

    def eq(bits,number):
        if any(x is not None and x!=((number>>i)&1) for i,x in enumerate(bits)):
            return 0
        return None if None in bits else 1

    tri=0
    for state,fire,user,run,raw,sof in itertools.product(itertools.product([0,1,None],repeat=3),
        [0,1,None],itertools.product([0,1,None],repeat=2),*[ [0,1,None] ]*3):
        active=vor(eq(state,1),eq(state,2));wait=eq(state,5)
        allowed=vor(eq(state,0),vand(fire,vor(vand(eq(state,3),eq(user,2)),vand(eq(state,4),eq(user,3)))))
        start=vand(allowed,run,raw,sof)
        assert vand(active,inv(start))==active and vand(wait,inv(start))==wait
        tri+=1
    for enable,abort,rest in itertools.product([0,1,None],repeat=3):
        assert inv(vor(abort,inv(enable),rest))==vand(enable,inv(abort),inv(rest))
    for run,a,b,c,d in itertools.product([0,1,None],repeat=5):
        assert vand(run,vor(vand(a,b),vand(c,d)))==vor(vand(run,a,b),vand(run,c,d))
    return {'boolean_selector_vectors':count,'X_state_START_redundancy':tri,'X_DeMorgan':27,'X_distributivity':243}


STRICT_COMPARE=r'''
    task strict_compare;
        begin
            strict_checks=strict_checks+1;
            if(dut.axis_data_next!==ref_dut.axis_data_next)
                $fatal(1,"R3 RAW next128 mismatch id=%0d C/P/S/E=%0d/%0d/%0d/%0d state=%0d old=%h new=%h",ID,C,P,S,E,dut.state,ref_dut.axis_data_next,dut.axis_data_next);
            if({dut.state,dut.state_next,dut.pack_bytes,dut.pack_data,dut.pack_data_next,
                dut.context_pending,dut.source_identity,dut.source_seen,dut.source_ok,
                dut.axis_data,dut.axis_keep,dut.axis_last,dut.axis_user,dut.axis_valid,
                dut.axis_keep_next,dut.axis_last_next,dut.axis_user_next,dut.axis_valid_next,
                dut.token_start_due,dut.token_active,dut.token_fault_base,dut.token_fault,dut.token_raw_bad,
                dut.token_data_due,dut.token_end_due,dut.token_abort_due,
                dut.payload_context,dut.payload_data,dut.payload_end,dut.payload_abort,
                dut.reservoir_append,dut.reservoir_emit,dut.reservoir_clear}!==
               {ref_dut.state,ref_dut.state_next,ref_dut.pack_bytes,ref_dut.pack_data,ref_dut.pack_data_next,
                ref_dut.context_pending,ref_dut.source_identity,ref_dut.source_seen,ref_dut.source_ok,
                ref_dut.axis_data,ref_dut.axis_keep,ref_dut.axis_last,ref_dut.axis_user,ref_dut.axis_valid,
                ref_dut.axis_keep_next,ref_dut.axis_last_next,ref_dut.axis_user_next,ref_dut.axis_valid_next,
                ref_dut.token_start_due,ref_dut.token_active,ref_dut.token_fault_base,ref_dut.token_fault,ref_dut.token_raw_bad,
                ref_dut.token_data_due,ref_dut.token_end_due,ref_dut.token_abort_due,
                ref_dut.payload_context,ref_dut.payload_data,ref_dut.payload_end,ref_dut.payload_abort,
                ref_dut.reservoir_append,ref_dut.reservoir_emit,ref_dut.reservoir_clear})
                $fatal(1,"R3 RAW control/register/sideband mismatch id=%0d",ID);
        end
    endtask
    always @(negedge i_clk)begin #1;strict_compare();end
'''

TERMINAL_CASES=r'''
    task terminal_restart(input integer next_sequence);
        begin
            i_valid=0;i_sof=0;i_eol=0;i_source_valid=0;i_axis_tready=1;
            watchdog=0;
            while(!(dut_o_axis_tvalid&&(dut_o_axis_tuser==2||dut_o_axis_tuser==3)))begin
                cycle();watchdog=watchdog+1;if(watchdog>40)$fatal(1,"terminal wait id=%0d",ID);
            end
            i_axis_tready=0;repeat(3)cycle();
            i_external_sequence=next_sequence;i_valid=1;i_accept=1;i_enable=1;i_abort=0;
            i_sof=1;i_eol=GROUPS==1;i_data=40'hb1a2030405;i_axis_tready=1;
            cycle();
            for(g=1;g<GROUPS*H;g=g+1)begin
                i_valid=1;i_sof=0;i_eol=(g%GROUPS)==GROUPS-1;i_data=40'hb1a2030405+g;cycle();
            end
            i_valid=0;i_sof=0;i_eol=0;source_result(next_sequence,0);settle();
        end
    endtask
'''


def adapt_bench(body):
    old='parameter W=24,H=3,C=1,P=1,S=1,ID=0'
    assert body.count(old)==1
    body=body.replace(old,'parameter W=24,H=3,C=1,P=1,S=1,E=1,ID=0')
    assert body.count('.EXTERNAL_SEQUENCE_ENABLE(1)')==2
    body=body.replace('.EXTERNAL_SEQUENCE_ENABLE(1)','.EXTERNAL_SEQUENCE_ENABLE(E)')
    body=body.replace('    integer stalls=0, resets=0, n, g, seq, random_seed;',
        '    integer stalls=0, resets=0, n, g, seq, random_seed;\n    integer strict_checks=0,terminal_starts=0,watchdog=0;')
    body=body.replace('            @(posedge i_clk); #1;',
        '            @(posedge i_clk);if(i_rst_n&&dut.terminal_fire&&dut.token_start_due)terminal_starts=terminal_starts+1;#1;strict_compare();')
    body=body.replace('    task cycle;',STRICT_COMPARE+'\n    task cycle;')
    old='i_source_valid=1;i_source_sequence=sequence_id;i_source_ok=!bad;'
    assert body.count(old)==1
    body=body.replace(old,'i_source_valid=1;i_source_sequence=E?sequence_id:(ref_dut.source_identity[31:0]+(sequence_id-i_external_sequence));i_source_ok=!bad;')
    body=body.replace('if(bad_geometry && g==1)','if(bad_geometry && g==(GROUPS*H>1?1:0))')
    old='    initial begin\n        clear_input();reset_now();'
    assert body.count(old)==1
    body=body.replace(old,TERMINAL_CASES+'\n'+old)
    old='        // SOURCE mismatch is stale, never a completion; a true error aborts.'
    assert body.count(old)==1
    body=body.replace(old,r'''        // Held END and ABORT transfer on the same edge as a new real SOF.
        frame_pixels(40,0);source_result(40,0);terminal_restart(41);
        i_external_sequence=50;i_valid=1;i_accept=1;i_sof=1;i_eol=GROUPS==1;
        cycle();i_valid=0;i_sof=0;i_eol=0;i_abort=1;cycle();i_abort=0;terminal_restart(51);
'''+old)
    old='        done=1;'
    assert body.count(old)==1
    body=body.replace(old,r'''        if(terminal_starts<2)$fatal(1,"missing same-edge terminal+SOF id=%0d",ID);
        $display("R3_RAW_INTERNAL case=%0d C=%0d P=%0d S=%0d E=%0d strict_checks=%0d terminal_starts=%0d",ID,C,P,S,E,strict_checks,terminal_starts);
'''+old)
    head=body.split('module tb_raw_payload;',1)[0]
    cases=[]
    for context,pair in [(0,0),(1,0),(1,1)]:
        for source in [0,1]:
            for external in [0,1]:
                index=len(cases);w,h=[(4,1),(20,2),(24,3)][index%3]
                cases.append({'ID':index,'W':w,'H':h,'C':context,'P':pair,'S':source,'E':external})
    top='module tb_raw_payload;\n    wire [11:0] done;\n'
    for case in cases:
        top+='    raw_payload_case #('+','.join('.'+name+'('+str(value)+')' for name,value in case.items())+') case_'+str(case['ID'])+'(done['+str(case['ID'])+']);\n'
    top+='    initial begin wait(&done);$display("RESULT: PASS r3_raw_payload_all");$finish;end\nendmodule\n'
    return head+top,cases


def clean(text):
    return re.sub(r'\s+','',re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name',required=True)
    parser.add_argument('--modelsim-bin',type=Path,required=True)
    args=parser.parse_args()
    if not re.fullmatch(r'r3_raw_payload_[a-z0-9_]+',args.name):parser.error('fresh name must start r3_raw_payload_')
    run=PROJECT/'tmp/r3_raw_payload'/args.name;run.mkdir(parents=True,exist_ok=False)
    source=PROJECT/'src_fpga/rtl/shared_raw10_frame_ingress.v';append=PROJECT/'src_fpga/rtl/raw10_append5.v'
    raw=subprocess.check_output(['git','show',BASE+':'+BASE_PATH],cwd=REPO)
    old=raw.decode().replace('\r\n','\n');new=source.read_text()
    old_region=re.search(r'assign axis_data_next\s*=.*?;',old,re.S)
    new_region=re.search(r'wire data_run\s*=.*?assign axis_data_next\s*=.*?;',new,re.S)
    assert old_region and new_region
    assert clean(old[:old_region.start()]+old[old_region.end():])==clean(new[:new_region.start()]+new[new_region.end():]),'change outside data-only candidate expression'
    proof=selector_proof()
    fixture=HERE/'run_raw_payload.py';spec=importlib.util.spec_from_file_location('r3_frozen_raw_fixture',fixture)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    body,cases=adapt_bench(module.BENCH)
    ports=[]
    header=re.sub(r'//[^\n]*','',old.split('    localparam',1)[0])
    for line in header.splitlines():
        match=re.match(r'\s*(input|output)\s+(?:wire|reg)\s*(\[[^\]]+\])?\s*(.*)',line)
        if match:
            direction,width,names=match.groups()
            ports += [(direction,width or '',name) for name in re.findall(r'\b[io]_\w+',names)]
    assert len(ports)==45
    inputs=[(w,n) for d,w,n in ports if d=='input'];outputs=[(w,n) for d,w,n in ports if d=='output']
    declarations=[f'    reg {w} {n};' for w,n in inputs if n!='i_clk']
    declarations += [f'    wire {w} {prefix}_{n};' for w,n in outputs for prefix in ['dut','ref']]
    body=body.replace('__DECLARATIONS__','\n'.join(declarations))
    body=body.replace('__INITIALIZE__','\n'.join(f'            {n}=0;' for _,n in inputs if n!='i_clk'))
    controls=[n for _,n in outputs if n not in ['o_axis_tdata','o_axis_tkeep','o_axis_tlast','o_axis_tuser']]
    for prefix in ['dut','ref']:
        body=body.replace('__'+prefix.upper()+'_PORTS__',',\n'.join(f'        .{n}({n if d=="input" else prefix+"_"+n})' for d,_,n in ports))
        body=body.replace('__CONTROL_'+prefix.upper()+'__',','.join(prefix+'_'+n for n in controls))
    bench=run/'r3_raw_payload_tb.sv';bench.write_text(body,newline='\n')
    reference=run/'r3_raw_payload_reference.v'
    reference.write_text(old.replace('module shared_raw10_frame_ingress #(','module shared_raw10_frame_ingress_baseline #(',1),newline='\n')
    identity=[{'path':str(p),'sha256':sha(p)} for p in [source,append,fixture,Path(__file__),bench,reference]]
    result={'status':'IN_PROGRESS','inputs':identity,'baseline':{'commit':BASE,'path':BASE_PATH,'sha256':hashlib.sha256(raw).hexdigest()},
        'static_scope':'entire module token-identical except new data-only candidates/axis_data_next; all original payload/control/sideband/reset/always unchanged',
        'selector_proof':proof,'parameter_cases':cases,'new_state_bits':0,'latency_change_cycles':0,
        'synthesis':'NOT_RUN','physical_timing':'NOT_RUN','board':'NOT_RUN'}

    def command(name,exe,words):
        proc=subprocess.run([str(args.modelsim_bin/exe)]+list(map(str,words)),cwd=run,text=True,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,errors='replace')
        (run/(name+'.console.log')).write_text(proc.stdout)
        if proc.returncode:raise RuntimeError(name+' failed '+proc.stdout[-10000:])

    try:
        command('map','vmap.exe',['-c']);command('lib','vlib.exe',['work'])
        command('rtl','vlog.exe',['-quiet','-l','rtl.log',append,source,reference])
        command('bench','vlog.exe',['-quiet','-sv','-l','bench.log',bench])
        command('run','vsim.exe',['-c','work.tb_raw_payload','-l','run.log','-do','run -all;quit -f'])
        log=(run/'run.log').read_text()
        if 'RESULT: PASS r3_raw_payload_all' not in log:raise RuntimeError(log[-12000:])
        for filename in ['rtl.log','bench.log','run.log']:
            if re.search(r'\*\* (Warning|Error|Fatal):',(run/filename).read_text()):raise RuntimeError('diagnostic '+filename)
        for row in identity:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('executed source drift '+row['path'])
        metrics=[line.strip('# ') for line in log.splitlines() if 'RAW_PAYLOAD_PASS' in line or 'R3_RAW_INTERNAL' in line]
        assert len(metrics)==24
        result.update(status='PASS',metrics=metrics);print('\n'.join(metrics));print('SELECTOR_PROOF',proof)
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        (run/'r3_raw_payload_RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Results:',run/'r3_raw_payload_RESULTS.json')


if __name__=='__main__':
    main()
