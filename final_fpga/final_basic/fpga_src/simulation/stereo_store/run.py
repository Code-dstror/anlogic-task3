"""Focused stereo capture/RAW owner/reader verification; no TD build is run."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--name',required=True)
    p.add_argument('--td-root',type=Path,required=True)
    p.add_argument('--modelsim-bin',type=Path,required=True)
    p.add_argument('--case',choices=['all','store','cadence','scheduler','stop','quiescent','hdr','lifecycle','hdr_lifecycle'],default='all')
    a=p.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}',a.name):p.error('invalid name')
    out=ROOT/'tmp'/'stereo_store'/a.name
    out.mkdir(parents=True,exist_ok=False)
    td=a.td_root.resolve();ms=a.modelsim_bin.resolve();rtl=ROOT/'src_fpga/rtl';ip=ROOT/'src_fpga/ip'
    models=[td/'sim_release'/x for x in ['common/al_phy_glbl.v','ph1/ph1_logic_dram.v',
        'ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v',
        'ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v']]
    sources=[td/'sim_release/ph1/ph1_phy_gsr.v',
        ip/'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
        ip/'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v', ip/'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v',
        ip/'camera_packet_fifo_147x512/camera_packet_fifo_147x512.v']
    names=['reset_release_sync','td_sdp_ram40','hdr_pair_directory','raw10_frame_replay',
        'stereo_raw_owner','stereo_raw_reader','stereo_raw_store','raw_capture_fifo_eram_safe',
        'shared_raw10_frame_ingress','shared_raw_capture_writer','full_raw_capture_frontend',
        'dual_raw_capture_frontend','dol2_axi_write_arbiter','raw10_append5',
        'hdr_pair_context_cache','raw_pair_replay_scheduler','raw_hdr_phase_scheduler4','raw_pair_job_service',
        'hdr_pair_bank_owner','hdr_pair_bank_owner_dual','hdr_eye_shared','hdr_pair_bank_owner_serial',
        'raw_application_stop_dfi','axis_frame_fifo_ip','full_raw_store']
    sources += [ip/'camera_control_fifo_40x512'/f for f in (
        'RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        'RTL/camera_control_fifo_40x512_soft_fifo.v','camera_control_fifo_40x512.v')]
    names += ['control_fifo_40x512','hdr_pair_read_cursor','shared_raw10_decoder','shared_raw10_decoder_masked','shared_raw10_decode_service','hdr_merge4','hdr_pair_pixel_reader']
    sources += [rtl/(n+'.v') for n in names]+[HERE/'tb_stereo_store.sv',HERE/'tb_stereo_scheduler.sv',
        HERE/'tb_stereo_full_store_quiescent.sv', HERE/'tb_stereo_hdr_capture.sv']
    if a.case in ('all','lifecycle'):
        sources += [rtl/'td_sdp_ram.v',rtl/'jpeg_ring_cold_bank.v',rtl/'jpeg_frame_ring.v',
                    HERE/'axi128_stall_memory.v',HERE/'tb_jpeg_tail_retire.sv']
    headers=[rtl/'include/04_include/pcie_protocol_v1.vh']
    for f in sources+models+headers:
        if not f.is_file():raise FileNotFoundError(f)
    identity=[{'path':f.as_posix(),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sources+models+headers+[Path(__file__)]]
    (out/'sources.json').write_text(json.dumps(identity,indent=2)+'\n')
    def run(args,log):
        r=subprocess.run([str(x) for x in args],cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
        (out/log).write_text(r.stdout,encoding='utf-8')
        if r.returncode:raise RuntimeError(r.stdout[-10000:])
        return r.stdout
    def check_simulation(log):
        if 'RESULT: PASS' not in log or re.search(r'\*\* (Error|Fatal):',log):
            raise RuntimeError(log[-10000:])
        warnings=[line for line in log.splitlines() if '** Warning:' in line]
        allowed=[line for line in warnings if
            ('ram40_sdp_fixed.v(69)' in line and 'vopt-2241' in line and 'ecc_' in line) or
            ('ph1_logic_eram.v(1287)' in line and 'vopt-2697' in line and 'INIT_FILE' in line) or
            ('ph1_logic_dram.v(221)' in line and 'vopt-2697' in line and 'INIT_FILE' in line) or
            ('vsim-3015' in line and 'ecc_' in line and 'ph1_logic_eram.v(52)' in line)]
        if len(allowed)!=len(warnings):
            raise RuntimeError('unclassified warning:\n'+'\n'.join(x for x in warnings if x not in allowed))
        return len(warnings)
    run([ms/'vlib.exe','ph1'],'vlib_ph1.log');run([ms/'vlib.exe','work'],'vlib_work.log')
    run([ms/'vlog.exe','-work','ph1',*models],'models.log')
    run([ms/'vlog.exe','-sv','+define+PH1','+incdir+'+(rtl/'include/04_include').as_posix(),*sources],'compile.log')
    results=[]
    cases=[]
    if a.case in ('all','store'):
        cases += [('tb_stereo_store',[f'-gDIVISOR={div}'],f'div{div}.log') for div in (1,4)]
    if a.case in ('all','cadence'):
        cases += [('tb_stereo_store',[f'-gDIVISOR={div}','-gRUNTIME_CADENCE=1'],f'runtime_div{div}.log') for div in (1,3,6)]
    if a.case in ('all','stop'):
        cases.append(('tb_stereo_store',['-gDIVISOR=1','-gSTOP_BEFORE_REPLAY=1'],'stop.log'))
    if a.case in ('all','quiescent'):
        cases.append(('tb_stereo_full_store_quiescent',[],'quiescent.log'))
    if a.case in ('all','scheduler'):
        cases.append(('tb_stereo_scheduler',[],'scheduler.log'))
    if a.case in ('all','hdr','hdr_lifecycle'):
        cases.append(('tb_stereo_hdr_capture',[],'hdr_capture.log'))
    if a.case in ('all','lifecycle','hdr_lifecycle'):
        for index, label in enumerate(('stop_b','mode_release','wrong_eye'),start=1):
            cases.append(('tb_stereo_hdr_capture',[f'-gAUDIT_CASE={index}'],label+'.log'))
        if a.case!='hdr_lifecycle':
            cases.append(('tb_jpeg_tail_retire',[],'jpeg_tail.log'))
    def save_results():
        (out/'RESULTS.json').write_text(json.dumps({'results':results,
            'scope':'actual capture/replay FIFOs, writers, full RAW store, cold owners and RAW reader; AXI memory and processing-result boundaries modeled',
            'td_root':td.as_posix(),'synthesis':'NOT_RUN','pnr':'NOT_RUN','board':'NOT_RUN'},indent=2)+'\n')
    for top,parameters,filename in cases:
        result={'top':top,'parameters':parameters,'log':filename,'status':'FAIL'}
        results.append(result)
        try:
            log=run([ms/'vsim.exe','-c','-L','ph1','work.PH1_PHY_GSR','work.'+top,
                *parameters,'-do','run -all; quit -f'],filename)
            print('\n'.join(x for x in log.splitlines() if 'STEREO_' in x or 'RESULT:' in x))
            warnings=check_simulation(log)
            result.update(status='PASS',owned_warnings=0,reviewed_vendor_warnings=warnings)
        except Exception:
            save_results()
            raise
        save_results()
    print(out/'RESULTS.json')

if __name__=='__main__':main()
