"""Observed aligners -> SDR first-loss trigger -> RAM -> SYS readback test."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
RTL = PROJECT / 'src_fpga/rtl'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def compact(text):
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    return re.sub(r'\s+', '', text)

def expression(text, name):
    found = re.search(r'\bassign\s+'+re.escape(name)+r'\s*=\s*(.*?);', text, re.S)
    if not found:
        raise RuntimeError('missing assignment: '+name)
    return compact(found.group(1))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        parser.error('unsafe run name')
    run = PROJECT / 'tmp/false_sot_trace' / args.name
    run.mkdir(parents=True, exist_ok=False)
    tb = HERE / 'tb_false_sot_trace.sv'
    receiver = RTL / 'real_hdr_physical_csi_rx.v'
    stream = RTL / 'physical_csi_rx_stream.v'
    camera = RTL / 'real_hdr_camera_observe_axis.v'
    top = RTL / 'anlogic2026.v'
    sources = [RTL / 'csi_rx_byte_align_observed.v', RTL / 'csi_rx_word_align_observed.v',
               PROJECT / 'src_fpga/ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v',
               RTL / 'physical_csi_word_core.v', RTL / 'rx_first_loss_trace.v', tb]
    bound = sources + [receiver, stream, camera, top, Path(__file__)]
    result = dict(status='IN_PROGRESS', simulation='NOT_RUN', synthesis='NOT_RUN',
                  place_route='NOT_RUN', timing='NOT_RUN', board='NOT_RUN',
                  scope='Digital PHY byte boundary; settled calibration. Injected extra lane3 SoT is not board evidence.',
                  inputs=[dict(path=str(p), sha256=sha(p)) for p in bound],
                  command=[sys.executable]+sys.argv, commands=[], structural_checks=[])
    def call(name, params):
        cmd = [str(args.modelsim_bin / name)] + [str(p) for p in params]
        row = dict(command=cmd, cwd=str(run), timeout_seconds=60)
        result['commands'].append(row)
        proc = subprocess.run(cmd, cwd=run, capture_output=True, text=True,
                              errors='replace', timeout=60)
        row['returncode'] = proc.returncode
        (run / ('command-%02d.log' % len(result['commands']))).write_text(
            proc.stdout+proc.stderr, encoding='utf-8')
        if proc.returncode:
            raise RuntimeError((proc.stdout+proc.stderr)[-8000:])
        return proc.stdout+proc.stderr
    def require(path, fragment):
        if compact(fragment) not in compact(path.read_text(errors='replace')):
            raise RuntimeError('production port/contract mismatch: '+str(path)+' '+fragment)
        result['structural_checks'].append(dict(path=str(path), exact_fragment=fragment, status='PASS'))
    try:
        real = receiver.read_text(errors='replace')
        test = tb.read_text()
        for name in ['o_rx_trace_sample', 'o_rx_trace_cohort_n', 'o_rx_trace_enable']:
            if expression(real, name) != expression(test, name):
                raise RuntimeError('TB/production expression mismatch: '+name)
            result['structural_checks'].append(dict(assignment=name,
                production_path=str(receiver), tb_path=str(tb), status='PASS'))
        require(receiver, '.O_diag_raw_bytes(trace_raw_bytes),.O_diag_byte_offset(trace_byte_offset)')
        require(receiver, '.O_diag_byte_found(trace_byte_found),.O_diag_calibration(trace_calibration)')
        require(receiver, 'csi_rx_word_align_observed #(.MIPI_LAN(MIPI_LAN)) u_word_align')
        require(receiver, '.o_diag_taps(trace_word_taps)')
        require(receiver, '.o_trace_parser(trace_parser),.o_trace_trigger(o_rx_trace_trigger)')
        require(stream, '.o_trace_parser(o_trace_parser),.o_trace_trigger(o_trace_trigger)')
        require(RTL / 'physical_csi_word_core.v',
                'assign o_trace_parser={frame_open,dropping,crc_lo_seen,o_packet_done,sequence_trusted,sequence_started,raw_packet,good,syn,left,state,sequence_counter};')
        for path, payload in [(camera, 'o_rx_trace'), (top, 'rx_trace')]:
            for field in ['sample', 'trigger', 'cohort_n', 'enable']:
                require(path, f'.o_rx_trace_{field}({payload}_{field})')
        require(top, '.i_cohort_rst_n(rx_trace_cohort_n),.i_enable(rx_trace_enable)')
        require(top, '.i_trigger(rx_trace_trigger),.i_sample(rx_trace_sample)')
        result['tool_version'] = call('vsim.exe', ['-version']).strip()
        call('vmap.exe', ['-c'])
        call('vlib.exe', ['work'])
        call('vmap.exe', ['work', 'work'])
        call('vlog.exe', ['-quiet', '-sv', '-l', 'compile.log']+sources)
        (run / 'run.do').write_text('onerror {quit -code 1}\nonbreak {quit -code 1}\nrun -all\nquit -code 0 -f\n')
        call('vsim.exe', ['-c', 'work.tb_false_sot_trace', '-l', 'run.log', '-do', 'run.do'])
        log = (run / 'run.log').read_text(errors='replace')
        if re.search(r'\*\*\s+(Error|Fatal):', log) or 'RESULT: PASS' not in log:
            raise RuntimeError(log[-12000:])
        rows = []
        for match in re.finditer(r'TRACE_READ index=(\d+) word_cycle=(\d+) mailbox=([0-9a-fA-F]{80})', log):
            index, cycle, word = int(match[1]), int(match[2]), int(match[3], 16)
            rows.append(dict(index=index, word_cycle=cycle, mailbox_hex=match[3],
                sample_hex=f'{word & ((1<<256)-1):064x}', geared=(word>>96)&0xffffffff,
                byte_word=(word>>32)&0xffffffff, aligned=(word>>64)&0xffffffff,
                lane3_tap=(word>>157)&7, sequence=(word>>160)&0xffffffff,
                parser_state=(word>>192)&3, syndrome=(word>>210)&63,
                generation=(word>>256)&65535, trigger_cycle=(word>>272)&0xffffffff))
        if len(rows)!=40 or [r['index'] for r in rows]!=list(range(40)):
            raise RuntimeError('missing chronological mailbox readback rows')
        (run / 'TRACE_READBACK.json').write_text(json.dumps(rows, indent=2)+'\n', encoding='utf-8')
        for item in result['inputs']:
            if sha(Path(item['path'])) != item['sha256']:
                raise RuntimeError('input changed: '+item['path'])
        result.update(status='PASS', simulation='PASS', sample_count=len(rows),
                      observations=[s for s in log.splitlines() if 'CASE ' in s or 'RESULT: PASS' in s],
                      readback=str(run / 'TRACE_READBACK.json'))
    except Exception as exc:
        result.update(status='FAIL', simulation='FAIL', error=str(exc))
        raise
    finally:
        (run / 'RESULTS.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
        print(json.dumps(dict(run=str(run), status=result['status'], error=result.get('error'))))

if __name__ == '__main__':
    main()
