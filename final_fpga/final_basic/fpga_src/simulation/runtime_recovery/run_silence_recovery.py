"""Actual candidate camera watchdog and guard; six explicit boundary stubs."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess, time
HERE=Path(__file__).resolve().parent

def header(text):
    start=text.index('module ')
    return text[start:text.index(');',start)+2]

def ports(text):
    clean=re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S)
    result=[]
    for match in re.finditer(r'\b(input|output|inout)\s+(?:wire\s+|reg\s+)?(?:\[[^\]]*\]\s*)?(.*?)(?=\b(?:input|output|inout)\b|\);)',clean,flags=re.S):
        result += [(match[1],name) for name in re.findall(r'[A-Za-z_]\w*',match[2])]
    return result

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True);ap.add_argument('--modelsim-bin',type=Path,required=True)
    ap.add_argument('--source-root',type=Path,required=True)
    ap.add_argument('--output-root',type=Path,required=True)
    args=ap.parse_args()
    if not re.fullmatch(r'[a-z0-9_]+',args.name):ap.error('unsafe name')
    run=args.output_root.resolve()/args.name
    run.mkdir(parents=True,exist_ok=False);identity=[]
    def frozen(name):
        original=args.source_root.resolve()/'src_fpga/rtl'/name
        data=original.read_bytes()
        path=run/'fixed'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        identity.append(dict(original=str(original),path=str(path),sha256=hashlib.sha256(data).hexdigest()))
        return path
    camera=frozen('real_hdr_camera_observe_axis.v');guard=frozen('production_source_identity_guard.v')
    stub_defs={
        'real_hdr_sensor_clock_mux.v':('',{'o_clk':'i_sdr_clk'}),
        'real_hdr_event_cdc.v':('',{}),
        'real_hdr_sensor_config.v':('',{'o_start_ready':"1'b1"}),
        'imx415_config.v':("reg tb_done=0;",{'o_done':'tb_done','o_xclr':"1'b1",'o_scl':"1'b1"}),
        'real_hdr_physical_csi_rx.v':('''reg tb_raw_valid=0,tb_sof=0,tb_delay_ready=0,tb_phy_ready=1;
            reg tb_event_valid=0,tb_identity_valid=1,tb_parser_fault=0;
            reg [1:0] tb_event_kind=0;''',{
            'o_raw_valid':'tb_raw_valid','o_raw_sof':'tb_sof','o_auto_delay_done':'tb_delay_ready',
            'o_phy_ready':'tb_phy_ready','m_frame_event_valid':'tb_event_valid',
            'm_frame_event_kind':'tb_event_kind','m_frame_event_identity_valid':'tb_identity_valid',
            'o_source_identity_fault':'tb_parser_fault','o_raw_identity_valid':'tb_identity_valid',
            'm_frame_event_ok':"1'b1",'o_hs_word_clk':'i_pixel_clk'}),
        'physical_camera_rgb_pipeline.v':('reg tb_ready=1;',{'o_raw_ready':'tb_ready',
            'o_frame_error':'i_raw_valid&&i_raw_abort','o_cropped_raw_abort':'i_raw_abort',
            'o_job_idle':"1'b1"})}
    bodies=[]
    for name,(declarations,assignments) in stub_defs.items():
        body=frozen(name).read_text(encoding='utf-8');head=header(body);head=re.sub(r'\boutput\s+reg\b','output wire',head)
        outs=[name for direction,name in ports(head) if direction=='output']
        bodies += [head,declarations]+['assign '+name+'='+assignments.get(name,"'0")+';' for name in outs]+['endmodule\n']
    stubs=run/'boundary_stubs.sv';stubs.write_text('\n'.join(bodies),encoding='utf-8',newline='\n')
    connections={'i_pixel_clk':'clk','i_sensor_clk':'clk','i_cfg_clk':'clk','i_hdr_mclk':'clk','i_ref_clk':'clk',
        'i_reset_n':'rst_n','i_processing_reset_n':'rst_n','i_clock_locked':"1'b1",'i_mode_quiet':"1'b1",
        'i_axis_tready':"1'b1",'i_rgb_tready':"1'b1",'m_frame_event_ready':"1'b1",
        'o_observe_raw_valid':'raw_valid','o_observe_raw_ready':'raw_ready','o_observe_receive_fault':'receive_fault',
        'o_phy_ready':'phy_ready','o_source_identity_fault':'parser_fault','m_frame_event_valid':'event_valid',
        'm_frame_event_kind':'event_kind','m_frame_event_identity_valid':'event_identity_valid',
        'o_config_done':'config_done','o_delay_ready':'delay_ready','o_mode_running':'mode_running','o_hdr_mode':'hdr_mode',
        'o_frame_error':'pipeline_abort'}
    instance='real_hdr_camera_observe_axis @PARAM@ camera(\n'+',\n'.join('.'+name+'('+connections.get(name,"'0" if direction=='input' else '')+')' for direction,name in ports(header(camera.read_text(encoding='utf-8'))))+'\n);'
    template=(HERE/'tb_silence_recovery.sv').read_text(encoding='utf-8')
    bench=run/'cfg_silence_benches.sv'
    bench.write_text('\n'.join(template.replace('@CAMERA@',instance.replace('@PARAM@',param))
        .replace('@TOP@',top).replace('@LIMIT@',str(limit)).replace('@DEFAULT@',str(default))
        for top,param,limit,default in [('tb_cfg_silence_small','#(.SILENCE_CYCLES(64))',64,0),
            ('tb_cfg_silence_default','',12500000,1)]),encoding='utf-8',newline='\n')
    result=dict(status='RUNNING',source_root=str(args.source_root.resolve()),frozen_inputs=identity,commands=[],
        simulation='RUNNING',synthesis='NOT_RUN',physical='NOT_RUN',timing='NOT_RUN',board='NOT_RUN',
        boundary_stubs=list(stub_defs),scope='Unmodified wrapper watchdog and guard, SDR actual reset condition; boundary modules replaced')
    def command(name,exe,argv):
        words=[str(args.modelsim_bin/exe)]+list(map(str,argv));result['commands'].append(words)
        start=time.monotonic();p=subprocess.run(words,cwd=run,text=True,errors='replace',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=45,creationflags=subprocess.CREATE_NO_WINDOW)
        (run/(name+'.console.log')).write_text(p.stdout)
        result.setdefault('elapsed_seconds',{})[name]=round(time.monotonic()-start,3)
        if p.returncode:raise RuntimeError(name+' '+str(p.returncode)+' '+p.stdout[-6000:])
    try:
        command('vmap','vmap.exe',['-c']);command('work','vlib.exe',['work'])
        command('compile','vlog.exe',['-quiet','-sv','-l','compile.log',camera,guard,stubs,bench])
        metrics=[]
        for top in ['tb_cfg_silence_small','tb_cfg_silence_default']:
            command(top,'vsim.exe',['-c','work.'+top,'-l',top+'.log','-do','run -all; quit -f'])
            text=(run/(top+'.log')).read_text(errors='replace')
            if 'RESULT: PASS '+top not in text:raise RuntimeError(text[-6000:])
            metrics += [x.strip('# ') for x in text.splitlines() if 'RESULT:' in x]
        for log in run.glob('*.log'):
            if re.search(r'\*\* (Warning|Error|Fatal):',log.read_text(errors='replace')):raise RuntimeError('unclassified diagnostic '+log.name)
        for row in identity:
            for field in ('original','path'):
                if hashlib.sha256(Path(row[field]).read_bytes()).hexdigest()!=row['sha256']:
                    raise RuntimeError('input changed: '+row[field])
        result.update(status='PASS',simulation='PASS',metrics=metrics);print('\n'.join(metrics))
    except Exception as error:result.update(status='FAIL',simulation='FAIL',error=str(error));raise
    finally:
        result['test_inputs']=[dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in [Path(__file__),HERE/'tb_silence_recovery.sv',stubs,bench]]
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
