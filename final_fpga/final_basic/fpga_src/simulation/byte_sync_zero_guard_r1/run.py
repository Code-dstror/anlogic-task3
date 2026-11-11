"""Isolated full-zero-preamble byte-acquisition A/B; no board-cause claim."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,re,subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE=HERE/'packet_fixture.py'
spec=importlib.util.spec_from_file_location('base_repro',BASE)
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)

def shifted(words,shift):
    result=[];previous=0xffffffff
    for word in words:
        new=0
        for lane in range(4):
            b=word>>(8*lane)&255;p=previous>>(8*lane)&255
            new|=(((b<<shift)|(p>>(8-shift)))&255 if shift else b)<<(8*lane)
        result.append(new);previous=word
    return result

def cases():
    cases=[]
    # Original31 boundary scenarios at every physical bit phase.
    for shift in range(8):
        for original in base.cases():
            c={k:v for k,v in original.items() if k!='raw'}
            c.update(id=len(cases),family='original31',shift=shift,offset=(shift-1)%8,
                     name=f'phase{shift}_{original["name"]}',raw=shifted(original['raw'],shift))
            cases.append(c)
    # One lane sees a B8 whose preceding logical byte is01, not00.
    # Old offsets0..6 only test the predecessor's high1..7 bits, all zero.
    # It precedes the real four-lane clean sync by6..12 byte clocks.
    for shift in range(8):
        for lead in range(6,13):
            raw=base.cases()[0]['raw'];syncs=[i for i,w in enumerate(raw) if w==0xb8b8b8b8]
            true_sync=syncs[2];false_sync=true_sync-lead
            raw[false_sync-1]=(raw[false_sync-1]&0xffffff00)|1
            raw[false_sync]=(raw[false_sync]&0xffffff00)|0xb8
            cases.append(dict(id=len(cases),family='false_prelude',shift=shift,offset=(shift-1)%8,
                lead=lead,name=f'false_phase{shift}_lead{lead}',false_sync_logical_cycle=false_sync,
                true_sync_logical_cycle=true_sync,predecessor_byte=1,raw=shifted(raw,shift)))
    # Minimal admitted contract: exactly eight stable zero bits before sync,
    # rather than the three zero bytes used by the original boundary fixture.
    for shift in range(8):
        original=base.cases()[0];raw=original['raw']
        for i,w in enumerate(raw):
            if w==0xb8b8b8b8:raw[i-3]=raw[i-2]=0xffffffff
        c={k:v for k,v in original.items() if k!='raw'}
        c.update(id=len(cases),family='exact8zero',shift=shift,offset=(shift-1)%8,
            name=f'exact8zero_phase{shift}',raw=shifted(raw,shift));cases.append(c)
    return cases

BENCH=r'''`timescale 1ns/1ps
module chain #(parameter CANDIDATE=0)(input wire clk,rst,input wire [31:0] raw);
 wire [31:0] bd,aw,gw;wire [3:0] lv,found;wire [11:0] offsets,taps;wire av,gv,ws,pd;
 wire [39:0] data;wire valid,sof,eol,abort_frame;wire [3:0] error;
 wire [127:0] parser;wire ecc_error,crc_error,len_error,identity_fault;wire [31:0] sequence_id;
 genvar l;
 generate for(l=0;l<4;l=l+1)begin:g_byte
  if(CANDIDATE)begin:g_new
   csi_rx_byte_align_fullzero u(.I_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
   .I_lan_data_in(raw[8*l+:8]),.I_wait_for_sync(ws),.I_packet_done(pd),
   .O_data_out_vaild(lv[l]),.O_data_out(bd[8*l+:8]),.o_diag_offset(offsets[3*l+:3]),.o_diag_found(found[l]));
  end else begin:g_old
   csi_rx_byte_align_observed u(.I_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
   .I_lan_data_in(raw[8*l+:8]),.I_wait_for_sync(ws),.I_packet_done(pd),
   .O_data_out_vaild(lv[l]),.O_data_out(bd[8*l+:8]),.o_diag_offset(offsets[3*l+:3]),.o_diag_found(found[l]));
  end
 end endgenerate
 csi_rx_word_align_observed #(.MIPI_LAN(4)) wa(.I_word_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
  .I_packet_done(pd),.I_wait_for_sync(ws),.O_packet_done_out(),.I_word_in(bd),.I_valid_in(lv),
  .O_word_out(aw),.O_valid_out(av),.o_diag_taps(taps));
 csi_rx_word_gear_box #(.MIPI_LAN(4)) gb(.I_word_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
  .I_lane_data(aw),.I_lane_data_valid(av),.O_word_out(gw),.O_valid_out(gv));
 physical_csi_word_core #(.FRAME_EVENTS_ENABLE(1),.FRAME_RESYNC_ENABLE(1)) p(
  .i_clk(clk),.i_reset_n(rst),.i_identity_rst_n(rst),.o_source_sequence_count(sequence_id),
  .o_identity_fault(identity_fault),.o_identity_diag(),.o_trace_parser(),.o_trace_trigger(),
  .i_word(gw),.i_word_valid(gv),.i_sink_ready(1'b1),.o_data(data),.o_valid(valid),.o_sof(sof),.o_eol(eol),
  .o_abort(abort_frame),.o_error_code(error),.o_header_ecc_error(ecc_error),.o_payload_crc_error(crc_error),
  .o_length_error(len_error),.o_wait_for_sync(ws),.o_packet_done(pd));
 // Testbench-only passive observations; production keeps its compact ABI.
 assign parser[31:0]=gw;
 assign parser[55:32]=p.hc;
 assign parser[61:56]=p.syn;
 assign parser[63:62]=p.state;
 assign parser[95:64]=p.sequence_counter;
 assign parser[96]=rst&&gv&&p.state==0;
 assign parser[97]=p.good;
 assign parser[98]=ecc_error;
 assign parser[99]=crc_error;
 assign parser[100]=len_error;
 assign parser[101]=valid&&abort_frame&&error==3;
 assign parser[102]=!p.sequence_trusted;
 assign parser[127:103]=0;
 integer headers,raw_packets,fs,fe,pixels,lines,aborts,fsout,feout,badheader,crcerr,lenerr,drop;
 reg [7:0] offset_seen;
 always @(posedge clk)begin
  if(!rst)begin
   headers=0;raw_packets=0;fs=0;fe=0;pixels=0;lines=0;aborts=0;fsout=0;feout=0;
   badheader=0;crcerr=0;lenerr=0;drop=0;offset_seen=0;
  end else begin
   if(parser[96])begin
    headers=headers+1;
    if(!parser[97])badheader=badheader+1;
    else if(parser[39:32]==8'h2b)raw_packets=raw_packets+1;
    else if(parser[39:32]==0)fs=fs+1;
    else if(parser[39:32]==1)fe=fe+1;
   end
   if(parser[99])crcerr=crcerr+1;if(parser[100])lenerr=lenerr+1;if(parser[101])drop=drop+1;
   if(av)offset_seen[offsets[2:0]]=1;
   if(valid)begin
    if(abort_frame)aborts=aborts+1;
    else if(error==7)fsout=fsout+1;
    else if(error==6)feout=feout+1;
    else if(error==0)begin
     if(data!=={4{10'h155}})$fatal(1,"actual RAW10 samples mismatch candidate=%0d",CANDIDATE);
     pixels=pixels+1;if(eol)lines=lines+1;
    end
   end
  end
 end
endmodule
module tb;
 parameter integer CASES=1,STEPS=2500;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;reg [31:0] raw=32'hffffffff;
 chain #(.CANDIDATE(0)) old(clk,rst,raw);chain #(.CANDIDATE(1)) candidate(clk,rst,raw);
 reg [31:0] stimulus[0:CASES*STEPS-1];
 integer id,n;
 reg [3:0] old_lv,new_lv,old_found,new_found;
 reg old_wa,new_wa;
 initial begin
  $readmemh("raw.hex",stimulus);
  for(id=0;id<CASES;id=id+1)begin
   rst=0;raw=32'hffffffff;repeat(8)@(negedge clk);rst=1;
   old_lv=0;new_lv=0;old_found=0;new_found=0;old_wa=0;new_wa=0;
   for(n=0;n<STEPS;n=n+1)begin
    raw=stimulus[id*STEPS+n];@(posedge clk);#1;
    if(id==255 && (old_lv!=old.lv||new_lv!=candidate.lv||old_found!=old.found||new_found!=candidate.found||old_wa!=old.wa.r_valid||new_wa!=candidate.wa.r_valid))
     $display("TRACE id=%0d cycle=%0d raw=%08h oldfound=%h newfound=%h oldlv=%h newlv=%h oldwa=%0d newwa=%0d oldws=%0d newws=%0d oldtaps=%h newtaps=%h",id,n,raw,old.found,candidate.found,old.lv,candidate.lv,old.wa.r_valid,candidate.wa.r_valid,old.ws,candidate.ws,old.taps,candidate.taps);
    old_lv=old.lv;new_lv=candidate.lv;old_found=old.found;new_found=candidate.found;old_wa=old.wa.r_valid;new_wa=candidate.wa.r_valid;
    @(negedge clk);
   end
   $display("CASE id=%0d oldraw=%0d newraw=%0d oldpixels=%0d newpixels=%0d oldlines=%0d newlines=%0d oldfs=%0d newfs=%0d oldfe=%0d newfe=%0d oldabort=%0d newabort=%0d oldbad=%0d newbad=%0d oldcrc=%0d newcrc=%0d oldlen=%0d newlen=%0d olddrop=%0d newdrop=%0d oldfault=%0d newfault=%0d oldfsout=%0d newfsout=%0d oldfeout=%0d newfeout=%0d oldoffsetmask=%0d newoffsetmask=%0d",id,old.raw_packets,candidate.raw_packets,old.pixels,candidate.pixels,old.lines,candidate.lines,old.fs,candidate.fs,old.fe,candidate.fe,old.aborts,candidate.aborts,old.badheader,candidate.badheader,old.crcerr,candidate.crcerr,old.lenerr,candidate.lenerr,old.drop,candidate.drop,old.identity_fault,candidate.identity_fault,old.fsout,candidate.fsout,old.feout,candidate.feout,old.offset_seen,candidate.offset_seen);
  end
  $display("RESULT: HARNESS_COMPLETE");$finish;
 end
endmodule
'''

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,default=Path('D:/App/modelsim/win64'));args=ap.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]*',args.name)
    run=ROOT/'tmp/byte_sync_zero_guard_r1'/args.name;run.mkdir(parents=True,exist_ok=False)
    report=dict(simulation='IN_PROGRESS',baseline_commit='5e302ae06ef4fff227e3030d31dc30e63b5dcb7e',guard_donor='2902a3f643527ca60ef410a38109376e118ef9a4',sources=[],commands=[],
      synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    try:
        sources=[]
        rt=ROOT/'src_fpga/rtl'
        actual=(rt/'csi_rx_byte_align_observed.v').read_bytes()
        assert hashlib.sha256(actual).hexdigest()=='9ca2c2a5151fd09825b1a02aeaaf14b4829750517e474564a476af6429bb6c6f'
        original=actual
        for k in range(7):
            bits='0' if k==0 else f'{k}:0'
            old=f'(r_lan_data_in_d1[{bits}] == 0)'.encode()
            guard=f'({{r_lan_data_in_d1[{bits}],r_lan_data_in_d2[7:{k+1}]}} == 8\'d0)'.encode()
            assert original.count(guard)==1
            original=original.replace(guard,old)
        assert hashlib.sha256(original).hexdigest()=='932cb8f33ce2b276e573ad714065b80d08722cda87b8109d681ba2c997964ec4'
        baseline=run/'csi_rx_byte_align_observed.v';baseline.write_bytes(original);sources.append(baseline)
        report['sources'].append(dict(path=str(rt/'csi_rx_byte_align_observed.v'),copied=str(baseline),sha256=hashlib.sha256(original).hexdigest(),change='Only seven guards reversed for A/B baseline',derived_baseline=True))
        for source in [rt/'csi_rx_word_align_observed.v', ROOT/'src_fpga/ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v',rt/'physical_csi_word_core.v']:
            content=source.read_bytes();dest=run/source.name;dest.write_bytes(content);sources.append(dest)
            report['sources'].append(dict(path=str(source),copied=str(dest),sha256=hashlib.sha256(content).hexdigest()))
        candidate=run/'csi_rx_byte_align_fullzero.v'
        candidate.write_bytes(actual.replace(b'module csi_rx_byte_align_observed(',b'module csi_rx_byte_align_fullzero('))
        sources.append(candidate)
        report['sources'].append(dict(path=str(rt/'csi_rx_byte_align_observed.v'),copied=str(candidate),production_sha256=hashlib.sha256(actual).hexdigest(),sha256=hashlib.sha256(candidate.read_bytes()).hexdigest(),change='Actual candidate; only module name changed for side-by-side instantiation',inverse_seven_guard_baseline_exact=True))
        report['fixture_dependency']=dict(path=str(BASE),sha256=hashlib.sha256(BASE.read_bytes()).hexdigest())
        cs=cases();steps=max(len(c['raw']) for c in cs)
        with (run/'raw.hex').open('w') as stream:
            for c in cs:
                for word in c['raw']+[0xffffffff]*(steps-len(c['raw'])):stream.write(f'{word:08x}\n')
                c.pop('raw')
        (run/'cases.json').write_text(json.dumps(cs,indent=2)+'\n');(run/'tb.sv').write_text(BENCH)
        def call(label,exe,argv):
            command=[str(args.modelsim_bin/exe),*map(str,argv)]
            p=subprocess.run(command,cwd=run,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=60)
            (run/(label+'.console.log')).write_text(p.stdout)
            report['commands'].append(dict(argv=command,cwd=str(run),returncode=p.returncode))
            if p.returncode:raise RuntimeError(label+' '+p.stdout[-6000:])
        call('version','vsim.exe',['-version']);call('vmap','vmap.exe',['-c']);call('vlib','vlib.exe',['work'])
        call('compile','vlog.exe',['-quiet','-sv','-l','compile.log',*sources,run/'tb.sv'])
        (run/'run.do').write_text('onerror {quit -code 1}\nonbreak {quit -code 1}\nrun -all\nquit -code 0 -f\n')
        call('run','vsim.exe',['-c','work.tb',f'-gCASES={len(cs)}',f'-gSTEPS={steps}','-voptargs=+acc','-l','run.log','-do','run.do'])
        log=(run/'run.log').read_text(errors='replace');rows=[]
        assert not re.search(r'\*\* (?:Error|Fatal|Warning):',log+(run/'compile.log').read_text(errors='replace'))
        for line in log.splitlines():
            if 'CASE id=' in line:
                r={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)};r.update(cs[r['id']]);rows.append(r)
        assert len(rows)==len(cs) and 'RESULT: HARNESS_COMPLETE' in log
        for r in rows:
            if r['family']=='false_prelude':
                oldexpected=3 if r['shift']==0 else 2;newexpected=3
            else:
                oldexpected=2 if (r['lost_lane']>=0 or r['skew']>=6 or
                  ('post_packet_gap_' in r['name'] and r['gap']<=6) or r['continuous']) else 3
                newexpected=oldexpected
            for prefix,expected in [('old',oldexpected),('new',newexpected)]:
                assert r[prefix+'raw']==r[prefix+'lines']==expected,r
                assert r[prefix+'pixels']==486*expected,r
                assert r[prefix+'fs']==r[prefix+'fe']==r[prefix+'fsout']==r[prefix+'feout']==1,r
                assert all(r[prefix+k]==0 for k in ['abort','bad','crc','len','drop','fault']),r
                assert r[prefix+'offsetmask']==(1<<r['offset']),r
        for item in report['sources']:
            if item.get('derived_baseline'):
                continue
            expected=item.get('production_sha256',item['sha256'])
            assert hashlib.sha256(Path(item['path']).read_bytes()).hexdigest()==expected
        report['test_inputs']=[dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in [Path(__file__),BASE]]
        report.update(simulation='PASS',cases=len(rows),results=rows,metrics=dict(original31_all8phases=248,
          false_nonzero_preamble_cases=56,old_silent_loss_candidate_full_recovery=49,offset7_negative_controls=7,
          exact8_stable_zero_bits_all_phases=8))
    except Exception as exc:
        report.update(simulation='FAIL',error=str(exc));raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(dict(run=str(run),simulation=report['simulation']),indent=2))
    print(json.dumps(report['metrics'],indent=2))
if __name__=='__main__':main()
