"""Run the isolated, source-bound HDR or SDR JPEG MAIN with explicit tool roots.

Only the electrical/DDR/host boundaries listed in MAIN_FIXTURE.json are models.
Owned image, lifecycle, native packetizer and transport RTL are the new project.
No TD synthesis or physical implementation is launched.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--mode', choices=['hdr', 'sdr', 'dual'], required=True)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    ap.add_argument('--compile-only', action='store_true')
    ap.add_argument('--autof21-short', action='store_true',
                    help='Actual TOP ordinary CFG G0 ON/OFF/ON, cold PERST and two bad-source recoveries; no ALGO writes')
    ap.add_argument('--runtime-recovery', choices=['short', 'full', 'crc-short', 'crc-full'],
                    help='SDR: two genuinely admitted partial frames fail, then recover SOURCE5; short stops at recovered output SOF')
    ap.add_argument('--runtime-profile', choices=['none', 'gaussian', 'sparse', 'dehaze'],
                    help='Short runtime check only: schema2 none, legacy Gaussian, or schema2 F22/F23 (default sparse)')
    ap.add_argument('--readonly-uart', action='store_true',
                    help='Passively decode the production 115200-baud observer during MAIN')
    ap.add_argument('--dual-cold-short', action='store_true', help='Actual cold TOP dual/mono/dual and v4 selection; no image/FPS claim')
    a = ap.parse_args()
    if a.dual_cold_short and (a.mode != 'dual' or a.compile_only):
        ap.error('--dual-cold-short requires --mode dual and actual bounded execution')
    if a.autof21_short:
        if a.mode != 'sdr' or a.runtime_recovery or a.runtime_profile:
            ap.error('--autof21-short requires SDR and selects its own runtime scenario')
        a.runtime_recovery = 'short'
        a.runtime_profile = 'dehaze'
    if a.runtime_recovery and a.mode != 'sdr':
        ap.error('--runtime-recovery is supported only for SDR')
    if a.runtime_profile is not None and a.runtime_recovery not in {'short', 'crc-short'}:
        ap.error('--runtime-profile is supported only with short or crc-short')
    runtime_short = a.runtime_recovery in {'short', 'crc-short'}
    runtime_crc = a.runtime_recovery in {'crc-short', 'crc-full'}
    runtime_profile = a.runtime_profile or 'sparse'
    runtime_enables = 2 if runtime_profile == 'dehaze' else 0 if runtime_profile in {'none', 'gaussian'} else 48
    if a.runtime_recovery:
        # This scenario checks the production RX observer (RT is retired). Select its
        # existing decoder, never the historical writable-UART fixture.
        a.readonly_uart = True
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', a.name):
        ap.error('name must be a lowercase run identifier')
    td = a.td_root.resolve()
    ms = a.modelsim_bin.resolve()
    run = ROOT / 'tmp' / 'main' / a.name
    run.mkdir(parents=True, exist_ok=False)
    fixture = json.loads((HERE / 'MAIN_FIXTURE.json').read_text())
    if a.mode in fixture.get('mode_simulation_overrides', {}):
        fixture['simulation_overrides'] = fixture['mode_simulation_overrides'][a.mode]
    if a.readonly_uart:
        fixture['simulation_overrides'] = dict(fixture['simulation_overrides'],
            READONLY_UART_REPORT_CYCLES=250000)
    paths = {Path(__file__), HERE / 'MAIN_FIXTURE.json', ROOT / 'BASELINE_INPUTS.json'}
    paths.update(ROOT / relative for relative in fixture['oracle_inputs'])
    # Simulation models use run-local HEX memory images, regenerated exclusively
    # from this candidate's byte-frozen production MIF inputs.
    rom_dir = run / 'rom_init'
    rom_dir.mkdir()
    rom_images = []
    for filename, relative in fixture['local_rom_initializers'].items():
        source = ROOT / relative
        mif = source.read_text(encoding='ascii')
        if not re.search(r'ADDRESS_RADIX\s*=\s*HEX', mif) or not re.search(r'DATA_RADIX\s*=\s*HEX', mif):
            raise ValueError(f'Unsupported MIF radix: {source}')
        depth = int(re.search(r'DEPTH\s*=\s*(\d+)', mif).group(1))
        width = int(re.search(r'WIDTH\s*=\s*(\d+)', mif).group(1))
        entries = re.findall(r'(?m)^\s*([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)\s*;', mif)
        values = {int(address, 16): int(value, 16) for address, value in entries}
        if len(entries) != depth or set(values) != set(range(depth)) or any(v >= (1 << width) for v in values.values()):
            raise ValueError(f'Incomplete or invalid MIF: {source}')
        image = rom_dir / filename
        image.write_text(''.join(f'{values[i]:0{(width+3)//4}X}\n' for i in range(depth)), encoding='ascii')
        paths.update((source, image))
        rom_images.append({'source': source.resolve().as_posix(),
                           'source_sha256': sha(source), 'path': image.resolve().as_posix(),
                           'sha256': sha(image), 'width': width, 'depth': depth})
    # These authorities are consumed by the independent oracle after MAIN.
    # Bind them before simulation as well so both stages share one fixed input set.
    reference_root = ROOT / 'verification_reference'
    reference_rows = [row for row in json.loads((ROOT / 'BASELINE_INPUTS.json').read_text())['files']
                      if row['path'].startswith('verification_reference/')]
    references = [ROOT / row['path'] for row in reference_rows]
    for row, path in zip(reference_rows, references):
        if not path.resolve().is_relative_to(reference_root.resolve()) or sha(path) != row['source_sha256']:
            raise ValueError(f'Changed frozen verification reference: {path}')
    paths.update(references)
    groups = {}
    for key, rows in fixture['groups'].items():
        group = [td / r['td_model'] if 'td_model' in r else ROOT / r['path'] for r in rows
                 if 'modes' not in r or a.mode in r['modes']]
        for p in group:
            if not p.is_file():
                raise FileNotFoundError(p)
        groups[key] = group
        paths.update(group)
    models = [td / p for p in fixture['models']]
    paths.update(models)
    incdirs = [ROOT / p for p in fixture['include_dirs']]
    # Bind every actually resolved include and ROM asset. Transitive vendor
    # includes stay under the explicitly selected TD installation.
    queue = list(paths)
    visited = set()
    while queue:
        p = queue.pop()
        if p in visited or p.suffix.lower() not in {'.v', '.sv', '.vh'}:
            continue
        visited.add(p)
        body = p.read_text(encoding='utf-8', errors='replace')
        for name in re.findall(r'(?m)^\s*`include\s+"([^"\r\n]+)"', body):
            candidates = [p.parent / name] + [d / name for d in incdirs]
            found = next((q.resolve() for q in candidates if q.is_file()), None)
            if found is None:
                raise FileNotFoundError(f'{p}: include {name}')
            paths.add(found)
            queue.append(found)
    # Small reviewed init files are part of the snapshot even when the native
    # IP supplies their path through a parameter rather than a literal include.
    for parent in [ROOT / 'src_fpga' / 'rtl' / 'jpeg' / 'quant_data', ROOT / 'src_fpga' / 'ip']:
        for pattern in ['*.mif', '*.dath', '*.mem', '*.hex']:
            paths.update(p for p in parent.rglob(pattern) if p.is_file())
    identity = {
        'schema': 1, 'mode': a.mode, 'td_root': td.as_posix(),
        'runtime_recovery': a.runtime_recovery,
        'autof21_short': a.autof21_short,
        'f21_auto_fixed_lut_profile': 0, 'candidate_dehaze_removed': True,
        'runtime_profile': runtime_profile if a.runtime_recovery else None,
        'runtime_enables': runtime_enables,
        'runtime_legacy_mode': 2 if runtime_profile == 'gaussian' else 0,
        'f23_profile': fixture['f23_profile'],
        'f21_profile': fixture['f21_profile'],
        'modelsim_bin': ms.as_posix(), 'boundary_models': fixture['boundary_models'],
        'simulation_overrides': fixture['simulation_overrides'],
        'rom_images': rom_images,
        'frozen_reference_inputs': [{'path': p.resolve().as_posix(), 'sha256': sha(p)} for p in references],
        'inputs': [{'path': p.resolve().as_posix(), 'sha256': sha(p)} for p in sorted(paths)],
    }
    (run / 'source_identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    q = {'status': 'IN_PROGRESS', 'mode': a.mode, 'td_root': td.as_posix(),
         'runtime_recovery': a.runtime_recovery,
         'autof21_short': a.autof21_short,
         'f21_auto_fixed_lut_profile': 0, 'candidate_dehaze_removed': True,
         'runtime_profile': runtime_profile if a.runtime_recovery else None,
         'runtime_enables': runtime_enables,
         'runtime_legacy_mode': 2 if runtime_profile == 'gaussian' else 0,
         'compile_only': a.compile_only, 'synthesis': 'NOT_RUN', 'physical': 'NOT_RUN',
         'board': 'NOT_RUN', 'source_identity_sha256': sha(run / 'source_identity.json'),
         'owned_warning_count': 0, 'boundary_models': fixture['boundary_models']}
    started = time.monotonic()

    def command(words, live=False):
        print('RUN', ' '.join(str(w) for w in words[:5]), flush=True)
        if live:
            proc = subprocess.Popen([str(w) for w in words], cwd=run, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, errors='replace')
            with (run / 'console.log').open('w', encoding='utf-8') as output:
                for line in proc.stdout:
                    output.write(line)
                    if re.search(r'RESULT:|REAL_HDR_(STEP|STAGE|MAIN|SDR_RETURN)|SDR_JPEG_MAIN|AUTOF21_|RUNTIME_RECOVERY|CRC_RECOVERY|REMOVED_LZ|C2_STOP_MAIN|\*\* (Error|Fatal)', line):
                        print(line.rstrip(), flush=True)
            code = proc.wait()
        else:
            done = subprocess.run([str(w) for w in words], cwd=run, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, errors='replace')
            code = done.returncode
            if code:
                print(done.stdout[-12000:], flush=True)
        if code:
            raise RuntimeError(f'{words[0]} exit {code}')

    def argfile(name, words):
        p = run / name
        p.write_text('\n'.join('"' + str(w).replace('\\', '/') + '"' for w in words) + '\n')
        return p

    try:
        command([ms / 'vlib.exe', 'work'])
        command([ms / 'vlib.exe', 'ph1'])
        command([ms / 'vmap.exe', 'work', 'work'])
        command([ms / 'vmap.exe', 'ph1', 'ph1'])
        model_args = argfile('models.args', ['-quiet', '-work', 'ph1', '-l', 'models.log',
                             '+incdir+' + (td / 'sim_release' / 'common').as_posix()] + models)
        command([ms / 'vlog.exe', '-f', model_args])
        defs = ['PH1', 'R8_STAGE1', 'R8_BASIC_PREPROCESS', 'S08_CONFIGURED_CAPTURE', 'S04_RAW_FRAME_STORE',
                'R8_LIVE_F21', 'R8_STAGE2_COMPACT_TRANSPORT', 'R8_F21_FIXED_CONFIG_SESSION',
                'R8_HE_FIXED_CONFIG_SESSION', 'F21_AUTO_FIXED_LUT_PROFILE=0',
                'S08_SIM_WIDTH=1920', 'S08_SIM_HEIGHT=1080']
        if a.mode == 'sdr':
            defs.append('REFACTOR_SDR_MAIN=1')
        if a.mode == 'dual':
            defs.append('DUAL_IMX415_MAIN=1')
            if a.dual_cold_short:defs.append('DUAL_COLD_SHORT=1')
        if a.autof21_short:
            defs.append('REFACTOR_AUTOF21_SHORT=1')
        if a.runtime_recovery:
            defs.append('REFACTOR_RUNTIME_RECOVERY=1')
            if runtime_crc:
                defs.append('REFACTOR_RUNTIME_CRC=1')
            if runtime_short:
                defs.append('REFACTOR_RUNTIME_RECOVERY_SHORT=1')
                defs.append('REFACTOR_RUNTIME_ENABLES=' + str(runtime_enables))
                if runtime_profile == 'gaussian':
                    defs.append('REFACTOR_RUNTIME_LEGACY_GAUSSIAN=1')
        if a.readonly_uart:
            defs += ['REFACTOR_READONLY_UART_MAIN=1', 'REFACTOR_OBSERVER_REPORT_CYCLES=250000']
        macdefs = ['fdct_mac19s14s_z33s_p34_m1p1_USE_' + name + '=1' for name in ['A', 'CE', 'PH1A', 'RST', 'Y', 'Z']]
        for filename, group in groups.items():
            log = filename.replace('.args', '.log')
            opts = ['-quiet', '-work', 'work', '-l', log, '-timescale', '1ns/1ps']
            # Official FDCT source is Verilog, as in the qualified original run.
            if filename == 'compile.args':
                opts += ['-sv']
            opts += ['+define+' + x for x in defs + macdefs]
            opts += ['+incdir+' + p.as_posix() for p in incdirs]
            argsfile = argfile(filename, opts + group)
            command([ms / 'vlog.exe', '-f', argsfile])
            text = (run / log).read_text(errors='replace')
            if re.search(r'\*\* (Warning|Error|Fatal):', text):
                print(text[-12000:], flush=True)
                raise RuntimeError(f'{log} contains compiler diagnostics')
        action = 'run 0; quit -f' if a.compile_only else 'run -all; quit -f'
        command([ms / 'vsim.exe', '-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                 'work.tb_dual_imx415' if a.mode == 'dual' else 'work.tb_hdr_jpeg',
                 '-gROM_ROOT=' + (run / 'rom_init').as_posix(), '-l', 'run.log', '-do', action], live=True)
        body = (run / 'run.log').read_text(errors='replace')
        if re.search(r'\*\* (Error|Fatal):', body):
            raise RuntimeError('MAIN runtime diagnostic')
        warnings = [line for line in body.splitlines() if '** Warning:' in line]
        owned = [line for line in warnings if (ROOT / 'src_fpga/rtl').as_posix() + '/' in line.replace('\\', '/')]
        if owned:
            raise RuntimeError('Owned warnings: ' + '\n'.join(owned))
        pass_marker = 'RESULT: PASS DUAL_COLD_TOP' if a.dual_cold_short else 'RESULT: PASS DUAL IMX415 MAIN' if a.mode == 'dual' else 'RESULT: PASS REFACTOR HDR JPEG MAIN'
        if not a.compile_only and pass_marker not in body:
            raise RuntimeError('Missing actual MAIN pass marker')
        if a.runtime_recovery and not a.compile_only:
            expected = (f'CRC_RECOVERY_MAIN PASS short={int(runtime_short)} failures=2 ignored=0 recovered_sequence=3' if runtime_crc else
                        f'RUNTIME_RECOVERY_MAIN PASS short={int(runtime_short)} failures=2 ignored=2 recovered_sequence=5')
            if expected not in body:
                raise RuntimeError('Missing actual runtime recovery lifecycle marker')
        if a.autof21_short and not a.compile_only:
            if 'AUTOF21_TOP_SHORT PASS cfg_on_off_on=3 applied=3 cold_reset=1 source_bad=2 recovered=5 algo_writes=0 lut_commands=0 generation=1' not in body:
                raise RuntimeError('Missing actual automatic-F21 ordinary-CFG/cold-reset/toggle marker')
        if a.readonly_uart and not a.compile_only and not runtime_short and a.mode != 'dual':
            uart = re.search(r'UART_READONLY_MAIN PASS frames=(\d+) fresh=(\d+) active=(\d+) bytes=(\d+)', body)
            if uart is None:
                raise RuntimeError('Missing actual read-only UART decode/overlap check')
            q['readonly_uart'] = dict(zip(('frames', 'fresh_frames', 'business_active_frames', 'decoded_bytes'),
                                         map(int, uart.groups())))
            q['readonly_uart']['report_interval_cycles'] = 250000
            q['readonly_uart']['baud_divisor'] = 217
            q['readonly_uart']['protocol_version'] = 2
            submit = re.search(r'UART_READONLY_MAIN PASS.* submit_frames=(\d+)', body)
            if submit is None or int(submit.group(1)) < 1:
                raise RuntimeError('V2 USER event0 did not report actual native SUBMIT')
            q['readonly_uart']['fresh_submit_frames'] = int(submit.group(1))
            cfg = re.search(r'UART_READONLY_MAIN PASS.* cfg_frames=(\d+) cfg_fresh=(\d+)', body)
            if cfg is None or int(cfg.group(1)) < 1 or int(cfg.group(2)) < 1:
                raise RuntimeError('Missing complete fresh CFG mixed-UART frames')
            q['readonly_uart']['cfg_frames'] = int(cfg.group(1))
            q['readonly_uart']['cfg_fresh_frames'] = int(cfg.group(2))
            q['readonly_uart']['cfg_protocol_version'] = 2
            rx = re.search(r'UART_READONLY_MAIN PASS.* rx_frames=(\d+)', body)
            if rx is None or int(rx.group(1)) < 1:
                raise RuntimeError('Missing actual RX diagnostics during MAIN')
            q['readonly_uart']['rx_frames'] = int(rx.group(1))
        for row in identity['inputs']:
            if sha(Path(row['path'])) != row['sha256']:
                raise RuntimeError('Input changed during run: ' + row['path'])
        q.update(status='PASS_ELABORATION_ONLY' if a.compile_only else 'PASS_DUAL_COLD_TOP' if a.dual_cold_short else
                 'PASS_AUTOF21_TOP_SHORT' if a.autof21_short else
                 'PASS_SDR_CRC_SHORT' if a.runtime_recovery == 'crc-short' else
                 'PASS_SDR_RUNTIME_SHORT' if runtime_short else 'PASS_' + a.mode.upper() + '_MAIN',
                 vendor_warning_count=len(warnings), owned_warning_count=len(owned),
                 metrics=[line for line in body.splitlines() if 'PASS' in line or 'REAL_HDR_STAGE' in line])
    except Exception as error:
        q.update(status='FAIL', error=str(error))
        raise
    finally:
        q['elapsed_seconds'] = round(time.monotonic() - started, 3)
        (run / 'qualification.json').write_text(json.dumps(q, indent=2) + '\n')
        print(json.dumps({'run': run.as_posix(), 'status': q['status'], 'elapsed_seconds': q['elapsed_seconds']}), flush=True)


if __name__ == '__main__':
    main()
