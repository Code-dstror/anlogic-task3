"""Complete R3/current config engine miter plus four-flit cursor collision checks."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
REPO=PROJECT.parents[1]
BASE='946d970c2f660eaf7dad85eea91931ec76c12200'
PREFIX='refactor/hdr_jpeg_timing/src_fpga/'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True);a=ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name):ap.error('unsafe name')
    run=PROJECT/'tmp/r4_config_tx'/a.name;run.mkdir(parents=True,exist_ok=False)
    baselines=[]
    def frozen(path):
        body=subprocess.check_output(['git','show',f'{BASE}:{path}'],cwd=REPO)
        baselines.append({'commit':BASE,'path':path,'sha256':hashlib.sha256(body).hexdigest()})
        return body.decode().replace('\r\n','\n')
    reference=run/'r4_config_reference.v'
    reference.write_text(frozen(PREFIX+'rtl/mono_config_engine_v2.v').replace(
        'module mono_config_engine_v2 #(','module timing_config_engine_reference #('),newline='\n')
    base=frozen('refactor/hdr_jpeg/src_fpga/simulation/control/tb_mono_config_ack_pipeline.sv')
    substitutions={
        'module tb_mono_config_ack_pipeline;':'module timing_config_base #(parameter integer TRUSTED_COMMANDS=0)(output reg done=0);',
        'mono_config_engine_v2 #(.V2_SUPPORTED_MODES':'mono_config_engine_v2 #(.TRUSTED_COMMANDS(TRUSTED_COMMANDS),.V2_SUPPORTED_MODES',
        '$finish;':'done=1;'}
    for old,new in substitutions.items():
        if base.count(old)!=1:raise RuntimeError('fixed base seam '+old)
        base=base.replace(old,new)
    # The original ACK fixture predates F04: its high delta word was nonzero,
    # which both fixed R3 and current correctly reject. Supply a legal delta
    # while retaining every original ACK bit mutation and identity assertion.
    old="extension[191:128]=64'h800000019abcdef0;"
    if base.count(old)!=1:raise RuntimeError('F04 legal fixture seam')
    base=base.replace(old,"extension[191:128]=64'h000000009abcdef0;")
    basepath=run/'r4_config_base.sv';basepath.write_text(base,newline='\n')
    bench=frozen(PREFIX+'simulation/control/tb_timing_config_control.sv')
    seam='    initial begin\n        wait(base_done);'
    if bench.count(seam)!=1:raise RuntimeError('test task seam')
    extra=HERE/'r4_config_tx_cases.vh'
    bench=bench.replace(seam,extra.read_text()+'\n'+seam)
    seam='        check(eligible_cycles>10&&wait_entries>=11&&wait_exits>=11&&response_stalls>100,'
    if bench.count(seam)!=1:raise RuntimeError('test call seam')
    bench=bench.replace(seam,'        r4_extra_tests();\n'+seam)
    seam='            check(base.dut.frame_apply_eligible==='
    if bench.count(seam)!=1:raise RuntimeError('state invariant seam')
    bench=bench.replace(seam,
        '            check(base.dut.tx_state===reference_dut.tx_state,"decoded cursor/owner exactly match R3 state");\n'
        '            check(base.dut.tx_active||base.dut.tx_index==0,"unowned cursor is zero");\n'+seam)
    benchpath=run/'r4_config_tb.sv';benchpath.write_text(bench,newline='\n')
    manifest=PROJECT/'SOURCE_MANIFEST.json'
    includes=[PROJECT/p for p in json.loads(manifest.read_text())['include_dirs']]
    sources=[PROJECT/'src_fpga/rtl'/name for name in ['mono_config_legacy_scan_v1.v','mono_config_scan_v2.v','mono_config_engine_v2.v']]
    headers=[p for d in includes for p in d.glob('*.vh')]
    inputs=sources+headers+[extra,Path(__file__)]
    identity=[{'path':str(p),'sha256':sha(p)} for p in inputs]
    # Exhaustive legal transition proof for each of the five old states.
    transitions=0
    for old in range(5):
        for ready in range(2):
            for reply in range(2):
                space=old==0 or (old==4 and ready)
                if reply and not space:continue
                old_next=(0 if old==4 else old+1) if old and ready else old
                if reply:old_next=1
                active=old!=0;index=old-1 if active else 0
                if active and ready:
                    index=(index+1)%4
                    if index==0:active=False
                if reply:active=True
                assert (index+1 if active else 0)==old_next
                assert active or index==0
                transitions+=1
    result={'status':'IN_PROGRESS','baseline':baselines,'inputs':identity,
        'fixture_adaptation':'pre-F04 ACK fixture delta high32 cleared; all other words/checks retained',
        'cursor_transition_cases':transitions,'modelsim_bin':str(a.modelsim_bin),
        'physical':'NOT_RUN','timing':'NOT_RUN','board':'NOT_RUN'}
    def execute(exe,args):
        p=subprocess.run([str(a.modelsim_bin/exe)]+list(map(str,args)),cwd=run,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        if p.returncode:raise RuntimeError(p.stdout[-12000:])
    try:
        execute('vmap.exe',['-c']);execute('vlib.exe',['work']);execute('vmap.exe',['work','work'])
        inc=['+incdir+'+str(d) for d in includes]
        execute('vlog.exe',['-quiet','-l','rtl.log']+inc+sources+[reference])
        execute('vlog.exe',['-quiet','-sv','-l','bench.log']+inc+[basepath,benchpath])
        execute('vsim.exe',['-c','work.tb_timing_config_control','-l','run.log','-do',
            'onerror {quit -code 1}; run -all; quit -f'])
        body=(run/'run.log').read_text()
        if 'RESULT: PASS timing_config_control_all' not in body or body.count('RESULT: PASS r4_config_tx_seams')!=2:
            raise RuntimeError(body[-12000:])
        for name in ['rtl.log','bench.log','run.log']:
            if re.search(r'\*\*\s+(Warning|Error|Fatal):',(run/name).read_text()):raise RuntimeError('unclassified diagnostic '+name)
        for row in identity:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('input changed '+row['path'])
        result['status']='PASS';result['metrics']=[s.strip('# ') for s in body.splitlines() if 'RESULT: PASS' in s]
        print('\n'.join(result['metrics']))
    except Exception as error:
        result['status']='FAIL';result['error']=str(error);raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print(run/'RESULTS.json')
if __name__=='__main__':main()
