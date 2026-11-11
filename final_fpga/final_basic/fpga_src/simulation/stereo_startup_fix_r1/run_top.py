"""Run source-bound dual startup control or two-eye RAW completion.

Candidate-local real TOP startup validation, adapted from the retained e081 diagnosis.
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
import time
import threading

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--scenario', choices=['control', 'start'], required=True)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    a = ap.parse_args()
    a.mode = 'dual'
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', a.name):
        ap.error('name must be a lowercase run identifier')
    td = a.td_root.resolve()
    ms = a.modelsim_bin.resolve()
    run = ROOT / 'tmp/stereo_startup_fix_r1' / a.name
    run.mkdir(parents=True, exist_ok=False)
    fixture = json.loads((HERE / 'MAIN_FIXTURE.json').read_text())
    if a.mode in fixture.get('mode_simulation_overrides', {}):
        fixture['simulation_overrides'] = fixture['mode_simulation_overrides'][a.mode]
        fixture['simulation_overrides'] = dict(fixture['simulation_overrides'], STEREO_CAPTURE_DIVISOR=2, REQUEST_FRAME_DIVISOR=2)
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
        if not path.resolve().is_relative_to(reference_root.resolve()) or sha(path) != row.get('source_sha256', row.get('sha256')):
            raise ValueError(f'Changed frozen verification reference: {path}')
    paths.update(references)
    groups = {}
    for key, rows in fixture['groups'].items():
        group = [td / r['td_model'] if 'td_model' in r else ROOT / r['path'] for r in rows
                 if 'modes' not in r or a.mode in r['modes']]
        for p in group:
            if not p.is_file():
                raise FileNotFoundError(p)
        group = [Path(__file__).resolve().parent / ('tb_cold_select.sv' if a.scenario == 'control' else 'tb_start_sources.sv') if p.name == 'tb_dual_imx415.sv' else p for p in group]
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
        'schema': 1, 'scenario': a.scenario, 'mode': a.mode, 'td_root': td.as_posix(),
        'f21_auto_fixed_lut_profile': 0, 'candidate_dehaze_removed': True,
        'f23_profile': fixture['f23_profile'],
        'f21_profile': fixture['f21_profile'],
        'modelsim_bin': ms.as_posix(), 'boundary_models': fixture['boundary_models'],
        'simulation_overrides': fixture['simulation_overrides'],
        'rom_images': rom_images,
        'frozen_reference_inputs': [{'path': p.resolve().as_posix(), 'sha256': sha(p)} for p in references],
        'inputs': [{'path': p.resolve().as_posix(), 'sha256': sha(p)} for p in sorted(paths)],
    }
    (run / 'source_identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    q = {'status': 'IN_PROGRESS', 'scenario': a.scenario, 'mode': a.mode, 'td_root': td.as_posix(),
         'f21_auto_fixed_lut_profile': 0, 'candidate_dehaze_removed': True,
         'synthesis': 'NOT_RUN', 'physical': 'NOT_RUN',
         'board': 'NOT_RUN', 'source_identity_sha256': sha(run / 'source_identity.json'),
         'owned_warning_count': 0, 'boundary_models': fixture['boundary_models']}
    started = time.monotonic()

    def command(words, live=False):
        print('RUN', ' '.join(str(w) for w in words[:5]), flush=True)
        if live:
            proc = subprocess.Popen([str(w) for w in words], cwd=run, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, errors='replace')
            def cap_expired():
                (run / 'WALL_TIME_CAP.txt').write_text('ModelSim stopped after 450 seconds; bounded validation incomplete.\n')
                subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            cap_timer=threading.Timer(450, cap_expired)
            cap_timer.start()
            with (run / 'console.log').open('w', encoding='utf-8') as output:
                for line in proc.stdout:
                    output.write(line)
                    if re.search(r'RESULT:|REAL_HDR_(STEP|STAGE|MAIN|SDR_RETURN)|SDR_JPEG_MAIN|AUTOF21_|RUNTIME_RECOVERY|CRC_RECOVERY|ROUND2_|CTRL_DIAG|REMOVED_LZ|C2_STOP_MAIN|\*\* (Error|Fatal)', line):
                        print(line.rstrip(), flush=True)
            code = proc.wait()
            cap_timer.cancel()
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
        defs += ['DUAL_IMX415_MAIN=1', 'DUAL_COLD_SHORT=1']
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
        action = 'run -all; quit -f'
        command([ms / 'vsim.exe', '-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                 'work.tb_dual_imx415',
                 '-gROM_ROOT=' + (run / 'rom_init').as_posix(), '-l', 'run.log', '-do', action], live=True)
        body = (run / 'run.log').read_text(errors='replace')
        if re.search(r'\*\* (Error|Fatal):', body):
            raise RuntimeError('MAIN runtime diagnostic')
        warnings = [line for line in body.splitlines() if '** Warning:' in line]
        owned = [line for line in warnings if (ROOT / 'src_fpga/rtl').as_posix() + '/' in line.replace('\\', '/')]
        if owned:
            raise RuntimeError('Owned warnings: ' + '\n'.join(owned))
        pass_marker = ('RESULT: PASS ROUND2_COMBO_COLD_AND_APP_BUSY' if a.scenario == 'control'
                       else 'RESULT: PASS ROUND2_CLEAN_START_BOTH_RAW_SOURCES')
        if pass_marker not in body:
            raise RuntimeError('Missing actual TOP pass marker')
        for row in identity['inputs']:
            if sha(Path(row['path'])) != row['sha256']:
                raise RuntimeError('Input changed during run: ' + row['path'])
        q.update(status='PASS_COLD_SELECT_APP_BUSY' if a.scenario == 'control' else 'PASS_START_BOTH_RAW_SOURCES',
                 vendor_warning_count=len(warnings), owned_warning_count=len(owned),
                 input_hash_recheck='PASS',
                 metrics=[line for line in body.splitlines() if 'PASS' in line or 'ROUND2_RAW_' in line])
    except Exception as error:
        q.update(status='FAIL', error=str(error))
        raise
    finally:
        q['elapsed_seconds'] = round(time.monotonic() - started, 3)
        (run / 'qualification.json').write_text(json.dumps(q, indent=2) + '\n')
        print(json.dumps({'run': run.as_posix(), 'status': q['status'], 'elapsed_seconds': q['elapsed_seconds']}), flush=True)


if __name__ == '__main__':
    main()
