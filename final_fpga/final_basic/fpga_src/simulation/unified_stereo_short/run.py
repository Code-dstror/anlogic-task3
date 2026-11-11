"""Short source/RAW two-slot A/B; real TD RAM/FIFO, modeled DDR/service boundary."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASELINE = ROOT.parent / 'dual_hdr_merge_r1'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        ap.error('invalid run identifier')
    out = ROOT / 'tmp/unified_stereo_short' / args.name
    out.mkdir(parents=True, exist_ok=False)
    td, ms = args.td_root.resolve(), args.modelsim_bin.resolve()
    models = [td / 'sim_release' / name for name in [
        'common/al_phy_glbl.v', 'ph1/ph1_logic_dram.v', 'ph1/ph1_logic_eram.v',
        'ph1/ph1_logic_fifo.v', 'ph1/ph1_logic_ramfifo.v', 'ph1/ph1_phy_eram.v', 'ph1/ph1_phy_fifoctrl.v']]
    names = ['reset_release_sync', 'td_sdp_ram40', 'hdr_pair_directory', 'stereo_raw_owner',
             'physical_capture_router', 'physical_identity_source_fence', 'stereo_capture_source4',
             'raw_capture_fifo_eram_safe', 'raw10_append5', 'shared_raw10_frame_ingress',
             'shared_raw_capture_writer', 'full_raw_capture_frontend', 'dual_raw_capture_frontend',
             'dol2_axi_write_arbiter']
    all_inputs = models + [Path(__file__), HERE / 'tb_owner_order.sv', HERE / 'tb_capture_rate.sv', HERE / 'tb_fs_cadence.sv',
                            BASELINE / 'src_fpga/simulation/stereo_source/tb_stereo_source.sv']
    source_sets = {}
    for label, root in [('baseline', BASELINE), ('candidate', ROOT)]:
        rtl, ip = root / 'src_fpga/rtl', root / 'src_fpga/ip'
        source_sets[label] = [td / 'sim_release/ph1/ph1_phy_gsr.v',
            ip / 'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
            ip / 'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v', ip / 'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v',
            ip / 'camera_packet_fifo_147x512/camera_packet_fifo_147x512.v'] + [rtl / (n + '.v') for n in names]
        all_inputs += source_sets[label] + [rtl / 'include/04_include/pcie_protocol_v1.vh']
    identity = [{'path': str(path.resolve()), 'sha256': digest(path)} for path in dict.fromkeys(all_inputs)]
    result = {'status': 'RUNNING', 'modelsim_bin': str(ms), 'td_root': str(td), 'inputs': identity,
              'scope': 'actual per-eye source/router/fence, both RAW frontends/FIFOs/writers and four-entry owner; DDR and processing boundaries modeled',
              'synthesis': 'NOT_RUN', 'pnr': 'NOT_RUN', 'timing': 'NOT_RUN', 'board': 'NOT_RUN', 'cases': []}
    start = time.monotonic()

    def command(name, exe, words):
        proc = subprocess.run([str(ms / exe)] + list(map(str, words)), cwd=out,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, errors='replace', timeout=60)
        (out / (name + '.log')).write_text(proc.stdout, encoding='utf-8')
        if proc.returncode or re.search(r'\*\* (Error|Fatal):', proc.stdout):
            raise RuntimeError(name + ': ' + proc.stdout[-9000:])
        return proc.stdout

    try:
        command('vmap', 'vmap.exe', ['-c'])
        command('ph1', 'vlib.exe', ['ph1'])
        command('models', 'vlog.exe', ['-work', 'ph1', *models])
        for label, root in [('baseline', BASELINE), ('candidate', ROOT)]:
            command(label + '_lib', 'vlib.exe', [label])
            options = ['-sv', '+define+PH1', '+incdir+' + str(root / 'src_fpga/rtl/include/04_include')]
            if label == 'candidate':
                options += ['+define+CANDIDATE']
            legacy_bench = BASELINE / 'src_fpga/simulation/stereo_source/tb_stereo_source.sv'
            extra_benches = []
            if label == 'candidate':
                # Only bind the added optional input; leave default FS cadence
                # disabled so the historical behavioral regression is exact.
                legacy_text = legacy_bench.read_text()
                legacy_bench = out / 'legacy_source_port_binding.sv'
                legacy_bench.write_text(legacy_text.replace('.i_enable(', ".i_frame_divisor(8'd1),.i_enable("))
                result['legacy_test_adaptation'] = {'path': str(legacy_bench.resolve()), 'sha256': digest(legacy_bench),
                    'change': 'connect new i_frame_divisor=1; FS_CADENCE_ENABLE remains default 0'}
                extra_benches = [HERE / 'tb_fs_cadence.sv']
            command(label + '_compile', 'vlog.exe', ['-work', label, *options, *source_sets[label],
                HERE / 'tb_owner_order.sv', HERE / 'tb_capture_rate.sv', legacy_bench, *extra_benches])
            cases = [('tb_owner_order', [], 'order'),
                ('tb_capture_rate', ['-gFE_DELAY=397'], 'late_fe'),
                ('tb_capture_rate', ['-gFE_DELAY=380'], 'early_fe'),
                ('tb_stereo_source', [], 'legacy_source')]
            if label == 'candidate':
                cases += [('tb_fs_cadence', [], 'fs_cadence')]
            for top, params, suffix in cases:
                name = label + '_' + suffix
                log = command(name, 'vsim.exe', ['-c', '-L', 'ph1', label + '.PH1_PHY_GSR',
                    label + '.' + top, *params, '-do', 'run -all; quit -f'])
                markers = [line.strip('# ') for line in log.splitlines() if 'RESULT: PASS' in line]
                if len(markers) != 1:
                    raise RuntimeError(name + ' missing self-check PASS: ' + log[-9000:])
                result['cases'].append({'name': name, 'status': 'PASS', 'metric': markers[0]})
                print(name + ': ' + markers[0], flush=True)
        warnings = []
        for path in out.glob('*.log'):
            for line in path.read_text(encoding='utf-8').splitlines():
                if '** Warning:' not in line:
                    continue
                vendor = ('ecc_' in line and ('ram40_sdp_fixed.v(69)' in line or 'ph1_logic_eram.v(52)' in line)) or (
                    'ph1_logic_eram.v(1287)' in line and 'INIT_FILE' in line)
                legacy_optional_port = ('i_frame_divisor' in line and ('Too few port' in line or 'Missing connection' in line))
                if not vendor and not legacy_optional_port:
                    raise RuntimeError('unclassified warning ' + path.name + ': ' + line)
                warnings.append({'log': path.name, 'message': line,
                                 'class': 'vendor_model' if vendor else 'legacy_default_FS_cadence_disabled'})
        if any(digest(Path(row['path'])) != row['sha256'] for row in identity):
            raise RuntimeError('source changed during A/B')
        result.update(status='PASS', reviewed_warnings=warnings)
    except Exception as exc:
        result.update(status='FAIL', error=str(exc))
        raise
    finally:
        result['elapsed_seconds'] = round(time.monotonic() - start, 3)
        (out / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(out / 'RESULTS.json')


if __name__ == '__main__':
    main()
