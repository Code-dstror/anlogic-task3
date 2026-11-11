"""Bounded worker-only A/B synthesis for sharing row-choice and emit registers."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys,time
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
REPO=ROOT.parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def candidate(body):
    replacements={
        '    reg [26:0] best,chosen0,chosen1;':
        '''    reg [26:0] best;
    // Row choice and sorting/emission occupy disjoint phases. Reuse these
    // two payload registers instead of copying chosen0/1 into emit0/1.
    reg [26:0] emit0,emit1,emit2;
    wire [26:0] chosen0=emit0,chosen1=emit1;''',
        '    reg [26:0] emit0,emit1,emit2;\n    reg [8:0] emit_y;':
        '    reg [8:0] emit_y;',
        'best<=0;chosen0<=0;chosen1<=0;scan_phase<=0;':
        'best<=0;emit0<=0;emit1<=0;scan_phase<=0;',
        'if(pass==0)begin chosen0<=scan_best;pass<=scan_best[26]?2:1;end':
        'if(pass==0)begin emit0<=scan_best;pass<=scan_best[26]?2:1;end',
        'else if(pass==1)begin chosen0<=scan_best;pass<=2;end':
        'else if(pass==1)begin emit0<=scan_best;pass<=2;end',
        'else if(pass==2)begin chosen1<=scan_best;pass<=3;end':
        'else if(pass==2)begin emit1<=scan_best;pass<=3;end',
        'emit0<=chosen0;emit1<=chosen1;emit2<=scan_best;':
        'emit2<=scan_best;',
    }
    for old,new in replacements.items():
        assert body.count(old)==1,old
        body=body.replace(old,new)
    return body
def area(p):
    body=p.read_text(errors='replace');rows=[]
    for line in body.splitlines():
        f=[s.strip() for s in line.split('|')[1:-1]]
        if len(f)>=8 and f[2].isdigit():
            rows.append(dict(instance=f[0],module=f[1],**dict(zip(
                ['logic','ripple','ff','eram','dsp','dram'],map(int,f[2:8])))))
    return dict(path=str(p),sha256=sha(p),worker=next(r for r in rows if r['module']=='lane_ridge_candidates1_lutram'))
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True);ap.add_argument('--td-root',required=True,type=Path)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/lane_area'/a.name;run.mkdir(parents=True,exist_ok=False)
    rtl=ROOT/'src_fpga/rtl';source=rtl/'lane_ridge_candidates1_lutram.v';body=source.read_text()
    sys.path.insert(0,str(ROOT/'src_fpga/simulation/timing'))
    from r3_run_zero_latency import header
    _,_,ports=header(body,'lane_ridge_candidates1_lutram')
    def width(w):
        if not w:return 1
        lo,hi=map(int,re.findall(r'\d+',w));return lo-hi+1
    ni=sum(width(w) for d,w,n in ports if d=='input' and n not in ('clk','rst_n'))
    no=sum(width(w) for d,w,n in ports if d=='output')
    harness=f'''module lane_probe(input clk,rst_n,scan,input [31:0] din,output [31:0] dout);
(* preserve="true" *) reg [{ni-1}:0] inputs;
(* preserve="true" *) reg [{no-1}:0] outputs;
wire [{no-1}:0] observed;
always @(posedge clk)if(scan)inputs<={{inputs[{ni-33}:0],din}};
always @(posedge clk)if(scan)outputs<={{outputs[{no-33}:0],32'd0}};else outputs<=observed;
assign dout=outputs[{no-1}-:32];
'''
    offset=0
    for d,w,n in ports:
        if n in ('clk','rst_n'):continue
        if d=='input':
            harness+=f'wire {w} {n}=inputs[{offset}+:{width(w)}];\n';offset+=width(w)
        else:harness+=f'wire {w} {n};\n'
    harness+='assign observed={'+','.join(n for d,w,n in ports if d=='output')+'};\n'
    harness+='lane_ridge_candidates1_lutram u_worker('+','.join(f'.{n}({n})' for d,w,n in ports)+');\nendmodule\n'
    dependencies=[rtl/n for n in ['lane_winner_pair_lutram.v','lane_candidate_store.v','td_sdp_ram40.v']]
    dependencies+=[ROOT/'src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v']
    result=dict(status='IN_PROGRESS',scope='ISOLATED_WORKER_SYN_ONLY',td_root=str(a.td_root),
        baseline_source_sha256=sha(source),threads=4,clock_period_ns=8.0,harness_input_ff=ni,harness_output_ff=no,
        cases={},physical='NOT_RUN',physical_timing='NOT_RUN',bitgen='NOT_RUN',board='NOT_RUN')
    started=time.monotonic()
    try:
        for name,text in [('r3_baseline',body),('shared_emit',candidate(body))]:
            case=run/name;case.mkdir();leaf=case/source.name;leaf.write_text(text,newline='\n')
            wrapper=case/'lane_probe.v';wrapper.write_text(harness,newline='\n')
            sdc=case/'clock.sdc';sdc.write_text('create_clock -name pix -period 8.000 [get_ports clk]\n')
            script=case/'build.tcl'
            tcl=f'''cd {{{case.as_posix()}}}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project lane_probe . -family ph1 -device PH1A90SEG324 -speed -2
top_module lane_probe
'''
            tcl+=''.join('add_files {'+p.as_posix()+'}\n' for p in [leaf,wrapper,sdc,*dependencies])
            tcl+='''set_param -run syn_1 flow thread 4
set_param -run syn_1 rtl min_control_set 2
set_param -run syn_1 gate map_mode area_prior
set_param -run syn_1 gate multi_thread_mapping partition
set_param -run syn_1 gate add_map_lut_struct on
launch_runs -step opt_gate syn_1
wait_run syn_1
if {![file exists lane_probe_Runs/syn_1/.opt_gate.end.f]} {error "LANE_PROBE_OPT_GATE_INCOMPLETE"}
report_run_param syn_1 -file native-syn.params
close_project
open_project lane_probe.al -noanalyze
open_run syn_1
report_area -file reopened.area
close_project
puts "LANE_PROBE_NATIVE_REOPEN_DONE"
exit 0
'''
            script.write_text(tcl,newline='\n')
            inputs=[leaf,wrapper,sdc,script,*dependencies,Path(__file__)]
            ident=[dict(path=str(p),sha256=sha(p)) for p in inputs]
            command=[sys.executable,str(REPO/'tools/run_td.py'),str(script),'--td-root',str(a.td_root),
                '--workdir',str(case),'--log',str(case/'td.log')]
            row=dict(status='IN_PROGRESS',command=command,inputs=ident);result['cases'][name]=row
            with (case/'console.log').open('w') as out:
                proc=subprocess.Popen(command,cwd=REPO,stdout=out,stderr=subprocess.STDOUT)
                try:code=proc.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True)
                    raise RuntimeError(name+' exceeded bounded120s; owned tree stopped')
            assert code==0,(name,case/'td.log')
            assert 'LANE_PROBE_NATIVE_REOPEN_DONE' in (case/'td.log').read_text(errors='replace')
            assert not list(case.rglob('*.error.f'))
            for r in ident:assert sha(Path(r['path']))==r['sha256'],r['path']
            row.update(status='PASS',raw_gate=area(case/'lane_probe_Runs/syn_1/lane_probe_gate.area'),
                reopened=area(case/'reopened.area'))
            print(name,json.dumps(row['reopened']['worker']),flush=True)
        old,new=[result['cases'][n] for n in ['r3_baseline','shared_emit']]
        result['delta']={stage:{k:new[stage]['worker'][k]-old[stage]['worker'][k]
            for k in ['logic','ripple','ff','eram','dsp','dram']} for stage in ['raw_gate','reopened']}
        result.update(status='PASS');print(json.dumps(result['delta']),flush=True)
    except Exception as e:result.update(status='FAIL',error=str(e));raise
    finally:
        result['elapsed_seconds']=round(time.monotonic()-started,3)
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n');print('Evidence',run,flush=True)
if __name__=='__main__':main()
