"""Focused HDR overlap proof using the real ingress, writer and pair authority."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

PROJECT = Path(__file__).resolve().parents[1]
NAMES = ('real_hdr_pair_cycle_gate shared_raw10_frame_ingress raw10_append5 '
         'shared_raw_capture_writer hdr_pair_bank_owner_dual hdr_pair_directory td_sdp_ram40').split()
RX_NAMES = '''reset_release_sync csi_clock_watchdog csi_rx_byte_align_observed csi_rx_word_align_observed
real_hdr_csi_capture_stream real_hdr_csi_dual_word_rx real_hdr_csi_word_core hdr_csi_boundary_adapter
real_hdr_member_crop10 raw_capture_fifo_eram_safe real_hdr_pair_cycle_gate real_hdr_event_cdc
real_hdr_sensor_config imx415_hdr2_config_owner imx415_hdr2_recipe_rom camera_i2c_write'''.split()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--old-gate', action='store_true')
    ap.add_argument('--physical-rx', action='store_true', help='Actual byte aligner, RX, crop, official asynchronous FIFOs and I2C owner at one sensor row')
    a = ap.parse_args()
    if a.old_gate and a.physical_rx:
        ap.error('--old-gate and --physical-rx are separate proofs')
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name):
        raise ValueError('unique lowercase run name required')
    root = PROJECT / 'tmp/hdr_overlap_r1' / a.name
    root.mkdir(parents=True, exist_ok=False)
    q = dict(status='RUNNING', old_gate=a.old_gate, physical_rx=a.physical_rx, commands=[], inputs=[],
             modelsim_bin=str(a.modelsim_bin), td_root=str(a.td_root),
             synthesis='NOT_RUN', physical='NOT_RUN', board='NOT_RUN',
             bounds='16x2 RAW10, 2 member FIFOs of 512 tokens, finite AW/W/B and final W/SOURCE stalls; not sustained HD fps')
    if a.physical_rx:
        q['bounds'] = '1944x1 sensor, 1920x1 crop, true byte RX and official asynchronous FIFOs/I2C; no DDR/ISP/JPEG or sustained HD fps'
    start = time.monotonic()
    try:
        def snapshot(source, relative):
            target = root / 'source' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
            q['inputs'].append(dict(source=str(source), snapshot=str(target), sha256=digest(target)))
            return target
        sources = []
        for name in RX_NAMES if a.physical_rx else NAMES:
            source = PROJECT / 'src_fpga/rtl' / (name + '.v')
            if a.old_gate and name == 'real_hdr_pair_cycle_gate':
                source = PROJECT.parent / 'dual_hdr_merge_r1/src_fpga/rtl' / (name + '.v')
            sources.append(snapshot(source, 'rtl/' + name + '.v'))
        ips = ['vendor/anlogic_camera/phy/csi_rx_word_gear_box.v',
               'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v', 'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v',
               'camera_packet_fifo_147x512/camera_packet_fifo_147x512.v'] if a.physical_rx else ['ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v']
        sources.extend(snapshot(PROJECT / 'src_fpga/ip' / p, 'ip/' + p) for p in ips)
        snapshot(PROJECT / 'src_fpga/rtl/include/04_include/pcie_protocol_v1.vh', 'include/pcie_protocol_v1.vh')
        bench_name = 'tb_full_overlap_rx' if a.physical_rx else 'tb_hdr_overlap'
        bench_dir = 'hdr_merge_short_r1' if a.physical_rx else 'hdr_overlap_r1'
        bench = snapshot(PROJECT / 'src_fpga/simulation' / bench_dir / (bench_name + '.sv'), bench_name + '.sv')
        snapshot(Path(__file__), 'run_hdr_overlap_unified.py')
        models = [a.td_root / 'sim_release' / p for p in ('common/al_phy_glbl.v', 'ph1/ph1_logic_eram.v',
                  'ph1/ph1_logic_fifo.v', 'ph1/ph1_logic_ramfifo.v', 'ph1/ph1_phy_eram.v', 'ph1/ph1_phy_fifoctrl.v')]
        gsr = a.td_root / 'sim_release/ph1/ph1_phy_gsr.v'
        q['tool_models'] = [dict(path=str(p), sha256=digest(p)) for p in models + [gsr]]

        def call(name, exe, arguments):
            argv = [str(a.modelsim_bin / exe), *map(str, arguments)]
            record = dict(argv=argv, cwd=str(root), returncode=None)
            q['commands'].append(record)
            proc = subprocess.run(argv, cwd=root, capture_output=True, text=True, errors='replace',
                                  timeout=55, creationflags=subprocess.CREATE_NO_WINDOW)
            record['returncode'] = proc.returncode
            (root / (name + '.console.log')).write_text(proc.stdout + proc.stderr)
            if proc.returncode:
                raise RuntimeError((proc.stdout + proc.stderr)[-7000:])
        call('vmap', 'vmap.exe', ['-c'])
        call('work', 'vlib.exe', ['work'])
        call('ph1', 'vlib.exe', ['ph1'])
        call('models', 'vlog.exe', ['-quiet', '-work', 'ph1', '-l', 'models.log', *models])
        flags = ['+define+PH1', '+incdir+' + str(root / 'source/include')]
        if a.physical_rx:
            flags.append('+define+R8_STAGE1')
        if a.old_gate:
            flags.append('+define+OLD_GATE')
        call('compile', 'vlog.exe', ['-quiet', '-sv', '-l', 'compile.log', *flags, gsr, *sources, bench])
        call('simulation', 'vsim.exe', ['-c', '-voptargs=+acc', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
             'work.' + bench_name, '-l', 'simulation.log', '-do', 'onerror {quit -code 1}; run -all; quit -f'])
        body = (root / 'simulation.log').read_text(errors='replace')
        marker = 'FULL_OVERLAP_RX_TWO_CONTEXT' if a.physical_rx else 'OLD_HDR_HALF_RATE_NEGATIVE_CONTROL' if a.old_gate else 'HDR_TWO_CONTEXT_OVERLAP'
        if 'RESULT: PASS ' + marker not in body or re.search(r'\*\* (Error|Fatal):', body):
            raise RuntimeError(body[-9000:])
        for row in q['inputs']:
            if digest(Path(row['source'])) != row['sha256']:
                raise RuntimeError('source drift: ' + row['source'])
        q.update(status='PASS', observations=[s.strip('# ') for s in body.splitlines() if 'CASE ' in s or 'RESULT:' in s])
        print('\n'.join(q['observations']))
    except Exception as error:
        q.update(status='FAIL', error=str(error))
        raise
    finally:
        q['elapsed_seconds'] = round(time.monotonic() - start, 3)
        (root / 'RESULTS.json').write_text(json.dumps(q, indent=2) + '\n')
        print('Evidence', root)


if __name__ == '__main__':
    main()
