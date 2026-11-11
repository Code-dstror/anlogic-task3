"""Independent two-frame RAW/ISP/Gray/Gaussian/temporal-HE/C1/v4/JPEG oracle."""
from pathlib import Path
import argparse,importlib.util,json,sys,time
from dataclasses import asdict
import numpy as np

CASE=Path(__file__).resolve().parent
EXTENDED=CASE.parent
ROOT=EXTENDED.parents[2]

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    m=importlib.util.module_from_spec(spec);sys.modules[name]=m;spec.loader.exec_module(m)
    return m

A=load('frozen_extended_common',EXTENDED/'sdr_recover/oracle.py')
C1=load('frozen_c1_temporal',EXTENDED/'c1_reference_frozen.py')

def isp_reference():
    """Independent scalar BLC50 + reflect101 RGGB bilinear + frozen gamma.

    Input is the documented linear RAW road pattern, not a DUT trace. Arithmetic
    and border rules are the frozen shared ISP authority used by normal MAIN.
    """
    w,h=1920,1080
    def at(x,y):
        x=-x if x<0 else 2*w-2-x if x>=w else x
        y=-y if y<0 else 2*h-2-y if y>=h else y
        v=60+((x//80+y//90)%9)*12
        if 694<=x<=706:v=800
        elif 1194<=x<=1206:v=700 if not(x%2 or y%2) else 60 if x%2 and y%2 else 600
        return v
    image=[]
    for y in range(h):
        for x in range(w):
            c=at(x,y);cross=(at(x-1,y)+at(x+1,y)+at(x,y-1)+at(x,y+1)+2)//4
            diag=(at(x-1,y-1)+at(x+1,y-1)+at(x-1,y+1)+at(x+1,y+1)+2)//4
            hor=(at(x-1,y)+at(x+1,y)+1)//2;ver=(at(x,y-1)+at(x,y+1)+1)//2
            rgb=((c,cross,diag),(hor,c,ver),(ver,c,hor),(diag,cross,c))[(y%2)*2+x%2]
            image.append(tuple(A.GAMMA[v] for v in rgb))
    return image

def processed_reference(isp):
    v=np.asarray(isp,dtype=np.int32).reshape(1080,1920,3)
    y=((77*v[:,:,0]+150*v[:,:,1]+29*v[:,:,2]+128)>>8).astype(np.uint8)
    # Frozen image-domain contract: Gray before alpha1/2 color-preserving
    # Gaussian image, then previous successful frame's bounded HE correction.
    g=C1.gaussian(y).astype(np.int32);d=g-y.astype(np.int32)
    half=np.where(d<0,-((-d+1)//2),(d+1)//2)
    filtered=np.clip(y.astype(np.int32)+half,0,255).astype(np.uint8)
    hist=np.bincount(filtered.ravel(),minlength=256).astype(np.int64)
    cdf=np.cumsum(hist);first=int(cdf[np.flatnonzero(hist)[0]])
    lut=np.arange(256) if filtered.size==first else np.maximum(cdf-first,0)*255//(filtered.size-first)
    enhanced=np.clip(filtered.astype(np.int64)+np.clip(lut[filtered]-filtered.astype(np.int64),-32,32),0,255).astype(np.uint8)
    A.need(np.count_nonzero(enhanced!=filtered)>100000,'HE fixture must exercise substantial real history')
    return [list(zip(z.ravel().tolist(),z.ravel().tolist(),z.ravel().tolist())) for z in (filtered,enhanced)],hist,lut

def analysis(record,run,index,ys,points):
    pyramid_path=A.ROOT/'src_fpga/stages/r8_stage2/simulation/preprocess_multiscale_reference.py'
    pyramid=load('temporal_frozen_pyramid',pyramid_path)
    levels=pyramid.pyramid_reference(pyramid.Plane(1920,1080,ys))
    expected=pyramid.pack_record(levels,40,record.s07.context)
    A.need(list(A.words(run/f'sdr_f22_{index}.hex',684))==[expected] and record.s07.f22.original_record==expected,'F22 complete independent body')
    descriptor=(record.s07.context<<17)|(len(points)<<8)
    A.need(list(A.words(run/f'sdr_f23_{index}.hex',177))==[descriptor],'C1 complete descriptor')
    wire=record.s07.f23
    A.need(wire.count==len(points) and wire.status==(0 if points else 1),'C1 count/status contract')
    for actual,expected in zip(wire.points,points):
        A.need((actual.native_x,actual.native_y,actual.strength,actual.width_quarter,actual.marking_class)==
            tuple(expected[k] for k in ('native_x','native_y','strength','width_quarter','marking_class')),'C1 every independent point')
    A.need((wire.roi_begin,wire.roi_end)==(169,269) and record.s07.enabled==3 and not record.s07.frame_error,'C1 exact ROI/feature/error')
    return dict(status='PASS',point_count=len(points),F22='all684bits',C1='all177bits+every40bit point')

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run-directory',type=Path,required=True);ap.add_argument('--output-directory',type=Path,required=True)
    a=ap.parse_args();run=a.run_directory.resolve();out=a.output_directory.resolve();out.mkdir(parents=True,exist_ok=False)
    started=time.monotonic();result=dict(status='RUNNING',scope=__doc__,source_commit='LOCAL_SEALED_TREE_NOT_PUSHED',frames=[],production_RTL_modified=False,board='NOT_RUN',physical='NOT_RUN')
    names=tuple(f'{name}_{i}.{suffix}' for i in range(2) for name,suffix in [('sdr_isp','hex'),('sdr_processed','hex'),('sdr_f22','hex'),('sdr_f23','hex'),('local_record','bin'),('actual_record','bin')])
    try:
        binding,log=A.snapshot_binding(run,'sdr',names);result['source_binding']=binding
        A.need('EXTENDED_HE_MAIN PASS frames=2 mask=61 JPEG=2 native_retire=2' in log,'actual two-frame lifecycle marker')
        A.need(log.count('EXTENDED_HE_FRAME PASS')==2,'both complete-frame hardware checks')
        isp=isp_reference();processed,hist,lut=processed_reference(isp)
        points=C1.extract(np.asarray(isp,dtype=np.uint8).reshape(1080,1920,3)[:,:,::-1].copy())
        A.need(len(points)>0,'road fixture must exercise nonempty C1 wire payload')
        ys=list(map(A.luma,isp));seen=[]
        for i in range(2):
            folder=out/f'frame{i}';folder.mkdir()
            record,header,data=A.record_pair(run,f'local_record_{i}.bin',f'actual_record_{i}.bin');m=record.metadata
            A.need(asdict(m.source)==dict(session=1,epoch=1,sequence=i+1,camera=0,kind=1,format=1,role=0),'physical eye/source/epoch identity')
            A.need(m.processing_mode==(128|61) and m.schema2_processing_enables==61 and m.record_flags==0,'frozen full processing tuple, no removed dehaze/HDR flag')
            A.need(not m.qualified and m.actual_exposure is None and m.actual_gain is None and m.calibration_id is None and m.pair_id is None,'unknown optical SDR fields remain unknown')
            A.need((m.jpeg_session,m.jpeg_generation,m.jpeg_slot,m.write_tag) not in seen,'distinct actual writer capability')
            seen.append((m.jpeg_session,m.jpeg_generation,m.jpeg_slot,m.write_tag))
            checks=dict(isp=A.pixels_equal(run/f'sdr_isp_{i}.hex',isp),
                processed=A.pixels_equal(run/f'sdr_processed_{i}.hex',processed[i],list(map(A.luma,processed[i]))),
                neutral=A.check_neutral(record,isp),analysis=analysis(record,run,i,ys,points),
                jpeg=A.check_jpeg(record,processed[i],folder))
            result['frames'].append(dict(index=i,source=asdict(m.source),checks=checks,HE_history_used=bool(i)))
        A.need('C2_STOP_MAIN PASS' in log and 'after_products=2' in log,'actual STOP/reset retains both retired products')
        final,_=A.snapshot_binding(run,'sdr',names);A.need(final==binding,'input/trace drift during independent oracle')
        result.update(status='PASS',oracle_sources=[A.identity(Path(__file__)),A.identity(EXTENDED/'c1_reference_frozen.py')],
            numerical_authority='frozen scalar ISP/JPEG/pyramid; independent image-domain Gaussian/HE contract; no DUT output used as input golden',
            he_histogram=hist.tolist(),he_lut=lut.tolist(),point_count=len(points))
        print('RESULT: PASS extended two-frame fullSDR Gray/Gaussian/HE/F22/C1/v4/exactJPEG/SAFE/ACK',flush=True)
    except Exception as exc:result.update(status='FAIL',error=str(exc));print('RESULT: FAIL',exc,flush=True)
    finally:
        result['elapsed_seconds']=round(time.monotonic()-started,3);(out/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    return result['status']!='PASS'

if __name__=='__main__':raise SystemExit(main())
