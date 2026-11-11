"""Bounded one-thread A/B leaf SYN; production projects and RTL stay untouched."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]
BASE='ed50d4e7534b1574213d173e941dbfbcfdf20351'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def freeze(path,data):
    if path.exists():
        assert path.read_bytes()==data,'Refuse to rebind completed probe inputs: '+str(path)
    else:
        path.write_bytes(data)


def area(path):
    body=path.read_text(errors='replace')
    resources={}
    for key,label in [('slice','slice'),('ff','slice reg'),('eram','eram'),('dsp','dsp')]:
        match=re.search(r'^\s*#'+re.escape(label)+r'\*?\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%',body,re.M)
        assert match,(path,key)
        resources[key]=int(match[1])
    hierarchy=[]
    for line in body.splitlines():
        fields=[s.strip() for s in line.split('|')[1:-1]]
        if len(fields)>=7 and fields[2].isdigit():
            hierarchy.append(dict(instance=fields[0],module=fields[1],
                **dict(zip(['logic_lut','ripple','ff','eram','dsp'],map(int,fields[2:7])))))
    assert any(r['module']=='control_message_fifo_ip' for r in hierarchy)
    top=next(r for r in hierarchy if r['instance']=='top')
    leaf=next(r for r in hierarchy if r['module']=='control_message_fifo_ip')
    return dict(path=path.as_posix(),sha256=sha(path),resources=resources,
        hierarchy=hierarchy,leaf=leaf,
        harness_exclusive={key:top[key]-leaf[key] for key in ['logic_lut','ripple','ff','eram','dsp']})


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--width',type=int,default=545)
    ap.add_argument('--borrow',type=int,choices=[0,1],default=1)
    ap.add_argument('--resume',action='store_true',help='Reuse an already completed local leaf build after report-parser repair')
    a=ap.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    assert a.width>=40
    run=ROOT/'tmp/control_mux_area'/a.name
    run.mkdir(parents=True,exist_ok=a.resume)
    iw,ow=a.width+2,a.width+4
    harness=f'''module control_probe(
 input source_clk,sink_clk,source_rst_n,sink_rst_n,scan,
 input [31:0] din,output [31:0] dout);
 (* preserve="true" *) reg [{iw-1}:0] inputs;
 (* preserve="true" *) reg [{ow-1}:0] outputs;
 wire [{ow-1}:0] observed;
 always @(posedge source_clk)if(scan)inputs<={{inputs[{iw-33}:0],din}};
 always @(posedge sink_clk)if(scan)outputs<={{outputs[{ow-33}:0],32'd0}};else outputs<=observed;
 assign dout=outputs[{ow-1}-:32];
 control_message_fifo_ip #(.MESSAGE_WIDTH({a.width}),.BORROW_SOURCE({a.borrow})) u_fifo(
 .i_source_clk(source_clk),.i_source_rst_n(source_rst_n),.i_source_data(inputs[{a.width-1}:0]),
 .i_source_valid(inputs[{a.width}]),.o_source_ready(observed[{a.width}]),
 .o_source_reset_done(observed[{a.width+1}]),.i_sink_clk(sink_clk),.i_sink_rst_n(sink_rst_n),
 .o_sink_data(observed[{a.width-1}:0]),.o_sink_valid(observed[{a.width+2}]),
 .i_sink_ready(inputs[{a.width+1}]),.o_sink_reset_done(observed[{a.width+3}]));
endmodule
'''
    ip=ROOT/'src_fpga/ip/camera_control_fifo_40x512'
    adapter=ROOT/'src_fpga/rtl/control_fifo_40x512.v'
    sources=dict(old=subprocess.check_output(['git','show',BASE+':refactor/hdr_lane_sparse/src_fpga/rtl/control_message_fifo_ip.v'],cwd=REPO),
                 candidate=(ROOT/'src_fpga/rtl/control_message_fifo_ip.v').read_bytes())
    result=dict(status='IN_PROGRESS',scope='ISOLATED_LEAF_SYN_ONLY',reference_commit=BASE,
        width=a.width,borrow_source=a.borrow,td_root=a.td_root.resolve().as_posix(),threads=1,
        harness=dict(input_register_bits=iw,output_register_bits=ow,
            source_inputs='Every message bit, VALID and sink READY independently scan loaded',
            outputs='Every sink message bit and all four public READY/VALID/reset flags captured and shifted to dout',
            clocks='Separate source and sink ports; no timing exceptions added',sha256=hashlib.sha256(harness.encode()).hexdigest()),
        runs={},synthesis='NOT_RUN',PNR='NOT_RUN',physical_STA='NOT_RUN',bitgen='NOT_RUN',board='NOT_RUN')
    started=time.monotonic()
    try:
        for version,data in sources.items():
            directory=run/version;directory.mkdir(exist_ok=a.resume)
            leaf=directory/'control_message_fifo_ip.v';freeze(leaf,data)
            wrapper=directory/'control_probe.v';freeze(wrapper,harness.encode())
            sdc=directory/'clock.sdc';freeze(sdc,b'create_clock -name source -period 8.000 [get_ports source_clk]\ncreate_clock -name sink -period 8.000 [get_ports sink_clk]\n')
            inputs=[leaf,wrapper,sdc,adapter,*sorted(ip.rglob('*.v')),*sorted(ip.glob('*.xml'))]
            tcl=f'''cd {{{directory.as_posix()}}}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project control_probe . -family ph1 -device PH1A90SEG324 -speed -2
top_module control_probe
'''
            tcl+=''.join('add_files {'+p.as_posix()+'}\n' for p in [leaf,wrapper,sdc,adapter,ip/'camera_control_fifo_40x512.xml'])
            tcl+='''set_param -run syn_1 flow thread 1
set_param -run syn_1 rtl min_control_set 2
set_param -run syn_1 gate map_mode area_prior
set_param -run syn_1 gate add_map_lut_struct on
launch_runs -step opt_gate syn_1
wait_run syn_1
if {![file exists control_probe_Runs/syn_1/.opt_gate.end.f]} {error "CONTROL_PROBE_OPT_GATE_NOT_COMPLETE"}
report_run_param syn_1 -file native-syn.params
close_project
open_project control_probe.al -noanalyze
open_run syn_1
report_area -file reopened.area
close_project
puts "CONTROL_PROBE_NATIVE_REOPEN_DONE"
exit 0
'''
            script=directory/'probe.tcl';freeze(script,tcl.encode())
            inputs+=[script,Path(__file__)]
            identity=[dict(path=p.resolve().as_posix(),sha256=sha(p)) for p in inputs]
            command=[sys.executable,'-I','-B',str(REPO/'tools/run_td.py'),str(script),
                '--td-root',str(a.td_root.resolve()),'--workdir',str(directory),'--log',str(directory/'td.log')]
            record=dict(status='IN_PROGRESS',source_sha256=sha(leaf),command=command,inputs=identity)
            result['runs'][version]=record
            already_done=a.resume and (directory/'control_probe_Runs/syn_1/.opt_gate.end.f').is_file() and (directory/'reopened.area').is_file()
            if already_done:
                assert 'CONTROL_PROBE_NATIVE_REOPEN_DONE' in (directory/'td.log').read_text(errors='replace')
                record['stage_reused']='Completed local SYN/reopen; earlier result parser required optional-star correction'
                code=0
            else:
                with (directory/'console.log').open('w') as output:
                    proc=subprocess.Popen(command,cwd=REPO,stdout=output,stderr=subprocess.STDOUT)
                    try:code=proc.wait(timeout=120)
                    except subprocess.TimeoutExpired:
                        subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True)
                        raise RuntimeError(version+' exceeded bounded120s; owned process tree stopped')
            record['exit_code']=code
            assert code==0,(version,directory/'td.log')
            log=(directory/'td.log').read_text(errors='replace')
            assert 'CONTROL_PROBE_NATIVE_REOPEN_DONE' in log
            assert not list(directory.rglob('*.error.f'))
            assert re.search(r'^set_param flow thread 1\s*$',(directory/'native-syn.params').read_text(),re.M)
            for item in identity:assert sha(Path(item['path']))==item['sha256'],item['path']
            record.update(status='PASS',area={
                'raw_gate':area(directory/'control_probe_Runs/syn_1/control_probe_gate.area'),
                'reopened_synthesis':area(directory/'reopened.area')})
        old,new=(result['runs'][name] for name in ['old','candidate'])
        result['delta']={}
        for stage in old['area']:
            result['delta'][stage]=dict(
                resources={key:new['area'][stage]['resources'][key]-old['area'][stage]['resources'][key] for key in old['area'][stage]['resources']},
                leaf={key:new['area'][stage]['leaf'][key]-old['area'][stage]['leaf'][key] for key in ['logic_lut','ripple','ff','eram','dsp']})
        result.update(status='PASS',synthesis='PASS')
        print(json.dumps(result['delta'],indent=2))
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        result['elapsed_seconds']=round(time.monotonic()-started,3)
        (run/('RESULT_resume.json' if a.resume else 'RESULT.json')).write_text(json.dumps(result,indent=2)+'\n')
        print('Evidence',run)


if __name__=='__main__':main()
