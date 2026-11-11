"""Native short leaf-only TD A/B synthesis; no production project or PHY run."""
from pathlib import Path
import argparse,subprocess,re,json,hashlib,time,sys
HERE=Path(__file__).resolve().parent;PROJECT=HERE.parents[2];REPO=PROJECT.parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--name',required=True);ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--candidate',type=Path,default=HERE/'evaluated/shared_raw10_frame_ingress.v')
    ap.add_argument('--reference',type=Path,help='measure this exact comparison source instead of archived ed50')
    ap.add_argument('--candidate-only',action='store_true',help='reuse the separately recorded baseline')
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]*',a.name)
    out=PROJECT/'tmp/area_ingress'/a.name;out.mkdir(parents=True,exist_ok=False)
    result=dict(status='RUNNING',td_root=str(a.td_root.resolve()),scope='tiny leaf raw gate A/B only',cases=[],pnr='NOT_RUN',bitgen='NOT_RUN',board='NOT_RUN')
    reference=HERE/'baseline/shared_raw10_frame_ingress.v'
    if a.reference is None:
        assert sha(reference)==json.loads((reference.parent/'MANIFEST.json').read_text())['sha256']
    else:
        reference=a.reference.resolve()
    start=time.monotonic()
    try:
        cases=[('optimized',a.candidate.resolve())]
        if not a.candidate_only:
            cases.insert(0,('base' if a.reference else 'ed50',reference))
        for variant,leaf in cases:
            case=out/variant;case.mkdir()
            snapshot=case/'shared_raw10_frame_ingress.v';snapshot.write_bytes(leaf.read_bytes())
            append=case/'raw10_append5.v';append.write_bytes((PROJECT/'src_fpga/rtl/raw10_append5.v').read_bytes())
            ports=snapshot.read_text().split(') (',1)[1].split('\n);',1)[0]
            declarations=[]
            for line in ports.splitlines():
                line=line.split('//')[0].strip()
                match=re.match(r'(input|output)\s+wire\s*(?:\[(\d+):(\d+)\])?',line)
                if not match:continue
                width=int(match[2])-int(match[3])+1 if match[2] else 1
                declarations.extend((name,match[1],width) for name in re.findall(r'\b[io]_[a-zA-Z0-9_]+',line))
            names=[name for name,direction,width in declarations]
            input_bits=sum(width for name,direction,width in declarations if direction=='input' and name not in ('i_clk','i_rst_n'))
            output_bits=sum(width for name,direction,width in declarations if direction=='output')
            padded=(output_bits+31)//32*32
            body=f'module ingress_probe(input wire i_clk,i_rst_n,load,input wire [31:0] stimulus_word,input wire [3:0] view,output wire [31:0] observe);\nreg [{input_bits-1}:0] stimulus;\nalways @(posedge i_clk) if(load)stimulus<={{stimulus[{input_bits-33}:0],stimulus_word}};\n'
            offset=0
            for name,direction,width in declarations:
                if name in ('i_clk','i_rst_n'):continue
                body+=f'wire [{width-1}:0] {name}'
                if direction=='input':body+=f'=stimulus[{offset}+:{width}]';offset+=width
                body+=';\n'
            output_names=[name for name,direction,width in declarations if direction=='output']
            body+=f'wire [{padded-1}:0] results={{{padded-output_bits}\'d0,'+','.join(output_names)+'};\nassign observe=results >> {view,5\'b0};\n'
            wrapper=case/'ingress_probe.v'
            wrapper.write_text(body+'shared_raw10_frame_ingress #(.WIDTH(1920),.HEIGHT(1080),.CONTEXT_ENABLE(1),.PAIR_METADATA_ENABLE(1),.SOURCE_TERMINAL_ENABLE(1),.EXTERNAL_SEQUENCE_ENABLE(1)) u_leaf(\n'+',\n'.join('.'+p+'('+p+')' for p in names)+'\n);\nendmodule\n')
            (case/'clock.sdc').write_text('create_clock -name pix -period 8.000 [get_ports {i_clk}]\n')
            script=case/'build.tcl'
            script.write_text('''import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project ingress_probe . -family ph1 -device PH1A90SEG324 -speed -2
top_module ingress_probe
foreach source {raw10_append5.v shared_raw10_frame_ingress.v ingress_probe.v clock.sdc} {add_files $source}
set_param -run syn_1 flow thread {2}
set_param -run syn_1 rtl min_control_set {2}
set_param -run syn_1 gate mapper_lut_delay {off}
set_param -run syn_1 gate multi_thread_mapping {partition}
set_param -run syn_1 gate pack_effort {medium}
set_param -run syn_1 gate map_mode {area_prior}
set_param -run syn_1 gate add_map_lut_struct {on}
close_project
open_project ingress_probe.al
launch_runs -step opt_gate syn_1
wait_run syn_1 -quiet
if {![file isfile ingress_probe_Runs/syn_1/.opt_gate.end.f] ||
    [llength [glob -nocomplain -directory ingress_probe_Runs/syn_1 .*.error.f]]} {
    error "incomplete native ingress synthesis"
}
close_project
open_project ingress_probe.al -noanalyze
open_run syn_1
report_area -io_info -file gate_reopened.area
close_project
puts "INGRESS_PROBE_SYNTHESIS_DONE"
exit 0
''')
            command=[sys.executable,'-B',str(REPO/'tools/run_td.py'),str(script),'--td-root',str(a.td_root),'--workdir',str(case),'--log',str(case/'wrapper.log')]
            row=dict(variant=variant,leaf_sha256=sha(snapshot),append_sha256=sha(append),wrapper_sha256=sha(wrapper),script_sha256=sha(script),command=command)
            result['cases'].append(row)
            r=subprocess.run(command,cwd=REPO,capture_output=True,text=True,errors='replace',timeout=180)
            (case/'launcher.log').write_text(r.stdout+r.stderr)
            row['exit_code']=r.returncode
            if r.returncode:raise RuntimeError(variant+': '+(r.stdout+r.stderr)[-5000:])
            row['status']='DONE';print(variant,'DONE',case,flush=True)
        result['status']='DONE_COMPARE_RAW_REPORTS'
    except Exception as exc:result.update(status='FAIL',error=str(exc));raise
    finally:
        result['elapsed_seconds']=round(time.monotonic()-start,3)
        (out/'qualification.json').write_text(json.dumps(result,indent=2)+'\n');print(out/'qualification.json',flush=True)
if __name__=='__main__':main()
