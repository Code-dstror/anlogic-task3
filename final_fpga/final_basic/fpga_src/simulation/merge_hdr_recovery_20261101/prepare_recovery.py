"""Create one HDR-only recovery; retain the original frozen campaign unchanged."""
from pathlib import Path
import hashlib
import json

EXT=Path(__file__).resolve().parent
PROJECT=EXT.parents[2]
OLD=EXT.parent/'merge_integration_20261101'
if (EXT/'PROVENANCE.json').exists():raise RuntimeError('Do not overwrite a prepared recovery')
files=['binding.py','freeze.py','supervise.py','launch.ps1','test_controller.py',
       'c1_reference_frozen.py','PROTOCOL_REFERENCE.json','HDR_INPUT_PLAN.json','word_phy_extended.sv',
       'hdr_startup/run.py','hdr_startup/tb.sv','hdr_startup/oracle.py',
       'hdr_startup/extended_uart_decode.vh','hdr_startup/runtime_recovery/top_runtime.vh']
files += ['protocol_reference/'+p.relative_to(OLD/'protocol_reference').as_posix()
          for p in sorted((OLD/'protocol_reference').rglob('*.py'))]
rows=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for relative in files:
    source=OLD/relative;target=EXT/relative;target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(source.read_bytes())
    rows.append(dict(path=relative,donor_path=source.relative_to(PROJECT.parents[1]).as_posix(),donor_sha256=sha(source)))
def change(relative,old,new,count=1):
    path=EXT/relative;body=path.read_text(encoding='utf-8-sig')
    if body.count(old)!=count:raise RuntimeError(f'{relative}: {old!r} count {body.count(old)} != {count}')
    path.write_text(body.replace(old,new),encoding='utf-8',newline='\n')
change('binding.py','docs/EXTENDED_SIMULATION_20261101.lock.json','docs/EXTENDED_SIMULATION_20261101.hdr_recovery.lock.json')
change('freeze.py',"campaign='dual_hdr_merge_r1_integration_20261101'","campaign='dual_hdr_merge_r1_hdr_recovery_20261101'")
change('freeze.py',"    for row in provenance['files']:","    for row in provenance['files']:")
change('freeze.py',"max_parallel=2, case_wall_limit_seconds=10800, total_wall_limit_seconds=21600", "max_parallel=1, case_wall_limit_seconds=10800, total_wall_limit_seconds=21600,\n                  original_plan_deadline_epoch=1793534251.7473004")
change('supervise.py',"REGISTRY = PROJECT / 'tmp/extended_20261101'","REGISTRY = PROJECT / 'tmp/extended_hdr_recovery_20261101'\nORIGINAL_START=1793512651.7473004\nORIGINAL_DEADLINE=1793534251.7473004")
change('supervise.py',"CASES = ('hdr', 'sdr')","CASES = ('hdr',)")
change('supervise.py',"stem = f'{case}_merge_r{attempt}'","stem = f'{case}_recovery_r{attempt}'")
change('supervise.py',"max_parallel=2, case_wall_limit_seconds=10800", "max_parallel=1, case_wall_limit_seconds=10800")
change('supervise.py','plan_deadline_epoch=time.time()+10800','plan_deadline_epoch=min(time.time()+10800, ORIGINAL_DEADLINE)')
change('supervise.py',"state.update(phase='FULL', plan_started_epoch=time.time(), plan_deadline_epoch=time.time()+21600,", "state.update(phase='FULL', plan_started_epoch=ORIGINAL_START, recovery_started_epoch=time.time(), plan_deadline_epoch=ORIGINAL_DEADLINE,")
change('supervise.py',"entry['status'] == 'QUEUED' and active < 2", "entry['status'] == 'QUEUED' and active < 1")
change('supervise.py',"    verify(bound)\n    REGISTRY.mkdir", "    verify(bound)\n    if time.time() >= ORIGINAL_DEADLINE:raise RuntimeError('Original six-hour campaign deadline has expired')\n    REGISTRY.mkdir")
change('launch.ps1','docs/EXTENDED_SIMULATION_20261101.lock.json','docs/EXTENDED_SIMULATION_20261101.hdr_recovery.lock.json')
change('launch.ps1','tmp/extended_20261101','tmp/extended_hdr_recovery_20261101')
change('hdr_startup/run.py',"ROOT / 'tmp' / 'extended_20261101' / a.name", "ROOT / 'tmp' / 'extended_hdr_recovery_20261101' / a.name")
change('hdr_startup/tb.sv','    integer input_ledger_fd,expected_input_sequence;', '    integer input_ledger_fd,expected_input_sequence;\n    integer member_finishes0=0,member_finishes1=0;')
change('hdr_startup/tb.sv','    always @(posedge dut.dfi_clk)if(dut.dfi_rst_n)begin\n        if(dut.raw_commit_valid', '''    always @(posedge dut.dfi_clk)if(dut.dfi_rst_n)begin
        if(dut.g_s04.u_raw_service.finish_valid&&dut.g_s04.u_raw_service.finish_ready)begin
            check(dut.g_s04.u_raw_service.finish_ok,"LONG real writer finish must be successful");
            check(dut.g_s04.u_raw_service.capture_frame[2:1]==1&&
                dut.g_s04.u_raw_service.capture_frame[108:77]==10&&
                dut.g_s04.u_raw_service.capture_frame[76:45]==member_session[0]&&
                dut.g_s04.u_raw_service.capture_frame[140:109]==member_epoch[0]&&
                dut.g_s04.u_raw_service.capture_frame[366:335]==10,
                "LONG completed DDR descriptor preserves independent input SOURCE10");
            member_finishes0++;
            $fdisplay(event_fd,"HDR_MEMBER_FINISH role=LONG session=%0d epoch=%0d sequence=10 group=10 ok=1",member_session[0],member_epoch[0]);
        end
        if(dut.g_s04.u_raw_service.finish_valid1&&dut.g_s04.u_raw_service.hdr_finish1_ready)begin
            check(dut.g_s04.u_raw_service.finish_ok1,"SHORT real writer finish must be successful");
            check(dut.g_s04.u_raw_service.capture_frame1[2:1]==2&&
                dut.g_s04.u_raw_service.capture_frame1[108:77]==10&&
                dut.g_s04.u_raw_service.capture_frame1[76:45]==member_session[1]&&
                dut.g_s04.u_raw_service.capture_frame1[140:109]==member_epoch[1]&&
                dut.g_s04.u_raw_service.capture_frame1[366:335]==10,
                "SHORT completed DDR descriptor preserves independent input SOURCE10");
            member_finishes1++;
            $fdisplay(event_fd,"HDR_MEMBER_FINISH role=SHORT session=%0d epoch=%0d sequence=10 group=10 ok=1",member_session[1],member_epoch[1]);
        end
        if(dut.raw_commit_valid''')
change('hdr_startup/tb.sv','            raw_pins++;','            check(member_finishes0==1&&member_finishes1==1,"pair acquire follows both actual successful DDR member completions");\n            raw_pins++;')
change('hdr_startup/tb.sv','check(raw_commits==2&&member_sequence[0]==10&&member_sequence[1]==10&&', 'check(raw_commits==1&&member_finishes0==1&&member_finishes1==1&&member_sequence[0]==10&&member_sequence[1]==10&&')
change('hdr_startup/tb.sv','"two actual committed member identities survive one pair acquisition"', '"two real DDR member completions and one legacy LONG observation preserve one acquired pair"')
change('hdr_startup/tb.sv','            check(`R8_MEM.accepted_aw==`R8_MEM.accepted_b,"all physical HDR and JPEG write responses settled");', '''            $display("HDR_COMMIT_CONTRACT PASS member_finish=%0d/%0d legacy_long_commit=%0d pair_acquire=%0d",member_finishes0,member_finishes1,raw_commits,raw_pins);
            check(`R8_MEM.accepted_aw==`R8_MEM.accepted_b,"all physical HDR and JPEG write responses settled");''')
change('hdr_startup/oracle.py',"    starts = re.findall(",'''    finishes = re.findall(r'^HDR_MEMBER_FINISH role=(LONG|SHORT) session=(\\d+) epoch=(\\d+) sequence=10 group=10 ok=1$', events, re.M)
    need(len(finishes)==2 and {row[0] for row in finishes}=={'LONG','SHORT'}, 'Both actual successful DDR writer completions observed exactly once')
    for role, session, epoch in finishes:
        need((int(session),int(epoch))==(fields['source_session'],fields['source_epoch']),role+' DDR completion identity matches frozen pre-DDR SOURCE')
    need('HDR_COMMIT_CONTRACT PASS member_finish=1/1 legacy_long_commit=1 pair_acquire=1' in log,'Exact legacy-LONG observation and dual-member finish contract')
    starts = re.findall(''')
for row in rows:row['sha256']=sha(EXT/row['path'])
(EXT/'PROVENANCE.json').write_text(json.dumps(dict(source_kind='LOCAL_SEALED_TREE_NOT_PUSHED',
    source_seal_sha256='9f1be00097a6ab21889720cf6cfb8ee353cb34fffaab366df4369a63b93af03d',
    donor_qualification_inherited=False,original_failed_campaign='tmp/extended_20261101/hdr_merge_r1_full',
    old_test_lock_sha256='7054c8be8b3c7744164f1f53ae917444ef2fa6180516ea233b1e4ac9bbeb61d2',files=rows),indent=2)+'\n')
print('PREPARED_HDR_ONLY_RECOVERY',len(rows))
