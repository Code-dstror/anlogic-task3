"""Directed stopped-clock A/B checks against the fixed 14df reset implementation."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]
BASE='14df01dcce'

OBSERVER=r'''
 task ticks(input integer n);begin repeat(n)@(negedge i_clk);#0.1;end endtask
 task frame;
 integer x,y,g;
 begin
  i_context=i_context+1;i_exposure=99;i_gain=7;i_width=18;i_height=12;
  i_pixel_ready=1;i_status_ready=0;
  for(y=0;y<12;y=y+1)for(x=0;x<18;x=x+4)begin
   @(negedge i_clk);i_tap_valid=1;i_tap_sof=(y==0&&x==0);
   i_tap_eol=x+4>=18;i_tap_eof=(y==11&&x+4>=18);
   i_tap_keep=x+4>=18 ? 3 : 15;i_tap_rgb={4{24'h456789}};i_tap_luma={4{8'd100}};
  end
  @(negedge i_clk);i_tap_valid=0;i_tap_sof=0;i_tap_eol=0;i_tap_eof=0;
  g=0;while(!o_status_valid&&g<200)begin ticks(1);g=g+1;end
  if(!o_status_valid||!o_status_ok||o_context!==i_context||o_status_pixels!=6)
   $fatal(1,"observer valid metadata/statistics recovery");
  ticks(3);
 end endtask
 integer phase;
 initial begin
  i_rst_n=0;i_width=18;i_height=12;i_pixel_ready=1;
  ticks(4);i_rst_n=1;ticks(14);
  for(phase=0;phase<8;phase=phase+1)begin
   frame();if(phase%2)@(posedge i_clk);else @(negedge i_clk);
   #0.1;clock_run=0;#(0.2+phase*0.4);i_rst_n=0;
   #0.1;if(o_status_valid||o_pixel_valid||o_reset_done)$fatal(1,"observer stopped assertion isolation");
   #1;i_rst_n=1;#17;
   if(o_status_valid||o_pixel_valid||o_reset_done)$fatal(1,"observer stopped premature release");
   clock_run=1;ticks(16);
  end
  frame();i_status_ready=1;ticks(6);
  $display("RESULT: PASS observer_reset_ab stopped_phases=8 complete_frames=9 checks=%0d",checks);$finish;
 end
'''

FENCE=r'''
 task ticks(input integer n);begin repeat(n)@(negedge clk);#0.1;end endtask
 task own;
 begin
  @(negedge clk);fence_lower_address=7'h40;fence_cookie=fence_cookie+1;fence_requester_id=16'h1234;fence_start=1;
  @(negedge clk);fence_start=0;
  if(!outstanding)$fatal(1,"fence owner did not open");
 end endtask
 task complete;
 begin
  @(negedge clk);rx_format=2;rx_type=5'h0a;rx_requester_id=fence_requester_id;rx_tag=10'h1a;
  rx_dword_length=1;rx_byte_count=4;rx_cpl_last=1;rx_address=64'h40;
  rx_data={96'd0,fence_cookie};rx_dwen=1;rx_hv=1;rx_dv=1;rx_eot=1;rc_ready=1;
  @(negedge clk);rx_hv=0;rx_dv=0;rx_eot=0;
  if(!rc_valid||fault||outstanding)$fatal(1,"fence exact completion failed");
  ticks(2);
 end endtask
 integer phase;
 initial begin
  rst_n=0;ticks(4);rst_n=1;ticks(3);
  for(phase=0;phase<8;phase=phase+1)begin
   own();if(phase%2)@(posedge clk);else @(negedge clk);
   #0.1;clock_run=0;#(0.2+phase*0.4);rst_n=0;
   #0.1;if(outstanding||rc_valid||fault)$fatal(1,"fence stopped async isolation");
   #1;rst_n=1;#17;
   if(outstanding||rc_valid||fault)$fatal(1,"fence stopped stale owner");
   clock_run=1;ticks(3);own();complete();
  end
  $display("RESULT: PASS fence_reset_ab stopped_phases=8 completed_fences=8 checks=%0d",checks);$finish;
 end
'''

TRANSPORT=r'''
 reg inject_write=0;reg [11:0] inject_address=0;reg [31:0] inject_data=0;
 initial begin
  force dut.reg_write=inject_write;force reference.reg_write=inject_write;
  force dut.reg_address=inject_address;force reference.reg_address=inject_address;
  force dut.reg_wdata=inject_data;force reference.reg_wdata=inject_data;
  force dut.reg_wstrb=4'hf;force reference.reg_wstrb=4'hf;
 end
 task ticks(input integer n);begin repeat(n)@(negedge i_clk);#0.1;end endtask
 task wr(input [11:0] a,input [31:0] d);
 begin @(negedge i_clk);inject_address=a;inject_data=d;inject_write=1;
 @(negedge i_clk);inject_write=0;#0.1;end endtask
 task arm;
 begin
  wr('h008,8);wr('h020,'h1000);wr('h024,0);wr('h028,4096);
  wr('h030,3);wr('h034,1);wr('h038,7);wr('h03c,0);wr('h040,'h9000);wr('h044,0);wr('h048,'h12345);wr('h008,1);
  if(!o_buffer_armed||dut.state!=1)$fatal(1,"transport descriptor did not arm");
 end endtask
 integer phase;
 initial begin
  i_rst_n=0;i_link_up=1;i_bme=1;i_cc_ready=1;ticks(4);i_rst_n=1;ticks(4);
  for(phase=0;phase<8;phase=phase+1)begin
   arm();if(phase%2)@(posedge i_clk);else @(negedge i_clk);
   #0.1;clock_run=0;#(0.2+phase*0.4);i_rst_n=0;
   #0.1;if(o_buffer_armed||o_record_ready||o_tlp_header_valid||o_tlp_data_valid||dut.state!=0)
    $fatal(1,"transport stopped async assertion isolation");
   #1;i_rst_n=1;#17;
   if(o_buffer_armed||o_record_ready||o_tlp_header_valid||o_tlp_data_valid)$fatal(1,"transport stale owner while stopped");
   clock_run=1;ticks(4);
  end
  arm();wr('h008,4);ticks(4);
  $display("RESULT: PASS transport_reset_ab stopped_phases=8 armed_grants=9 checks=%0d",checks);$finish;
 end
'''


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    a=ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}',a.name):ap.error('unsafe name')
    run=ROOT/'tmp/reset_r3'/a.name;run.mkdir(parents=True,exist_ok=False)
    helper_path=ROOT/'src_fpga/simulation/timing/r3_run_zero_latency.py'
    spec=importlib.util.spec_from_file_location('reset_header',helper_path)
    helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
    rtl=ROOT/'src_fpga/rtl';generated=[];baseline=[]
    for module,body,clock,reset in [('neutral_observer',OBSERVER,'i_clk','i_rst_n'),
                                  ('c2h_native_fence_listener',FENCE,'clk','rst_n'),
                                  ('c2h_native_rx_transport',TRANSPORT,'i_clk','i_rst_n')]:
        p=rtl/(module+'.v');raw=subprocess.check_output(['git','show',f'{BASE}:refactor/dual_lane_s1/src_fpga/rtl/{module}.v'],cwd=REPO)
        old=raw.decode().replace('module '+module,'module r3_ref_'+module,1)
        ref=run/('r3_ref_'+module+'.v');ref.write_text(old);generated.append(ref)
        baseline.append({'commit':BASE,'module':module,'sha256':hashlib.sha256(raw).hexdigest()})
        _,_,ports=helper.header(p.read_text(),module)
        outs=[(w,n) for d,w,n in ports if d=='output']
        text='`timescale 1ns/1ps\nmodule tb_'+module+';\n'
        text+='\n'.join(('reg ' if d=='input' else 'wire ')+w+' '+n+('=0;' if d=='input' else ',ref_'+n+';') for d,w,n in ports)+'\n'
        text+='reg clock_run=1;integer checks=0;\n'
        text+=f'initial forever begin if(clock_run){clock}=1;#2;if(clock_run){clock}=0;#6;end\n'
        params='#(.SOURCE_WIDTH(18),.SOURCE_HEIGHT(12))' if module=='neutral_observer' else ''
        for mod,inst,prefix in [(module,'dut',''),('r3_ref_'+module,'reference','ref_')]:
            text+=mod+' '+params+' '+inst+'('+','.join('.'+n+'('+(prefix if d=='output' else '')+n+')' for d,w,n in ports)+');\n'
        text+='task compare;begin checks=checks+1;\n'
        meta={'o_context','o_exposure','o_gain','o_source_width','o_source_height'} if module=='neutral_observer' else set()
        for w,n in outs:
            qualifier='(o_pixel_valid||o_status_valid)&&' if n in meta else ''
            if module=='c2h_native_rx_transport':
                if n=='o_fence_cookie':qualifier='(i_rst_n&&dut.state!=0)&&'
                elif n in {'o_tlp_data','o_tlp_address','o_tlp_byte_enable','o_tlp_byte_length','o_tlp_format','o_tlp_tag'}:
                    qualifier='(o_tlp_header_valid||o_tlp_data_valid)&&'
            text+=f'if({qualifier}({n}!==ref_{n}))$fatal(1,"{module} A/B output {n}");\n'
        text+='end endtask\n'
        text+=f'always @(posedge {clock} or negedge {clock} or negedge {reset})begin #0.05;compare();end\n'
        text+=body+'\ninitial begin #100000;$fatal(1,"reset A/B watchdog");end\nendmodule\n'
        bench=run/('tb_'+module+'.sv');bench.write_text(text);generated.append(bench)
    td=a.td_root;ip=ROOT/'src_fpga/ip'
    models=[td/'sim_release'/p for p in ['common/al_phy_glbl.v','ph1/ph1_logic_dram.v','ph1/ph1_logic_eram.v',
        'ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v']]
    sources=[td/'sim_release/ph1/ph1_phy_gsr.v',ip/'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        ip/'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v',ip/'camera_control_fifo_40x512/camera_control_fifo_40x512.v']
    sources += [rtl/(p+'.v') for p in ['control_fifo_40x512','neutral_observer','c2h_native_fence_listener',
        'c2h_native_rx_transport','c2h_bar_cq','c2h_native_packetizer','c2h_packet_ram','td_sdp_ram']]
    includes=[rtl/'include/04_include',rtl/'include/01_include']
    identity=[{'path':str(p),'sha256':sha(p)} for p in [*models,*sources,*generated,Path(__file__),helper_path]]
    result={'status':'IN_PROGRESS','baseline':baseline,'inputs':identity,'commands':[],
        'scope':'14DF_DIRECTED_RESET_AB_WITH_REAL_LEAVES_AND_TD_FIFO_MODEL','physical_timing':'NOT_RUN','board':'NOT_RUN'}
    def command(name,exe,words):
        argv=[str(a.modelsim_bin/exe),*map(str,words)];result['commands'].append(argv)
        r=subprocess.run(argv,cwd=run,capture_output=True,text=True,errors='replace',timeout=60)
        (run/(name+'.console.log')).write_text(r.stdout+r.stderr)
        if r.returncode:raise RuntimeError((r.stdout+r.stderr)[-6000:])
    try:
        command('map','vmap.exe',['-c'])
        for lib in ('work','ph1'):command(lib,'vlib.exe',[lib])
        command('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        command('rtl','vlog.exe',['-quiet','-sv','+define+PH1',*['+incdir+'+str(p) for p in includes],'-l','rtl.log',*sources,*generated])
        result['metrics']=[]
        for module in ('neutral_observer','c2h_native_fence_listener','c2h_native_rx_transport'):
            command(module,'vsim.exe',['-c','-voptargs=+acc','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_'+module,
                '-l',module+'.log','-do','onerror {quit -code 1};run -all;quit -f'])
            log=(run/(module+'.log')).read_text()
            assert 'RESULT: PASS ' in log and not re.search(r'\*\* (Error|Fatal):',log),log[-6000:]
            warnings=[line for line in log.splitlines() if '** Warning:' in line]
            assert all('ph1_logic_dram.v(221)' in line and 'INIT_FILE' in line and 'out of bounds' in line for line in warnings),warnings
            result.setdefault('known_td_model_warnings',[]).extend(warnings)
            result['metrics'] += [line.strip('# ') for line in log.splitlines() if 'RESULT: PASS' in line]
        for row in identity:assert sha(Path(row['path']))==row['sha256'],row['path']
        result['status']='PASS';print('\n'.join(result['metrics']))
    except Exception as error:result.update(status='FAIL',error=str(error));raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__':main()
