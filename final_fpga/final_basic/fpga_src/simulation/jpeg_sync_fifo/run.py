"""Official-model A/B: pinned928b Quant/FIFO versus actual production candidate."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys

HERE=Path(__file__).resolve().parent
CAND=HERE.parents[2]
REPO=CAND.parents[1]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def fixtures(run):
    sys.path.insert(0,str(REPO/'tools/jpeg_ref'))
    import jpeg_ref as ref
    base=json.loads((REPO/'src_fpga/rtl/jpeg/quant_data/q50_base.json').read_text())
    columns=[];tokens=[];entropy=[];counts=[];offsets=[]
    for frame,(quality,restart) in enumerate([(75,0),(37,1),(1,3),(100,2)]):
        scale=5000//quality if quality<50 else 200-2*quality
        tables={name:[min(255,max(1,(q*scale+50)//100)) for q in base[name]] for name in ['luma','chroma']}
        bits=ref.Bits();predict={'Y':0,'Cb':0,'Cr':0}
        for block in range(128):
            component=(0,0,1,2)[block%4];name=('Y','Cb','Cr')[component]
            # Exact signed DCT-domain input; includes dense AC, signs, long
            # zero runs, DC changes and both tables, without changing JPEG math.
            coeff=[((n*37+block*11+frame*29)%511)-255 for n in range(64)]
            if block%3==1:
                for z in range(1,35):coeff[ref.ZIGZAG[z]]=0
            q=tables['luma' if component==0 else 'chroma']
            quant=[(-1 if c<0 else 1)*((abs(c)+q[n]//2)//q[n]) for n,c in enumerate(coeff)]
            meta=(component<<53)|((block//4)<<44)|(0<<35)|((block%4)<<33)|(int(block==127)<<32)|(0x5000+frame)
            header=(0x5000+frame)|(11<<32)|(23<<64)|((block//4)<<96)|(component<<114)|((block%4)<<116)|(int(block==127)<<118)|(quality<<119)
            tokens.append((1<<145)|(0xffff<<128)|header)
            for col in range(8):
                data=sum((coeff[row*8+col]&0xffff)<<(16*row) for row in range(8))
                columns.append(data|(col<<128)|(meta<<131)|(quality<<186)|(11<<193)|(23<<225))
            for batch in range(8):
                data=sum((quant[ref.ZIGZAG[batch*8+lane]]&0xffff)<<(16*lane) for lane in range(8))
                tokens.append(data|(0xffff<<128)|(int(batch==7)<<144))
            predict[name]=ref.emit(bits,quant,predict[name],name,[],quant)
            if restart and block%4==3 and block!=127 and (block//4+1)%restart==0:
                bits.finish();bits.out.extend([0xff,0xd0+(((block//4+1)//restart-1)%8)])
                predict={k:0 for k in predict}
        bits.finish();offsets.append(len(entropy));counts.append(len(bits.out));entropy+=bits.out
    for name,data,digits in [('columns',columns,65),('tokens',tokens,37),('entropy',entropy,2),('byte_counts',counts,8),('byte_offsets',offsets,8)]:
        (run/(name+'.hex')).write_text(''.join(f'{v:0{digits}x}\n' for v in data),encoding='ascii')
    (run/'fixture.vh').write_text(f'`define COLUMN_TOTAL {len(columns)}\n`define TOKEN_TOTAL {len(tokens)}\n`define BYTE_TOTAL {len(entropy)}\n`define COLUMNS_PER_FRAME 1024\n`define TOKENS_PER_FRAME 1152\n')
    return dict(frames=4,columns=len(columns),tokens=len(tokens),entropy_bytes=counts,
                quality=[75,37,1,100],restart=[0,1,3,2])


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--td-root',required=True,type=Path)
    ap.add_argument('--modelsim-bin',required=True,type=Path)
    ap.add_argument('--name',required=True)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,40}',a.name)
    run=CAND/'tmp/jpeg_sync_fifo'/a.name;run.mkdir(parents=True,exist_ok=False)
    result=dict(status='IN_PROGRESS',production_modified=False,td_root=str(a.td_root),commands=[],inputs=[],synthesis='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    rtl=CAND/'src_fpga/rtl';ip=CAND/'src_fpga/ip';assets=CAND/'src_fpga/simulation/assets'
    original=rtl/'jpeg_quant_stream.v'
    baseline_commit='928b426c07ecf0bc0f94c0aef708f9696541aa1e'
    baseline_path='refactor/hdr_lane_sparse/src_fpga/rtl/jpeg_quant_stream.v'
    baseline_bytes=subprocess.run(['git','show',baseline_commit+':'+baseline_path],cwd=REPO,capture_output=True,check=True).stdout
    old=baseline_bytes.decode('utf-8')
    block='''    axis_frame_fifo_ip u_token_fifo (
        .i_source_clk(i_clk),.i_source_rst_n(i_rst_n),.i_source_data(token),
        .i_source_valid(i_rst_n && token_valid),.o_source_ready(fifo_ready),.o_source_reset_done(),
        .i_sink_clk(i_clk),.i_sink_rst_n(i_rst_n),.o_sink_data(o_token_data),
        .o_sink_valid(o_token_valid),.i_sink_ready(i_token_ready),.o_sink_reset_done());'''
    assert old.count(block)==1,'pinned baseline is not original async Quant'
    assert re.search(r'\bjpeg_quant_sync_fifo\s+u_token_fifo\s*\(',original.read_text()),'production Quant must contain the approved sync FIFO instance before A/B'
    reference=old.replace('module jpeg_quant_stream #(','module jpeg_quant_stream_async_reference #(',1)
    generated=run/'jpeg_quant_stream_async_reference.v';generated.write_text(reference,encoding='utf-8',newline='\n')
    (run/'jpeg_quant_stream_928b_original.v').write_bytes(baseline_bytes)
    result['baseline']=dict(commit=baseline_commit,path=baseline_path,git_bytes_sha256=hashlib.sha256(baseline_bytes).hexdigest(),
        simulation_copy_sha256=sha(generated),only_change='module renamed jpeg_quant_stream_async_reference')
    result['fixture']=fixtures(run)
    rom_init=run/'rom_init';rom_init.mkdir()
    for mif in (rtl/'jpeg/quant_data').glob('*.mif'):
        records=re.findall(r'(?m)^\s*([0-9a-fA-F]+)\s*:\s*([0-9a-fA-F]+);',mif.read_text())
        if records:
            assert [int(k,16) for k,_ in records]==list(range(len(records)))
            (rom_init/(mif.name+'.dath')).write_text(''.join(v+'\n' for _,v in records))
            result['inputs'].append(dict(path=str(mif),sha256=sha(mif)))
    source_names=['td_sdp_ram40.v','td_sdp_ram.v','td_dsp_mult.v','axis_frame_fifo_ip.v','jpeg_quant_sync_fifo.v',
        'jpeg_quant_rom10x2048.v','jpeg_quant_recip_rom40x512.v','jpeg_quant_table_rom.v','jpeg_quant_stream.v',
        'jpeg_quant_rom20x1024.v','jpeg_huff_ac_rom.v','jpeg_entropy.v']
    sources=[rtl/n for n in source_names]
    sources += [ip/'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
        ip/'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v', ip/'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v',ip/'camera_packet_fifo_147x512/camera_packet_fifo_147x512.v',
        ip/'isp_line_ram_20x1024_ip/isp_line_ram_20x1024_ip.v',
        ip/'dsp_mult_fixed/mult_25u16u_p1/RTL/mult_25u16u_p1_multiplier.v',
        ip/'dsp_mult_fixed/mult_25u16u_p1/RTL/mult_25u16u_p1_multiplier_top.v',
        ip/'dsp_mult_fixed/mult_25u16u_p1/mult_25u16u_p1.v']
    sources += [assets/f'jpeg_rom_q_lane{n}_sim.v' for n in range(8)]
    sources += [assets/'jpeg_rom_recip_sim.v',assets/'jpeg_rom_huff_sim.v',generated,a.td_root/'sim_release/ph1/ph1_phy_gsr.v']
    models=[a.td_root/'sim_release'/n for n in ['common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_phy_eram.v',
        'ph1/ph1_logic_mult.v','ph1/ph1_phy_dspmult.v','ph1/ph1_phy_dspmult_v2.v',
        'ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_fifoctrl.v','ph1/ph1_logic_dram.v','ph1/ph1_phy_dram.v']]
    models=[p for p in models if p.exists()]
    benches=sorted(HERE.glob('tb_*.sv'))
    include_dirs=[rtl/'include/02_jpeg',ip/'camera_packet_fifo_147x512/RTL/include',run]
    for p in sources+models+benches+[Path(__file__),REPO/'tools/jpeg_ref/jpeg_ref.py',REPO/'src_fpga/rtl/jpeg/quant_data/q50_base.json',rtl/'include/02_jpeg/jpeg_quant_config.vh',rtl/'include/02_jpeg/jpeg_quant_bank_map.vh',rtl/'include/02_jpeg/jpeg_huff_rom.vh']:
        result['inputs'].append(dict(path=str(p),sha256=sha(p)))
    def call(label,exe,args,timeout=90):
        argv=[str(a.modelsim_bin/exe),*map(str,args)]
        proc=subprocess.run(argv,cwd=run,capture_output=True,text=True,errors='replace',timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
        (run/(label+'.console.log')).write_text(proc.stdout+proc.stderr,encoding='utf-8')
        result['commands'].append(dict(argv=argv,exit_code=proc.returncode))
        if proc.returncode:raise RuntimeError(label+': '+proc.stdout[-7000:]+proc.stderr[-1000:])
    try:
        call('vmap','vmap.exe',['-c'])
        for lib in ['work','ph1']:
            call('vlib_'+lib,'vlib.exe',[lib]);call('vmap_'+lib,'vmap.exe',[lib,lib])
        call('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        call('compile','vlog.exe',['-quiet','+define+PH1','-timescale','1ns/1ps',*[f'+incdir+{p}' for p in include_dirs],'-l','compile.log',*sources])
        call('benches','vlog.exe',['-quiet','-sv',*[f'+incdir+{p}' for p in include_dirs],'-l','benches.log',*benches])
        for bench in benches:
            call(bench.stem,'vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.'+bench.stem,'-l',bench.stem+'.log','-do','onerror {quit -code 1}; run -all; quit -f'],120)
            log=(run/(bench.stem+'.log')).read_text(errors='replace')
            assert 'RESULT: PASS' in log and not re.search(r'\*\* (Error|Fatal):|Parameter Error|Error, ERAM20K',log),log[-7000:]
            result.setdefault('results',[]).extend(line.strip('# ') for line in log.splitlines() if 'RESULT: PASS' in line or 'FRAME_PASS' in line)
        warnings=[line for bench in benches for line in (run/(bench.stem+'.log')).read_text(errors='replace').splitlines() if '** Warning:' in line]
        unexpected=[line for line in warnings if not re.search(r'ph1_logic_(?:eram|dram)\.v\((?:1287|221)\).*INIT_FILE.*out of bounds|(?:vopt-2241).*ecc_[sd]biterrinj',line)]
        assert not unexpected,unexpected
        result['warning_occurrences']=len(warnings)
        result['warning_classes']=['official INIT_FILE string-index bounds','official unused ECC injection port width']
        for record in result['inputs']:assert sha(Path(record['path']))==record['sha256'],record['path']
        result.update(status='PASS')
        print('\n'.join(result['results']))
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
        print('Evidence',run)


if __name__=='__main__':main()
