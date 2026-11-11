"""Fixed14df cycle miter for the one-bit delayed applied-bank enable."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess

HERE=Path(__file__).resolve().parent
CONTROL=HERE.parent
PROJECT=CONTROL.parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=PROJECT/'tmp/config_pending'/a.name;run.mkdir(parents=True,exist_ok=False)
    manifest=PROJECT/'SOURCE_MANIFEST.json'
    includes=[PROJECT/p for p in json.loads(manifest.read_text())['include_dirs']]
    fixed=HERE/'fixed14df_engine.v.txt';fixture=HERE/'fixed_ack_bench.sv.txt'
    reference=run/'timing_config_engine_reference.v'
    reference.write_text(fixed.read_text().replace('module mono_config_engine_v2 #(',
        'module timing_config_engine_reference #('),newline='\n')
    base=fixture.read_text().replace('module tb_mono_config_ack_pipeline;',
        'module timing_config_base #(parameter integer TRUSTED_COMMANDS=0)(output reg done=0);')
    base=base.replace('mono_config_engine_v2 #(.V2_SUPPORTED_MODES',
        'mono_config_engine_v2 #(.CFG_DIAG_ENABLE(1),.TRUSTED_COMMANDS(TRUSTED_COMMANDS),.V2_SUPPORTED_MODES')
    # R2 RAW protocol defines delta as low32 only. Keep the old fixture's
    # other legal configuration fields and its 2368 ACK bit mutations.
    base=base.replace("64'h800000019abcdef0","64'h000000009abcdef0")
    base=base.replace('    reg rst_n=0;', '''    reg rst_n=0;
    wire diag_observer_rst_n=rst_n;
    reg diag_source_fs=0;reg [15:0] diag_source_gates=0;
    wire [223:0] diag_data;''')
    base=base.replace('$finish;','done=1;')
    basepath=run/'timing_config_base.sv';basepath.write_text(base,newline='\n')
    template=CONTROL/'tb_timing_config_control.sv'
    bench=template.read_text().replace('timing_config_engine_reference #(.TRUSTED_COMMANDS(TRUSTED),',
        'timing_config_engine_reference #(.CFG_DIAG_ENABLE(1),.TRUSTED_COMMANDS(TRUSTED),')
    bench=bench.replace('    wire [5:0] ref_active_processing_enables;',
        '    wire [5:0] ref_active_processing_enables;wire [223:0] ref_diag_data;')
    bench=bench.replace('    integer checks=0,eligible_cycles=0,wait_entries=0,wait_exits=0;',
        '    integer pending_cycles=0;\n'
        '    integer checks=0,eligible_cycles=0,wait_entries=0,wait_exits=0;')
    bench=bench.replace('.active_processing_enables(ref_active_processing_enables));',
        '''.active_processing_enables(ref_active_processing_enables),
        .diag_observer_rst_n(base.diag_observer_rst_n),.diag_source_fs(base.diag_source_fs),
        .diag_source_gates(base.diag_source_gates),.diag_data(ref_diag_data));''')
    seam='            check(base.dut.frame_apply_eligible==='
    bench=bench.replace(seam,'''            check(base.dut.applied_view===reference_dut.applied,"effective applied owner exact every half-cycle");
            check(base.diag_data===ref_diag_data,"all diagnostic bits retain original milestone edges");
            if(base.dut.applied_write_pending)begin
                pending_cycles=pending_cycles+1;
                check(base.dut.state==0&&base.dut.tx_state==1&&!base.command_ready&&
                    !base.dut.rx_active&&!base.dut.rx_done,
                    "APPLIED first flit owns prepared until narrow pending copy retires");
            end
'''+seam)
    seam='                take_reply(2,17,1,32\'h9000+trial);'
    assert bench.count(seam)==1
    bench=bench.replace(seam,'''                // Noise on a blocked next PREPARE speculatively changes its
                // session copy on exactly the delayed applied-bank write edge.
                base.command_valid=1;base.command_data={8'h80,32'hcafebabe};
                @(posedge base.clk);@(negedge base.clk);base.command_valid=0;
'''+seam)
    bench=bench.replace('        check(eligible_cycles>10&&wait_entries>=11&&wait_exits>=11&&response_stalls>100,',
        '        check(pending_cycles>=5,"pending and blocked PREPARE overlap coverage");\n'
        '        check(eligible_cycles>10&&wait_entries>=11&&wait_exits>=11&&response_stalls>100,')
    bench=bench.replace('fixed f3fc9adb','fixed14df')
    benchpath=run/'tb_pending.sv';benchpath.write_text(bench,newline='\n')
    sources=[PROJECT/'src_fpga/rtl'/n for n in ['mono_config_legacy_scan_v1.v','mono_config_scan_v2.v',
        'cfg_diag_pixel.v','mono_config_engine_v2.v']]
    headers=[p for inc in includes for p in inc.glob('*.vh')]
    inputs=sources+headers+[manifest,template,fixed,fixture,Path(__file__)]
    result=dict(status='IN_PROGRESS',baseline_commit='14df01dcce',
        inputs=[dict(path=str(p),sha256=sha(p)) for p in inputs],commands=[],
        synthesis='NOT_RUN',physical='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    def call(exe,words):
        argv=[str(a.modelsim_bin/exe),*map(str,words)]
        r=subprocess.run(argv,cwd=run,capture_output=True,text=True,timeout=120,
            creationflags=subprocess.CREATE_NO_WINDOW)
        result['commands'].append(dict(argv=argv,exit_code=r.returncode))
        (run/(exe+'.console.log')).write_text(r.stdout+r.stderr)
        if r.returncode:raise RuntimeError(r.stdout[-10000:]+r.stderr[-2000:])
    try:
        call('vmap.exe',['-c']);call('vlib.exe',['work']);call('vmap.exe',['work','work'])
        inc=['+incdir+'+str(p) for p in includes]
        call('vlog.exe',['-quiet','-l','rtl.log',*inc,*sources,reference])
        call('vlog.exe',['-quiet','-sv','-l','bench.log',*inc,basepath,benchpath])
        call('vsim.exe',['-c','work.tb_timing_config_control','-l','run.log','-do',
            'onerror {quit -code 1}; run -all; quit -f'])
        log=(run/'run.log').read_text()
        assert 'RESULT: PASS timing_config_control_all' in log,log[-10000:]
        for n in ['rtl.log','bench.log','run.log']:
            assert not re.search(r'\*\*\s+(Warning|Error|Fatal):',(run/n).read_text()),n
        for row in result['inputs']:
            if Path(row['path'])!=manifest:assert sha(Path(row['path']))==row['sha256'],row['path']
        result.update(status='PASS',metrics=[s.strip('# ') for s in log.splitlines() if 'RESULT: PASS' in s])
        print('\n'.join(result['metrics']))
    except Exception as e:result.update(status='FAIL',error=str(e));raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Evidence',run)
if __name__=='__main__':main()
