"""Short forced-metadata event miter for production quarter_bad predicate split."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--td-root',required=True,type=Path)
    ap.add_argument('--modelsim-bin',required=True,type=Path)
    ap.add_argument('--name',required=True)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/lane_metadata'/a.name;run.mkdir(parents=True,exist_ok=False)
    fixture=ROOT/'src_fpga/simulation/MAIN_FIXTURE.json';data=json.loads(fixture.read_text())
    sys.path.insert(0,str(ROOT/'src_fpga/simulation/autof21/core'))
    from run import closure
    groups=closure(data,['stage3_filter_color_analysis4'])
    rtl=ROOT/'src_fpga/rtl';ip=ROOT/'src_fpga/ip'
    sources=[p for group in groups.values() for p in group]
    sources+=[rtl/n for n in ['lane_sparse_serial4.v','lane_quarter_fifo4_to1.v',
        'lane_winner_pair_lutram.v','lane_ridge_candidates1_lutram.v']]
    sources+=[ip/'stage3/fdct_mac19s14s_z33s_p34_m1p1/RTL/fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v',
        ip/'stage3/fdct_mac19s14s_z33s_p34_m1p1/fdct_mac19s14s_z33s_p34_m1p1.v',
        ROOT/'src_fpga/simulation/assets/define.v',a.td_root/'sim_release/ph1/ph1_phy_gsr.v']
    sources=list(dict.fromkeys(p for p in sources if p.name not in ['lane_ridge_candidates4.v','lane_ridge_candidates1.v']))
    models=[a.td_root/p for p in data['models']];bench=HERE/'tb_metadata.sv'
    inputs=sources+models+[bench,fixture,Path(__file__)]
    result=dict(status='IN_PROGRESS',inputs=[dict(path=str(p),sha256=sha(p)) for p in inputs],
        commands=[],synthesis='NOT_RUN',physical='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    def call(label,exe,args):
        argv=[str(a.modelsim_bin/exe),*map(str,args)]
        r=subprocess.run(argv,cwd=run,capture_output=True,text=True,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
        result['commands'].append(dict(argv=argv,exit_code=r.returncode))
        (run/(label+'.console.log')).write_text(r.stdout+r.stderr)
        if r.returncode:raise RuntimeError(r.stdout[-10000:]+r.stderr[-1000:])
    try:
        call('vmap','vmap.exe',['-c'])
        for lib in ['work','ph1']:
            call('vlib_'+lib,'vlib.exe',[lib]);call('vmap_'+lib,'vmap.exe',[lib,lib])
        call('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        defs=['+define+fdct_mac19s14s_z33s_p34_m1p1_USE_'+n+'=1' for n in ['A','CE','PH1A','RST','Y','Z']]
        call('compile','vlog.exe',['-quiet','+define+PH1',*defs,'-timescale','1ns/1ps','-l','compile.log',*sources])
        call('bench','vlog.exe',['-quiet','-sv','-l','bench.log',bench])
        call('run','vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_metadata','-l','run.log',
            '-do','onerror {quit -code 1}; run -all; quit -f'])
        log=(run/'run.log').read_text();assert 'RESULT: PASS' in log,log[-10000:]
        assert not re.search(r'\*\* (Error|Fatal):',log),log[-10000:]
        for row in result['inputs']:assert sha(Path(row['path']))==row['sha256'],row['path']
        result.update(status='PASS',metrics=[s.strip('# ') for s in log.splitlines() if 'RESULT: PASS' in s])
        print('\n'.join(result['metrics']))
    except Exception as e:result.update(status='FAIL',error=str(e));raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Evidence',run)
if __name__=='__main__':main()
