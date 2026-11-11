"""Cycle-exact dual-VC CRC sharing miter against the fixed pre-change Git RTL."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]
BASE='928b426c07ecf0bc0f94c0aef708f9696541aa1e'


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--modelsim-bin',type=Path,required=True)
    ap.add_argument('--receiver',action='store_true');ap.add_argument('--td-root',type=Path)
    ap.add_argument('--name',required=True);a=ap.parse_args();assert re.fullmatch(r'[a-z][a-z0-9_]{0,40}',a.name)
    run=ROOT/'tmp/rx_shared_crc'/a.name;run.mkdir(parents=True,exist_ok=False)
    fixed=run/'fixed';fixed.mkdir()
    sources=[]
    for name in ['real_hdr_csi_word_core.v','real_hdr_csi_dual_word_rx.v']:
        body=subprocess.check_output(['git','show',BASE+':refactor/hdr_lane_sparse/src_fpga/rtl/'+name],cwd=REPO)
        target=fixed/('prior_'+name)
        target.write_bytes(body.replace(b'real_hdr_csi_word_core',b'prior_real_hdr_csi_word_core').replace(b'real_hdr_csi_dual_word_rx',b'prior_real_hdr_csi_dual_word_rx'))
        sources += [target,ROOT/'src_fpga/rtl'/name]
    groups=[(48,'long_data short_data'),(1,'long_valid short_valid long_sof short_sof long_eol short_eol long_abort short_abort'),
        (4,'long_error short_error'),(32,'long_sequence_count short_sequence_count long_group short_group long_event_sequence short_event_sequence'),
        (1,'long_identity_valid short_identity_valid long_cycle_valid short_cycle_valid'),(16,'long_event_frame_number short_event_frame_number'),
        (1,'long_fs_observe_valid short_fs_observe_valid'),(16,'long_fs_number short_fs_number'),
        (32,'long_fs_observe_sequence short_fs_observe_sequence'),(1,'long_fs_observe_trusted short_fs_observe_trusted identity_fault wait_for_sync packet_done packet_continue header_ecc_error payload_crc_error length_error')]
    mappings=[];offset=0
    for width,names in groups:
        for name in names.split():mappings.append((name,offset,width));offset+=width
    assert offset==447,offset
    text=[]
    for module,instance,bus in [('real_hdr_csi_dual_word_rx','dut','candidate'),('prior_real_hdr_csi_dual_word_rx','prior','reference')]:
        ports=['.i_clk(clk)','.i_reset_n(rst_n)','.i_identity_rst_n(identity_n)','.i_cycle_enable(cycle_enable)',
            '.i_word(word)','.i_word_valid(valid)','.i_long_ready(ready0)','.i_short_ready(ready1)']
        ports += ['.o_'+name+'('+bus+'['+str(off)+'+:'+str(width)+'])' for name,off,width in mappings]
        text.append(module+' #(.SAMPLE_BITS(BITS)) '+instance+'('+',\n'.join(ports)+');\n')
    (run/'miter_instances.vh').write_text(''.join(text))
    models=[];flags=[];extras=[]
    if a.receiver:
        assert a.td_root is not None,'Receiver uses explicit TD models'
        models=[a.td_root/'sim_release'/p for p in ['common/al_phy_glbl.v','ph1/ph1_logic_eram.v',
            'ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v']]
        fixture=ROOT/'src_fpga/simulation/runtime_recovery/recovery_receiver_tb.sv';extras.append(fixture)
        mock=run/'phy_boundary.v';mock.write_text(fixture.read_text().split('module recovery_receiver_tb;')[0])
        sources=[a.td_root/'sim_release/ph1/ph1_phy_gsr.v',mock]
        sources += [ROOT/'src_fpga/rtl'/p for p in ['real_hdr_physical_csi_rx.v','reset_release_sync.v',
            'csi_rx_word_align_observed.v','physical_csi_rx_stream.v','physical_csi_word_core.v','csi2_async_event_fifo.v',
            'real_hdr_csi_capture_stream.v','real_hdr_csi_dual_word_rx.v','real_hdr_csi_word_core.v',
            'real_hdr_member_crop10.v','raw_capture_fifo_eram_safe.v']]
        sources += [ROOT/'src_fpga/ip'/p for p in ['vendor/anlogic_camera/phy/csi_rx_word_gear_box.v',
            'camera_event_fifo_47x8192/RTL/camera_event_fifo_47x8192_soft_fifo_core.v',
            'camera_event_fifo_47x8192/RTL/camera_event_fifo_47x8192_soft_fifo.v','camera_event_fifo_47x8192/camera_event_fifo_47x8192.v',
            'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v', 'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v','camera_packet_fifo_147x512/camera_packet_fifo_147x512.v']]
        inc=ROOT/'src_fpga/ip/camera_event_fifo_47x8192/RTL/include'
        extras += list(inc.glob('*'))
        flags=['+define+PH1','+define+R8_STAGE1','+incdir+'+str(inc)]
        bench=HERE/'tb_shared_crc_receiver.sv';top='tb_shared_crc_receiver'
    else:bench=HERE/'tb_shared_crc.sv';top='tb_shared_crc'
    sources.append(bench)
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    inputs=[dict(path=str(p),sha256=sha(p)) for p in models+sources+extras+[Path(__file__),run/'miter_instances.vh']]
    result=dict(status='IN_PROGRESS',baseline_commit=BASE,inputs=inputs,commands=[],synthesis='NOT_RUN',pr='NOT_RUN',board='NOT_RUN')
    start=time.monotonic()
    def call(name,exe,args):
        argv=[str(a.modelsim_bin/exe)]+list(map(str,args));proc=subprocess.run(argv,cwd=run,capture_output=True,text=True,errors='replace',timeout=60)
        (run/(name+'.console.log')).write_text(proc.stdout+proc.stderr);result['commands'].append(dict(argv=argv,returncode=proc.returncode))
        assert proc.returncode==0,(proc.stdout+proc.stderr)[-6000:]
    try:
        call('vmap','vmap.exe',['-c']);call('work','vlib.exe',['work'])
        if models:
            call('ph1','vlib.exe',['ph1']);call('models','vlog.exe',['-quiet','-work','ph1','-l','models.log']+models)
        call('compile','vlog.exe',['-sv','-quiet','+incdir+'+str(run),'-l','compile.log']+flags+sources)
        call('sim','vsim.exe',['-c','-voptargs=+acc']+(['-L','ph1','work.PH1_PHY_GSR','ph1.glbl'] if models else [])+['work.'+top,'-l','simulation.log','-do','run -all; quit -f'])
        log=(run/'simulation.log').read_text(errors='replace')
        assert ('RESULT: PASS SHARED_RX_RECEIVER' if a.receiver else 'RESULT: PASS SHARED_RX_CRC') in log and not re.search(r'\*\* (?:Error|Fatal):',log),log[-6000:]
        for row in inputs:assert sha(Path(row['path']))==row['sha256'],'Source drift '+row['path']
        result.update(status='PASS',summary=[l.strip('# ') for l in log.splitlines() if 'CASE_PASS' in l or 'RESULT:' in l])
    except Exception as exc:result.update(status='FAIL',error=str(exc));raise
    finally:
        result['elapsed_s']=round(time.monotonic()-start,3);(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(dict(status=result['status'],run=str(run),error=result.get('error'))))


if __name__=='__main__':main()
