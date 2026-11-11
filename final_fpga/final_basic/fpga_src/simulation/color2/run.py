"""Independent, unadopted2PPC color prototype: fixed6f8 A/B and scalar oracle."""
from pathlib import Path
from bisect import bisect_right
import argparse,hashlib,json,random,re,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def mif_words(p):
    body=p.read_text();width=int(re.search(r'WIDTH\s*=\s*(\d+)',body,re.I)[1]);depth=int(re.search(r'DEPTH\s*=\s*(\d+)',body,re.I)[1])
    pairs=[(int(a,16),int(v,16)) for a,v in re.findall(r'(?im)^\s*([0-9a-f]+)\s*:\s*([0-9a-f]+)\s*;',body)]
    assert len(pairs)==depth and [a for a,v in pairs]==list(range(depth)) and all(v<1<<width for a,v in pairs)
    return width,[v for a,v in pairs]
def make_vectors(run):
    gamma_path=ROOT/'src_fpga/rtl/isp/color/gamma22_10to8.mif';_,gamma=mif_words(gamma_path)
    knots=sorted(set(list(range(0,1025,32))+list(range(1024,2049,64))+list(range(2048,4097,128))+list(range(4096,8193,256))+list(range(8192,16385,512))))
    rh=lambda n,d:(2*n+d)//(2*d)
    gains=[rh(65536*1023*(16368+1024),16368*(x+1024)) for x in knots]
    tones=[min(1023,rh(x*1023*(16368+1024),16368*(x+1024))) for x in knots]
    def tone(rgb):
        maximum=max(rgb);i=bisect_right(knots,maximum)-1;step=knots[i+1]-knots[i];rem=maximum-knots[i]
        gain=gains[i]-rh((gains[i]-gains[i+1])*rem,step)
        peak=tones[i]+rh((tones[i+1]-tones[i])*rem,step)
        return tuple(peak if x==maximum else min(peak,rh(x*gain,65536)) for x in rgb)
    matrices=[((256,0,0),(0,256,0),(0,0,256)),((1023,-1024,31),(-128,384,17),(512,-511,256))]
    def mapped(rgb,hdr,wb,matrix,bypass):
        maximum=16383 if hdr else 1023
        raw=[(x*g+128)//256 for x,g in zip(rgb,wb)];clipped=any(x>maximum for x in raw);v=[min(maximum,x) for x in raw]
        if matrix:
            z=[(sum(c*x for c,x in zip(row,v))+128)//256 for row in matrices[matrix]]
            clipped|=any(x<0 or x>maximum for x in z);v=[min(maximum,max(0,x)) for x in z]
        if hdr:v=tone(v)
        return tuple(x>>2 if bypass else gamma[x] for x in v),clipped
    rng=random.Random(20261030);wb_choices=[(256,256,256),(0,0,0),(1023,1023,1023),(909,410,832),(1,127,128),(255,257,511),(1023,0,256),(0,1023,1)]
    codes=[0,1,127,128,255,256,511,512,1022,1023,1024,2047,2048,4095,4096,8191,8192,16368,16383]
    words=[];meta=[];expected={(0,0):[],(1,0):[],(1,1):[]};clip={0:[],1:[]}
    for group in range(1024):
        frame=group//64;hdr=frame&1;wb=wb_choices[frame//2];maximum=16383 if hdr else 1023
        pixels=[tuple(codes[(group*7+lane*3+c)%len(codes)] if group%3 else rng.randrange(maximum+1) for c in range(3)) for lane in range(4)]
        words.append(sum(((r<<28)|(g<<14)|b)<<(42*k) for k,(r,g,b) in enumerate(pixels)))
        gain_word=(wb[2]<<20)|(wb[1]<<10)|wb[0]
        meta.append((gain_word<<3)|(hdr<<2)|(int(group%16==15)<<1)|int(group%64==0))
        for (matrix,bypass),values in expected.items():
            out=[];clipped=False
            for pixel in pixels:
                result,c=mapped(pixel,hdr,wb,matrix,bypass);out.append(result);clipped|=c
            values.append(sum(((r<<16)|(g<<8)|b)<<(24*k) for k,(r,g,b) in enumerate(out)))
            if bypass==0:clip[matrix].append(int(clipped))
    def write(name,values,digits):
        (run/name).write_text(''.join(f'{v:0{digits}x}\n' for v in values))
    write('small_input.hex',words,42);write('small_meta.hex',meta,9)
    for (matrix,bypass),values in expected.items():write(f'small_m{matrix}_b{bypass}.hex',values,24)
    for matrix,values in clip.items():write(f'small_m{matrix}_clip.hex',values,1)
    # One actual1080p SDR frame, all source-valid cycles offered continuously.
    paths=[run/n for n in ['full_input.hex','full_meta.hex','full_expected.hex','full_clip.hex']]
    files=[p.open('w') for p in paths];wb=(909,410,832);gain_word=(wb[2]<<20)|(wb[1]<<10)|wb[0]
    try:
        for y in range(1080):
            for x in range(0,1920,4):
                pixels=[tuple((37*(x+lane)+83*y+13*(x+lane)*y+c*137)&1023 for c in range(3)) for lane in range(4)]
                inp=sum(((r<<28)|(g<<14)|b)<<(42*k) for k,(r,g,b) in enumerate(pixels));out=[];clipped=False
                for p in pixels:
                    q,c=mapped(p,False,wb,0,0);out.append(q);clipped|=c
                rgb=sum(((r<<16)|(g<<8)|b)<<(24*k) for k,(r,g,b) in enumerate(out))
                m=(gain_word<<3)|(int(x==1916)<<1)|int(x==0 and y==0)
                for file,value,digits in zip(files,[inp,m,rgb,int(clipped)],[42,9,24,1]):file.write(f'{value:0{digits}x}\n')
    finally:
        for f in files:f.close()
    return dict(small_groups=1024,small_frames=16,full_groups=518400,full_pixels=2073600,oracle='integer Q8 WB; signed CCM +128 floor>>8/clamp; independently constructed rational T96 knots; official gamma table')
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--td-root',required=True,type=Path);ap.add_argument('--modelsim-bin',required=True,type=Path);ap.add_argument('--name',required=True);a=ap.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/color2'/a.name;run.mkdir(parents=True,exist_ok=False)
    result=dict(simulation='IN_PROGRESS',production_adoption='NOT_ADOPTED_SDR_BURST_UNPROVEN',commands=[],inputs=[],synthesis='NOT_RUN',physical='NOT_RUN',board='NOT_RUN')
    result['vectors']=make_vectors(run)
    sys.path.insert(0,str(ROOT/'src_fpga/simulation/autof21/core'));from run import closure
    groups=closure(json.loads((ROOT/'src_fpga/simulation/MAIN_FIXTURE.json').read_text()),['wide_color_pipeline'])
    sources=list(dict.fromkeys(p for g in groups.values() for p in g));originals=sources[:]
    fixed=run/'wide_color_pipeline_fixed6f8.v';fixed.write_bytes(subprocess.check_output(['git','show','6f8a7004cf:refactor/hdr_lane_sparse/src_fpga/rtl/wide_color_pipeline.v']))
    assert fixed.read_text()==(ROOT/'src_fpga/rtl/wide_color_pipeline.v').read_text()
    sources=[fixed if p.name=='wide_color_pipeline.v' else p for p in sources]
    # Only official model INIT_FILE literals are changed in run-local copies.
    rom_map={'gamma_rom_8x1024_ip.v':'gamma22_10to8.mif.dath','tone96_rom0.v':'tone96_0.mif.dath','tone96_rom1.v':'tone96_1.mif.dath'}
    initializers=json.loads((ROOT/'src_fpga/simulation/MAIN_FIXTURE.json').read_text())['local_rom_initializers']
    for index,p in enumerate(sources):
        module_file=p.name.replace('_sim.v','.v')
        if module_file in rom_map:
            # MAIN fixtures select an existing INIT-only simulation copy.
            # Start this test's wrapper from the real registered IP instead.
            if module_file=='gamma_rom_8x1024_ip.v':p=ROOT/'src_fpga/ip/gamma_rom_8x1024_ip/gamma_rom_8x1024_ip.v'
            else:p=ROOT/'src_fpga/ip/stage3'/module_file[:-2]/module_file
            originals.append(p)
            name=rom_map[module_file];mif=ROOT/initializers[name];width,values=mif_words(mif);dest=run/name
            dest.write_text(''.join(f'{v:0{(width+3)//4}x}\n' for v in values))
            text=p.read_text();matches=list(re.finditer(r'\.INIT_FILE\("[^"]+"\)',text));assert len(matches)==1
            local=run/p.name;local.write_text(text[:matches[0].start()]+'.INIT_FILE("'+dest.as_posix()+'")'+text[matches[0].end():]);sources[index]=local;originals.append(mif)
    sources += [HERE/'prototype'/n for n in ['color_wbccm2.v','color_gamma2.v','wide_color_pipeline2.v']]+[a.td_root/'sim_release/ph1/ph1_phy_gsr.v']
    models=[a.td_root/p for p in json.loads((ROOT/'src_fpga/simulation/MAIN_FIXTURE.json').read_text())['models']]
    bench=HERE/'tb_color2.sv'
    for p in list(dict.fromkeys(originals+sources+models+[bench,Path(__file__)])):result['inputs'].append(dict(path=str(p.resolve()),sha256=sha(p)))
    def call(label,exe,args,timeout=120):
        argv=[str(a.modelsim_bin/exe),*map(str,args)];r=subprocess.run(argv,cwd=run,capture_output=True,text=True,errors='replace',timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
        result['commands'].append(dict(argv=argv,exit_code=r.returncode));(run/(label+'.console.log')).write_text(r.stdout+r.stderr)
        if r.returncode:raise RuntimeError(label+': '+r.stdout[-10000:]+r.stderr[-1000:])
    try:
        call('vmap','vmap.exe',['-c'])
        for lib in ['work','ph1']:call('vlib_'+lib,'vlib.exe',[lib]);call('vmap_'+lib,'vmap.exe',[lib,lib])
        call('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        call('compile','vlog.exe',['-quiet','+define+PH1','-timescale','1ns/1ps','-l','compile.log',*sources]);call('bench','vlog.exe',['-quiet','-sv','-l','bench.log',bench])
        for matrix,bypass,full in [(0,0,0),(1,0,0),(1,1,0),(0,0,1)]:
            name=f'm{matrix}_b{bypass}_f{full}'
            call(name,'vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_color2',f'-gMATRIX={matrix}',f'-gBYPASS={bypass}',f'-gFULL={full}','-l',name+'.log','-do','onerror {quit -code 1}; run -all; quit -f'],300)
            body=(run/(name+'.log')).read_text(errors='replace');assert 'RESULT: PASS' in body and not re.search(r'\*\* (Error|Fatal):',body),body[-12000:]
            result.setdefault('results',[]).extend(s.strip('# ') for s in body.splitlines() if 'RESULT: PASS' in s)
        warnings=[s for p in run.glob('*.log') for s in p.read_text(errors='replace').splitlines() if '** Warning:' in s]
        unexpected=[s for s in warnings if not re.search(r'ph1_logic_eram\.v\(1287\).*INIT_FILE.*out of bounds|(?:vopt-2241|vsim-3015).*ecc_[sd]biterrinj|gamma_rom_8x1024_ip\.v\(36\).*vopt-(?:2685|2718)',s)];assert not unexpected,unexpected
        for row in result['inputs']:assert sha(Path(row['path']))==row['sha256'],row['path']
        result.update(simulation='PASS',warnings=warnings)
        print('\n'.join(result['results']))
    except Exception as e:result.update(simulation='FAIL',error=str(e));raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n');print('Evidence',run)
if __name__=='__main__':main()
