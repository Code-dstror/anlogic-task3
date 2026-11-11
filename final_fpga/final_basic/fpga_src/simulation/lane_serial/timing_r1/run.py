"""Source-bound C1 serial-lane candidate with installed TD2026.2 ERAM/DSP models."""
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
    ap.add_argument('--only',choices=['all','leaf','shared','fifo_stall'],default='all',help='select focused leaves or only the actual production shared native-frame suite')
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/lane_timing'/a.name;run.mkdir(parents=True,exist_ok=False)
    result=dict(simulation='IN_PROGRESS',suite_selection=a.only,td_root=str(a.td_root),commands=[],inputs=[],synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    fixture=ROOT/'model/c1_row_vectors.json'
    vectors=json.loads(fixture.read_text())['vectors']
    samples=[];expected=[];sizes=[]
    for v in vectors:
        for q,x,y,f in zip(v['q'],v['gx'],v['gy'],v['flags']):
            samples.append((x&2047)|((y&2047)<<11)|(q<<22)|(f<<30))
        points=[int.from_bytes(bytes.fromhex(h),'little') for h in v['expected_hex']]
        sizes.append(len(points));expected+=points+[0]*(303-len(points))
    sys.path.insert(0,str(ROOT/'model'))
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
    native=[];quarters=[];shared_points=[];shared_sizes=[]
    for mode in range(3):
        image=np.full((1080,1920,3),45,np.uint8)
        if mode!=2:
            image[:,694:707]=(220,220,220) if mode==0 else (30,210,220)
            image[:,1194:1207]=(230,230,230)
        q,gx,gy,flags=c1.features(image)
        for b,g,r in image[0].tolist():
            yy=(29*b+150*g+77*r+128)>>8
            native.append((yy<<24)|(r<<16)|(g<<8)|b)
        packed=(gx.astype(np.int64)&2047)|((gy.astype(np.int64)&2047)<<11)|(q.astype(np.int64)<<22)|(flags.astype(np.int64)<<30)
        quarters.extend(packed.ravel().tolist())
        selected=c1.select_rows(c1.ridge_candidates(q,gx,gy,flags))
        shared_sizes.append(len(selected))
        points=[int.from_bytes(c1.pack_point(p),'little') for p in selected]
        shared_points+=points+[0]*(303-len(points))
    for name,vals,digits in [('native_pixels',native,8),('quarter_samples',quarters,8),('shared_expected',shared_points,10),('shared_sizes',shared_sizes,8)]:
        (run/(name+'.hex')).write_text(''.join(f'{v:0{digits}x}\n' for v in vals))
    # Independent scalar native color comparisons, before the OR operation.
    palette=[(95,135,95),(95,136,95),(70,70,45),(70,70,46),
             (255,255,255),(96,72,47),(97,72,47),(128,96,71),
             (128,95,70),(140,140,110),(94,94,94),(0,0,255)]
    mark_pixels=[];mark_golden=[]
    image=np.zeros((8,1920),np.uint32)
    for yy in range(8):
        for xx in range(1920):
            r,g,b=palette[(xx//4+(yy//4)*7)%len(palette)]
            # Only one member of each native4x4 block is colored. Its phase
            # visits all four lanes and all four rows across adjacent blocks.
            if xx%4!=(xx//4)%4 or yy%4!=(xx//4//4)%4:r=g=b=45
            image[yy,xx]=(r<<16)|(g<<8)|b
            mark_pixels.append(int(image[yy,xx]))
    for qy in range(2):
        for qx in range(480):
            flags=0
            for rgb in image[qy*4:qy*4+4,qx*4:qx*4+4].ravel().tolist():
                r,g,b=(rgb>>16)&255,(rgb>>8)&255,rgb&255
                white=min(r,g,b)>=95 and max(r,g,b)-min(r,g,b)<=40
                yellow=r>=70 and g>=70 and b+24<min(r,g) and abs(r-g)<=max(24,max(r,g)>>2)
                flags|=int(white)|(int(yellow)<<1)
            mark_golden.append(flags)
    (run/'mark_pixels.hex').write_text(''.join(f'{v:06x}\n' for v in mark_pixels))
    (run/'mark_golden.hex').write_text(''.join(f'{v:01x}\n' for v in mark_golden))
    result['generated_fixtures']=[dict(path=p.name,sha256=sha(p)) for p in sorted(run.glob('*.hex'))]+[
        dict(path='r2_directed_vectors.json',sha256=sha(run/'r2_directed_vectors.json'))]
    rtl=ROOT/'src_fpga/rtl';ip=ROOT/'src_fpga/ip'
    fixed=run/'lane_ridge_candidates1_fixed_e700.v'
    fixed.write_bytes((HERE/'fixed_e700/lane_ridge_candidates1_lutram.v.txt').read_bytes().replace(b'module lane_ridge_candidates1_lutram(',b'module lane_ridge_candidates1_fixed_e700('))
    result['baseline_commit']='e700521176'
    sources=[fixed]+[rtl/n for n in ['td_sdp_ram40.v','lane_candidate_store.v','lane_sparse_serial4.v','lane_quarter_fifo4_to1.v','lane_winner_pair_lutram.v','lane_ridge_candidates1_lutram.v','lane_mark_hint4.v','full_filter_sobel4.v']]
    sources += [ip/'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
        ROOT/'src_fpga/simulation/assets/define.v',
        ip/'stage3/fdct_mac19s14s_z33s_p34_m1p1/RTL/fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v',
        ip/'stage3/fdct_mac19s14s_z33s_p34_m1p1/fdct_mac19s14s_z33s_p34_m1p1.v',
        a.td_root/'sim_release/ph1/ph1_phy_gsr.v']
    # Read only the fixture's directly reachable shared analysis dependencies.
    sys.path.insert(0,str(ROOT/'src_fpga/simulation/autof21/core'))
    from run import closure
    groups=closure(json.loads((ROOT/'src_fpga/simulation/MAIN_FIXTURE.json').read_text()),['stage3_filter_color_analysis4'])
    sources=list(dict.fromkeys(sources+[p for group in groups.values() for p in group]))
    original_stage=rtl/'stage3_filter_color_analysis4.v'
    # Compile the actual production adapter and its registered LUTRAM worker.
    # The historical shared bench names its old fixture alias; change only
    # that bench reference in the run-local copy, never production text.
    sources=[p for p in sources if p.name not in ['lane_ridge_candidates4.v','lane_ridge_candidates1.v']]
    assert original_stage in sources and 'lane_sparse_serial4 lane' in original_stage.read_text()
    assert 'lane_ridge_candidates1_lutram worker' in (rtl/'lane_sparse_serial4.v').read_text()

    # The compaction leaf gates the necessary native shared-frame check.
    benches=sorted(HERE.glob('tb_*.sv'),key=lambda p:(p.stem!='tb_fifo',p.stem))
    if a.only=='leaf':benches=[p for p in benches if p.stem!='tb_shared']
    if a.only=='shared':benches=[p for p in benches if p.stem=='tb_shared']
    if a.only=='fifo_stall':benches=[p for p in benches if p.stem=='tb_fifo_stall']
    original_benches=benches[:]
    for index,bench in enumerate(benches):
        if bench.stem=='tb_shared':
            body=bench.read_text()
            assert body.count('stage3_filter_color_analysis_serial4 #')==1
            actual=run/bench.name
            actual.write_text(body.replace('stage3_filter_color_analysis_serial4 #','stage3_filter_color_analysis4 #'))
            benches[index]=actual
    result['production_adapter_mode']='actual source, no generated production adapter; bench alias reference only'
    models=[a.td_root/p for p in json.loads((ROOT/'src_fpga/simulation/MAIN_FIXTURE.json').read_text())['models']]
    for p in sources+benches+original_benches+models+[fixture,ROOT/'model/c1_reference.py',Path(__file__)]:result['inputs'].append(dict(path=str(p.resolve()),sha256=sha(p)))
    def call(label,exe,args,timeout=90):
        argv=[str(a.modelsim_bin/exe),*map(str,args)]
        r=subprocess.run(argv,cwd=run,capture_output=True,text=True,errors='replace',timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
        result['commands'].append(dict(argv=argv,exit_code=r.returncode))
        (run/(label+'.console.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
        if r.returncode:raise RuntimeError(label+': '+r.stdout[-9000:]+r.stderr[-1000:])
    try:
        call('vmap','vmap.exe',['-c'])
        for lib in ['work','ph1']:
            call('vlib_'+lib,'vlib.exe',[lib]);call('vmap_'+lib,'vmap.exe',[lib,lib])
        call('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        macdefs=['+define+fdct_mac19s14s_z33s_p34_m1p1_USE_'+n+'=1' for n in ['A','CE','PH1A','RST','Y','Z']]
        call('compile','vlog.exe',['-quiet','+define+PH1',*macdefs,'-timescale','1ns/1ps','-l','compile.log',*sources])
        call('benches','vlog.exe',['-quiet','-sv','-l','benches.log',*benches])
        for bench in benches:
            top=bench.stem
            call(top,'vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.'+top,'-l',top+'.log','-do','onerror {quit -code 1}; run -all; quit -f'],600)
            log=(run/(top+'.log')).read_text(errors='replace')
            assert 'RESULT: PASS' in log and not re.search(r'\*\* (Error|Fatal):',log),log[-8000:]
            result.setdefault('results',[]).extend(s.strip('# ') for s in log.splitlines() if 'RESULT: PASS' in s)
            result.setdefault('observations',[]).extend(s.strip('# ') for s in log.splitlines() if 'SHARED frame' in s)
            result.setdefault('observations',[]).extend(s.strip('# ') for s in log.splitlines() if 'COMPACTION batches' in s)
            result.setdefault('observations',[]).extend(s.strip('# ') for s in log.splitlines() if 'MAX candidate_count' in s)
            result.setdefault('observations',[]).extend(s.strip('# ') for s in log.splitlines() if 'SERIAL_' in s)
        warnings=[s for p in run.glob('*.log') for s in p.read_text(errors='replace').splitlines() if '** Warning:' in s]
        unexpected=[s for s in warnings if not re.search(r'ph1_logic_eram\.v\(1287\).*INIT_FILE.*out of bounds|ph1_logic_dram\.v\(221\).*INIT_FILE.*out of bounds|(?:vopt-2241|vsim-3015).*ecc_[sd]biterrinj|fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0\.v\(466\).*\(vopt-(?:2685|2718)\)',s)]
        assert not unexpected,unexpected
        for row in result['inputs']:assert sha(Path(row['path']))==row['sha256'],row['path']
        result.update(simulation='PASS',warnings=warnings)
        print('\n'.join(result['results']))
    except Exception as e:result.update(simulation='FAIL',error=str(e));raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
        print('Evidence',run)
if __name__=='__main__':main()
