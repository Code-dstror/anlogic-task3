"""Official-model A/B: fixed6f8 FF winner versus asynchronous LUTRAM winner."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--td-root',required=True,type=Path)
    ap.add_argument('--modelsim-bin',required=True,type=Path)
    ap.add_argument('--name',required=True)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/lane_winner_lutram'/a.name;run.mkdir(parents=True,exist_ok=False)
    result=dict(simulation='IN_PROGRESS',suite_selection='pair_and_fixed_worker_AB',td_root=str(a.td_root),commands=[],inputs=[],synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    model=ROOT/'verification_reference/lane'
    fixture=model/'c1_row_vectors.json'
    vectors=json.loads(fixture.read_text())['vectors']
    samples=[];expected=[];sizes=[]
    for v in vectors:
        for q,x,y,f in zip(v['q'],v['gx'],v['gy'],v['flags']):
            samples.append((x&2047)|((y&2047)<<11)|(q<<22)|(f<<30))
        points=[int.from_bytes(bytes.fromhex(h),'little') for h in v['expected_hex']]
        sizes.append(len(points));expected+=points+[0]*(303-len(points))
    sys.path.insert(0,str(model))
    import c1_reference as c1
    import numpy as np
    # Raw, bounded quarter events isolate the unchanged ridge mathematics and
    # the r2 register-boundary compaction. Golden points use frozen C1 code.
    directed=[]
    q=np.zeros((270,480),np.uint8);gx=np.zeros((270,480),np.int16)
    gy=np.zeros((270,480),np.int16);flags=np.zeros((270,480),np.uint8)
    q[200]=10
    for x,dx in [(46,100),(48,-100),(50,120),(52,110),(53,-110),(58,-120)]:gx[200,x]=dx
    for x in [47,52,54]:q[200,x]=200;flags[200,x]=1
    selected=c1.select_rows(c1.ridge_candidates(q,gx,gy,flags))
    assert [(p['native_x'],p['width_quarter']) for p in selected]==[(188,2),(216,8)]
    for x in range(480):samples.append((int(gx[200,x])&2047)|((int(gy[200,x])&2047)<<11)|(int(q[200,x])<<22)|(int(flags[200,x])<<30))
    points=[int.from_bytes(c1.pack_point(p),'little') for p in selected]
    expected+=points+[0]*(303-len(points));sizes.append(len(points))
    directed.append(dict(name='center_inverse_same_batch',row=200,expected=selected))
    q=np.zeros((270,480),np.uint8);gx=np.zeros((270,480),np.int16)
    gy=np.zeros((270,480),np.int16);flags=np.zeros((270,480),np.uint8)
    q[200:203]=10
    for row in [200,201]:
        gx[row,478]=100;gx[row,479]=-100;q[row,478]=200;flags[row,478]=1
    gx[201,0]=110;gx[201,2]=-110;q[201,1]=200;flags[201,1]=2
    gx[202,1]=110;gx[202,2]=-110;q[202,1]=200;flags[202,1]=2
    selected=c1.select_rows(c1.ridge_candidates(q,gx,gy,flags))
    assert [(p['native_x'],p['native_y']) for p in selected]==[(1914,800),(4,804),(1914,804),(6,808)]
    for row in range(200,203):
        for x in range(480):samples.append((int(gx[row,x])&2047)|((int(gy[row,x])&2047)<<11)|(int(q[row,x])<<22)|(int(flags[row,x])<<30))
        points=[int.from_bytes(c1.pack_point(p),'little') for p in selected] if row==200 else []
        expected+=points+[0]*(303-len(points));sizes.append(len(points))
    directed.append(dict(name='mixed_EoL478_head0_and_head1',rows=[200,201,202],expected=selected))
    # Three separated bins really exercise all303 RAM entries on 101 ROI rows.
    # The original same-bin-four vector produces two, not three, row winners.
    q=np.zeros((270,480),np.uint8);gx=np.zeros((270,480),np.int16)
    gy=np.zeros((270,480),np.int16);flags=np.zeros((270,480),np.uint8)
    q[200]=10
    for left,strength in [(46,100),(146,120),(246,140)]:
        gx[200,left]=strength;gx[200,left+2]=-strength
        q[200,left+1]=200;flags[200,left+1]=1
    selected=c1.select_rows(c1.ridge_candidates(q,gx,gy,flags))
    assert [(p['native_x'],p['strength']) for p in selected]==[(188,100),(588,120),(988,140)]
    for x in range(480):samples.append((int(gx[200,x])&2047)|((int(gy[200,x])&2047)<<11)|(int(q[200,x])<<22)|(int(flags[200,x])<<30))
    points=[int.from_bytes(c1.pack_point(p),'little') for p in selected]
    expected+=points+[0]*(303-len(points));sizes.append(len(points))
    directed.append(dict(name='three_bins_dense303',row=200,repeated_rows=[169,269],expected_per_row=selected,expected_frame_count=303))
    for name,peaks,bright in [
        ('adjacent_even_odd_bins',[(38,100),(39,-100),(41,120),(43,-120)],[38,42]),
        ('back_to_back_samebin',[(46,100),(48,-100),(50,150),(52,-150),(54,200),(56,-200)],[47,51,55])]:
        q=np.zeros((270,480),np.uint8);gx=np.zeros((270,480),np.int16)
        gy=np.zeros((270,480),np.int16);flags=np.zeros((270,480),np.uint8);q[200]=10
        for x,dx in peaks:gx[200,x]=dx
        for x in bright:q[200,x]=200;flags[200,x]=1
        selected=c1.select_rows(c1.ridge_candidates(q,gx,gy,flags))
        assert [p['native_x'] for p in selected]==([168] if name=='adjacent_even_odd_bins' else [220])
        for x in range(480):samples.append((int(gx[200,x])&2047)|((int(gy[200,x])&2047)<<11)|(int(q[200,x])<<22)|(int(flags[200,x])<<30))
        points=[int.from_bytes(c1.pack_point(p),'little') for p in selected]
        expected+=points+[0]*(303-len(points));sizes.append(len(points))
        directed.append(dict(name=name,row=200,expected=selected))
    (run/'r2_directed_vectors.json').write_text(json.dumps(directed,indent=2)+'\n')
    for name,vals,digits in [('samples',samples,8),('expected',expected,10),('sizes',sizes,8)]:
        (run/(name+'.hex')).write_text(''.join(f'{v:0{digits}x}\n' for v in vals))
    rtl=ROOT/'src_fpga/rtl';ip=ROOT/'src_fpga/ip'
    fixed=rtl/'lane_ridge_candidates1.v'
    normalized=hashlib.sha256(fixed.read_bytes().replace(b'\r\n',b'\n')).hexdigest()
    if normalized != '3d0992209d5a571b653d38c70be5281fec800ea3ae3d12661265c0d41e7a4f24':
        raise RuntimeError('frozen C1 reference changed')
    result['baseline_commit']='6f8a7004cf8f45e022e826c56b6d40d6fdea7c66'
    result['baseline_source_blob_sha256']=sha(fixed)
    sources=[rtl/n for n in ['td_sdp_ram40.v','lane_candidate_store.v','lane_winner_pair_lutram.v','lane_ridge_candidates1_lutram.v']]
    sources += [fixed,ip/'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',a.td_root/'sim_release/ph1/ph1_phy_gsr.v']
    benches=sorted(HERE.glob('tb_*.sv'))
    models=[a.td_root/p for p in json.loads((ROOT/'src_fpga/simulation/MAIN_FIXTURE.json').read_text())['models']]
    for p in sources+benches+models+[fixture,model/'c1_reference.py',Path(__file__)]:result['inputs'].append(dict(path=str(p.resolve()),sha256=sha(p)))
    result['fixtures']=[dict(path=p.name,sha256=sha(p)) for p in sorted(run.glob('*.hex'))]
    def call(label,exe,args,timeout=120):
        argv=[str(a.modelsim_bin/exe),*map(str,args)]
        r=subprocess.run(argv,cwd=run,capture_output=True,text=True,errors='replace',timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
        result['commands'].append(dict(argv=argv,exit_code=r.returncode))
        (run/(label+'.console.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
        if r.returncode:raise RuntimeError(label+': '+r.stdout[-10000:]+r.stderr[-1000:])
    try:
        call('vmap','vmap.exe',['-c'])
        for lib in ['work','ph1']:
            call('vlib_'+lib,'vlib.exe',[lib]);call('vmap_'+lib,'vmap.exe',[lib,lib])
        call('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        call('compile','vlog.exe',['-quiet','+define+PH1','-timescale','1ns/1ps','-l','compile.log',*sources])
        call('benches','vlog.exe',['-quiet','-sv','-l','benches.log',*benches])
        for bench in benches:
            call(bench.stem,'vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.'+bench.stem,'-l',bench.stem+'.log','-do','onerror {quit -code 1}; run -all; quit -f'],180)
            log=(run/(bench.stem+'.log')).read_text(errors='replace')
            assert 'RESULT: PASS' in log and not re.search(r'\*\* (Error|Fatal):',log),log[-10000:]
            result.setdefault('results',[]).extend(s.strip('# ') for s in log.splitlines() if 'RESULT: PASS' in s)
        warnings=[s for p in run.glob('*.log') for s in p.read_text(errors='replace').splitlines() if '** Warning:' in s]
        # Exact official NONE-initializer branches warn on their dormant wide
        # string slice; payload remains intentionally uninitialized/valid-masked.
        unexpected=[s for s in warnings if not re.search(r'ph1_logic_eram\.v\(1287\).*INIT_FILE.*out of bounds|ph1_logic_dram\.v\(221\).*INIT_FILE.*out of bounds|(?:vopt-2241|vsim-3015).*ecc_[sd]biterrinj',s)]
        assert not unexpected,unexpected
        for row in result['inputs']:assert sha(Path(row['path']))==row['sha256'],row['path']
        result.update(simulation='PASS',warnings=warnings)
        print('\n'.join(result['results']))
    except Exception as e:result.update(simulation='FAIL',error=str(e));raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
        print('Evidence',run)
if __name__=='__main__':main()
