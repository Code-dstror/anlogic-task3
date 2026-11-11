"""Small actual full_raw_store test; only AXI write responses are modeled."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,time
CASE=Path(__file__).resolve().parent
EXT=CASE.parent
PROJECT=EXT.parents[2]
SEAL_SHA='9f1be00097a6ab21889720cf6cfb8ee353cb34fffaab366df4369a63b93af03d'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--name',required=True);ap.add_argument('--td-root',type=Path,required=True);ap.add_argument('--modelsim-bin',type=Path,required=True);a=ap.parse_args()
    run=PROJECT/'tmp/extended_hdr_recovery_20261101'/a.name;run.mkdir(parents=True,exist_ok=False)
    sealpath=PROJECT/'docs/SOURCE_SEAL_LOCAL_20261101.json'
    if sha(sealpath)!=SEAL_SHA:raise RuntimeError('Production seal differs')
    seal=json.loads(sealpath.read_text());td=a.td_root;ms=a.modelsim_bin;rtl=PROJECT/'src_fpga/rtl';ip=PROJECT/'src_fpga/ip'
    models=[td/'sim_release'/s for s in ['common/al_phy_glbl.v','ph1/ph1_logic_dram.v','ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v']]
    names=['reset_release_sync','td_sdp_ram40','hdr_pair_directory','raw10_frame_replay','stereo_raw_owner','stereo_raw_reader','stereo_raw_store','raw_capture_fifo_eram_safe','shared_raw10_frame_ingress','shared_raw_capture_writer','full_raw_capture_frontend','dual_raw_capture_frontend','dol2_axi_write_arbiter','raw10_append5','hdr_pair_context_cache','raw_pair_replay_scheduler','raw_hdr_phase_scheduler4','raw_pair_job_service','hdr_pair_bank_owner','hdr_pair_bank_owner_dual','hdr_eye_shared','hdr_pair_bank_owner_serial','raw_application_stop_dfi','axis_frame_fifo_ip','full_raw_store']
    sources=[td/'sim_release/ph1/ph1_phy_gsr.v',ip/'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',ip/'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v', ip/'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v',ip/'camera_packet_fifo_147x512/camera_packet_fifo_147x512.v']+[rtl/(n+'.v') for n in names]+[CASE/'tb_hdr_commit_contract.sv']
    paths=sources+models+[Path(__file__),rtl/'include/04_include/pcie_protocol_v1.vh']
    inputs=[dict(path=str(p.resolve()),sha256=sha(p)) for p in paths]
    result=dict(status='RUNNING',inputs=inputs,source_seal_sha256=SEAL_SHA,scope=__doc__,synthesis='NOT_RUN',physical='NOT_RUN',board='NOT_RUN');started=time.time()
    def verify(filename):
        rows=[dict(path=k,expected_sha256=v,actual_sha256=sha(PROJECT/k)) for k,v in seal['production_inputs'].items()]
        bad=[r['path'] for r in rows if r['expected_sha256']!=r['actual_sha256']]
        (run/filename).write_text(json.dumps(dict(status='FAIL' if bad else 'PASS',inputs=rows,mismatches=bad),indent=2)+'\n')
        if bad or sha(sealpath)!=SEAL_SHA:raise RuntimeError('Production source drift')
    def call(name,command):
        done=subprocess.run([str(s) for s in command],cwd=run,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        (run/name).write_text(done.stdout,encoding='utf-8')
        if done.returncode:raise RuntimeError(done.stdout[-7000:])
        return done.stdout
    try:
        verify('SOURCE_START.json')
        call('vlib_ph1.log',[ms/'vlib.exe','ph1']);call('vlib_work.log',[ms/'vlib.exe','work'])
        call('models.log',[ms/'vlog.exe','-work','ph1',*models])
        call('compile.log',[ms/'vlog.exe','-sv','+define+PH1','+incdir+'+(rtl/'include/04_include').as_posix(),*sources])
        text=call('run.log',[ms/'vsim.exe','-c','-L','ph1','work.PH1_PHY_GSR','work.tb_hdr_commit_contract','-do','run -all; quit -f'])
        if 'RESULT: PASS HDR_COMMIT_CONTRACT' not in text or re.search(r'\*\* (Error|Fatal):',text):raise RuntimeError(text[-7000:])
        for row in inputs:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('Test input drift')
        result.update(status='PASS',summary=next(line for line in text.splitlines() if 'RESULT: PASS' in line))
        print(result['summary'],flush=True)
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        try:verify('SOURCE_END.json')
        except Exception as error:result.update(status='SOURCE_DRIFT',source_end_error=str(error))
        result['elapsed_seconds']=time.time()-started;(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
