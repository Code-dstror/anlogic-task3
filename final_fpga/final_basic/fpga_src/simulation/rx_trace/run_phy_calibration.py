"""Focused native-ModelSim checks; all generated files stay in project tmp."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--modelsim-bin', required=True)
    parser.add_argument('--name', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        parser.error('name must be a new lowercase run identifier')
    here = Path(__file__).resolve().parent
    project = here.parents[2]
    source = project / 'src_fpga'
    vendor = source / 'ip/vendor/anlogic_camera/phy'
    run_dir = project / 'tmp/rx_trace_phy_control' / args.name
    run_dir.mkdir(parents=True, exist_ok=False)
    lib = run_dir / 'work'
    tool_bin = Path(args.modelsim_bin).resolve()
    commands: list[dict] = []
    provenance = []
    aliases = [
        ('csi_rx_byte_align',
         b'   output wire  [7:0] O_data_out',
         b'   output wire  [7:0] O_data_out,\n   output wire [2:0] o_diag_offset,\n   output wire o_diag_found',
         b'   assign O_data_out  = r_shifted_byte;',
         b'   assign O_data_out  = r_shifted_byte;\n   assign o_diag_offset = r_offset;\n   assign o_diag_found = r_was_found;'),
        ('csi_rx_word_align',
         b'    output                  O_valid_out',
         b'    output                  O_valid_out,\n    output [3*MIPI_LAN-1:0] o_diag_taps',
         b'    integer i;',
         b'    genvar diag_lane;\n    generate for (diag_lane=0; diag_lane<MIPI_LAN; diag_lane=diag_lane+1) begin : g_diag_taps\n        assign o_diag_taps[3*diag_lane+:3] = r_taps[diag_lane];\n    end endgenerate\n\n    integer i;')]
    for name, port_old, port_new, body_old, body_new in aliases:
        original = vendor / (name + '.v')
        derivative = source / 'rtl' / (name + '_observed.v')
        raw = original.read_bytes()
        restored = derivative.read_bytes().split(b'\n', 4)[4]
        restored = restored.replace(b'module ' + name.encode() + b'_observed', b'module ' + name.encode(), 1)
        restored = restored.replace(port_new, port_old, 1).replace(body_new, body_old, 1)
        if restored != raw:
            raise RuntimeError(f'Observation-only textual equivalence failed: {derivative}')
        provenance.append({'source': str(original), 'source_sha256': sha(original),
            'derivative': str(derivative), 'derivative_sha256': sha(derivative),
            'business_body_restores_exact_original': True})

    def invoke(name: str, arguments: list[str], label: str) -> None:
        argv = [str(tool_bin / name), *arguments]
        result = subprocess.run(argv, cwd=run_dir, timeout=60,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            encoding='utf-8', errors='replace', creationflags=subprocess.CREATE_NO_WINDOW)
        (run_dir / (label + '.console.log')).write_text(result.stdout, encoding='utf-8')
        commands.append({'argv': argv, 'exit_code': result.returncode, 'timeout_seconds': 60})
        if result.returncode:
            raise RuntimeError(result.stdout)

    if not lib.exists():
        invoke('vlib.exe', [str(lib)], 'vlib')
    invoke('vmap.exe', ['-c'], 'vmap-create')
    invoke('vmap.exe', ['work', str(lib)], 'vmap-work')
    inputs = [vendor / 'auto_delay_ctl.v', vendor / 'csi_rx_byte_align.v', vendor / 'csi_rx_word_align.v',
        source / 'rtl/ph1a_rx_delay_scan.v', source / 'rtl/csi_rx_byte_align_observed.v',
        source / 'rtl/csi_rx_word_align_observed.v', source / 'rtl/csi2_ph1_phy_wrapper.v',
        here / 'tb_ph1a_delay_scan.sv', here / 'tb_aligner_observation_miter.sv',
        here / 'tb_phy_calibration_wrapper.sv']
    invoke('vlog.exe', ['-sv', '-work', str(lib), '-l', str(run_dir / 'compile.log'),
        *map(str, inputs)], 'compile')
    cases = [('tb_ph1a_delay_scan', 'PASS PH1A calibration'),
        ('tb_aligner_observation_miter', 'PASS observed aligner'),
        ('tb_phy_calibration_wrapper', 'PASS PH1A wrapper')]
    checks = []
    for top, marker in cases:
        log_path = run_dir / (top + '.log')
        invoke('vsim.exe', ['-c', '-lib', 'work', top, '-l', str(log_path),
            '-do', 'run -all; quit -f'], top)
        log = log_path.read_text(encoding='utf-8', errors='replace')
        if marker not in log or '** Fatal:' in log or '** Error:' in log:
            raise RuntimeError(f'{top} failed: {log}')
        summary = [line for line in log.splitlines() if 'PASS ' in line or 'CASE ' in line]
        checks.append({'top': top, 'pass': True, 'summary': summary, 'log': str(log_path)})
        print('\n'.join(summary))
    result = {'pass': True, 'scope': 'Digital control and observation equivalence only; no board/electrical qualification',
        'inputs': [{'path': str(path), 'sha256': sha(path)} for path in inputs],
        'provenance': provenance, 'checks': checks, 'commands': commands}
    result_path = run_dir / 'RESULTS.json'
    result_path.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(result_path)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
