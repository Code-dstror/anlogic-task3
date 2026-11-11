"""R4/current zero-cycle admission and observer control miters."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REPO = ROOT.parents[1]
BASE = 'a62cdc6fd5e552752f7243305970d1aeedabff75'
RTL = ROOT / 'src_fpga/rtl'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ports(source, module):
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    start = text.index('module ' + module)
    at = text.index('(', start)
    if text[start:at].rstrip().endswith('#'):
        depth = 1
        pos = at + 1
        while depth:
            depth += (text[pos] == '(') - (text[pos] == ')')
            pos += 1
        at = text.index('(', pos)
    end = text.index(');', at)
    result = []
    direction = width = ''
    for item in text[at+1:end].split(','):
        item = item.strip()
        match = re.match(r'(input|output)\s+', item)
        if match:
            direction = match[1]
            item = item[match.end():]
            item = re.sub(r'^(?:(?:reg|wire|signed)\s+)+', '', item)
            match = re.match(r'\[[^\]]+\]', item)
            width = match[0] if match else ''
            if match:
                item = item[match.end():].strip()
        assert direction and re.fullmatch(r'\w+', item), item
        result.append((direction, width, item))
    return result


def wrapper(run, module, params, states, controls):
    path = RTL / (module + '.v')
    raw = subprocess.check_output(['git', 'show', BASE + ':' + path.relative_to(REPO).as_posix()], cwd=REPO)
    old = run / ('r5_ref_' + module + '.v')
    old.write_text(raw.decode().replace('module ' + module, 'module r5_ref_' + module, 1))
    pp = ports(path.read_text(), module)
    out = [(w, n) for d, w, n in pp if d == 'output']
    declarations = ',\n'.join(d + ' wire ' + w + ' ' + n for d, w, n in pp)
    param = '#(' + ','.join('parameter integer ' + p + '=' + str(v) for p, v in params.items()) + ')'
    forwards = '#(' + ','.join('.' + p + '(' + p + ')' for p in params) + ')'
    text = 'module r5_miter_' + module + ' ' + param + '(\n' + declarations + '\n);\n'
    text += '\n'.join('wire ' + w + ' ref_' + n + ';' for w, n in out) + '\n'
    for name, prefix in [(module, ''), ('r5_ref_' + module, 'ref_')]:
        conn = ','.join('.' + n + '(' + (prefix if d == 'output' else '') + n + ')' for d, w, n in pp)
        text += name + ' ' + forwards + ' ' + ('device' if not prefix else 'reference') + '(' + conn + ');\n'
    output_tuple = lambda prefix: '{' + ','.join(prefix + n for w, n in out) + '}'
    state_tuple = lambda prefix: '{' + ','.join(prefix + '.' + n for n in states) + '}'
    control_tuple = lambda prefix: '{' + ','.join(prefix + '.' + n for n in controls) + '}'
    text += 'integer miter_edges=0;\n'
    text += 'task compare_state;begin\n'
    text += 'if(' + output_tuple('') + '!==' + output_tuple('ref_') + ')$fatal(1,"R5 ' + module + ' public output mismatch");\n'
    text += 'if(' + state_tuple('device') + '!==' + state_tuple('reference') + ')$fatal(1,"R5 ' + module + ' internal state mismatch");\n'
    text += 'if(' + control_tuple('device') + '!==' + control_tuple('reference') + ')$fatal(1,"R5 ' + module + ' transfer/control mismatch");\n'
    text += 'miter_edges=miter_edges+1;end endtask\n'
    text += 'always @(posedge i_clk)begin if(i_rst_n)compare_state();#0.1;compare_state();end\n'
    text += 'always @(negedge i_clk or negedge i_rst_n)begin #0.1;compare_state();end\n'
    text += 'final $display("RESULT: PASS R5 ' + module + ' compared_edges=%0d",miter_edges);\nendmodule\n'
    generated = run / ('r5_miter_' + module + '.sv')
    generated.write_text(text)
    return [path, old, generated], pp


def random_bench(run, module, pp):
    text = 'module r5_random_' + module + ';\n'
    text += '\n'.join(('reg ' if d == 'input' else 'wire ') + w + ' ' + n + ('=0' if d == 'input' else '') + ';' for d, w, n in pp) + '\n'
    text += 'always #4 i_clk=~i_clk;\nr5_miter_' + module + ' dut(.*);\ninteger n;\ninitial begin\n'
    text += 'repeat(4)@(negedge i_clk);i_rst_n=1;\nfor(n=0;n<12000;n=n+1)begin\n@(negedge i_clk);\n'
    for d, w, name in pp:
        if d == 'input' and name not in ['i_clk', 'i_rst_n']:
            text += name + '={$random,$random,$random,$random,$random};\n'
    if module == 'neutral_observer':
        text += 'i_width=18;i_height=12;i_tap_valid=($random&3)!=0;i_tap_sof=n%79==0;i_tap_keep=15;i_source_abort=n%101==0;\n'
    else:
        text += 'i_session_armed=1;i_app_enable=1;i_fault=n%501==0;i_credit_grant=1;i_rgb_valid=($random&3)!=0;i_rgb_sof=n%19==0;\n'
        text += 'i_camera_done=n%17==0;i_camera_error=n%173==0;i_result_valid=n%23==0;i_result_id=dut.device.capture_id;i_result_ready=1;\n'
    text += 'i_rst_n=n%257!=0;\nend\n@(negedge i_clk);i_rst_n=0;repeat(3)@(negedge i_clk);\n'
    text += '$display("RESULT: PASS R5 randomized ' + module + ' cycles=12000 resets=47");$finish;end\nendmodule\n'
    path = run / ('r5_random_' + module + '.sv')
    path.write_text(text)
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', required=True, type=Path)
    ap.add_argument('--modelsim-bin', required=True, type=Path)
    a = ap.parse_args()
    assert re.fullmatch(r'r5_[a-z0-9_]+', a.name)
    run = ROOT / 'tmp/r5_data_control' / a.name
    run.mkdir(parents=True, exist_ok=False)
    targets, pp = wrapper(run, 'neutral_observer', {'SOURCE_WIDTH': 18, 'SOURCE_HEIGHT': 12},
        ['state','reset_release','source_x','source_y','observation_x','phase_x','phase_y','source_complete',
         'queued_pixels','sampled_pixels','delivered_pixels','dark_pixels','bright_pixels','sum_y','dropped_frames',
         'min_y','max_y','error_code','context_locked','exposure_locked','gain_locked','width_locked','height_locked'],
        ['fifo_write_enable','fifo_read_enable','fifo_write_data','capture_fault','current_fault','state_next'])
    random_observer = random_bench(run, 'neutral_observer', pp)
    extra, pp = wrapper(run, 'jpeg_frame_admission', {'EXTERNAL_SEQUENCE_ENABLE': 0, 'SHARED_LUMA_ENABLE': 0},
        ['state','capture_id','start_time','end_seen','bad_seen','encoder_started','credit_request',
         'buf_valid','buf_sof','buf_eol','buf_data','buf_luma'], ['push','pop','result_fire','matching_result'])
    targets += extra
    random_admission = random_bench(run, 'jpeg_frame_admission', pp)
    edge_source = 'src_fpga/simulation/tb_neutral_observer_edges.v'
    text = subprocess.check_output(['git','show',BASE+':'+edge_source],cwd=REPO).decode()
    text = text.replace('neutral_observer #(', 'r5_miter_neutral_observer #(')
    text = re.sub(r'\bdut\.', 'dut.device.', text)
    text = re.sub(r'((?:force|release) dut\.device\.[^;]+;)', lambda m:m[0]+'\n'+m[0].replace('dut.device.','dut.reference.'), text)
    edge = run / 'r5_neutral_edges.sv';edge.write_text(text)
    bench = HERE / 'tb_admission_restart.sv'
    admission_text = bench.read_text().replace('jpeg_frame_admission #(', 'r5_miter_jpeg_frame_admission #(')
    restart = run / 'r5_admission_restart.sv';restart.write_text(admission_text)
    latch = run / 'actual_restart_latch.vh';latch.write_text('always @(posedge pixel_clk) begin if(admission_state_idle) admitted_restart<=job_restart;end\n')
    models = [a.td_root/'sim_release'/p for p in ['common/al_phy_glbl.v','ph1/ph1_phy_gsr.v','ph1/ph1_logic_eram.v',
        'ph1/ph1_phy_eram.v','ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_fifoctrl.v']]
    fifo = [ROOT/'src_fpga/ip'/p for p in ['camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v','camera_control_fifo_40x512/camera_control_fifo_40x512.v']]
    fifo.append(RTL/'control_fifo_40x512.v')
    sources = fifo + targets + [edge,restart,random_observer,random_admission]
    identity = [{'path':str(p.resolve()),'sha256':sha(p)} for p in models+sources+[Path(__file__),bench,latch]]
    result = {'status':'RUNNING','baseline':BASE,'inputs':identity,'new_state_bits':0,'latency_change_cycles':0,
        'asynchronous_reset_processes':'UNCHANGED','synthesis':'NOT_RUN','physical_timing':'NOT_RUN','board':'NOT_RUN','tests':[]}
    def command(label, executable, args):
        completed = subprocess.run([str(a.modelsim_bin/executable), *[str(x) for x in args]],cwd=run,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
        (run/(label+'.console.log')).write_text(completed.stdout)
        if completed.returncode:
            raise RuntimeError(label+': '+completed.stdout[-7000:])
    try:
        command('map','vmap.exe',['-c'])
        for lib in ['work','ph1']:
            command('lib_'+lib,'vlib.exe',[lib]);command('map_'+lib,'vmap.exe',[lib,lib])
        command('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        command('compile','vlog.exe',['-quiet','-sv','+define+PH1','+incdir+'+str(run),'-timescale','1ns/1ps','-l','compile.log',*sources])
        tests = [('neutral_small','tb_neutral_observer_edges',['-gSOURCE_WIDTH=18','-gSOURCE_HEIGHT=12']),
            ('neutral_full','tb_neutral_observer_edges',['-gSOURCE_WIDTH=1920','-gSOURCE_HEIGHT=1080']),
            ('admission_restart','tb_admission_restart',[]),
            ('neutral_random','r5_random_neutral_observer',[]),('admission_random','r5_random_jpeg_frame_admission',[])]
        for label, top, args in tests:
            command(label,'vsim.exe',['-c','-L','ph1','ph1.PH1_PHY_GSR','ph1.glbl','work.'+top,*args,'-l',label+'.log','-do','run -all;quit -f'])
            log = (run/(label+'.log')).read_text()
            assert 'RESULT: PASS' in log and not re.search(r'\*\* (?:Warning|Error|Fatal):',log), log[-7000:]
            result['tests'].append({'name':label,'metrics':[line.strip('# ') for line in log.splitlines() if 'RESULT: PASS' in line]})
        for name in ['models.log','compile.log']:
            assert not re.search(r'\*\* (?:Warning|Error|Fatal):',(run/name).read_text()),name
        for row in identity:
            assert sha(Path(row['path']))==row['sha256'],'Input changed: '+row['path']
        result['status']='PASS'
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],'tests':result['tests'],'result':str(run/'RESULTS.json')},indent=2))


if __name__ == '__main__':
    main()
