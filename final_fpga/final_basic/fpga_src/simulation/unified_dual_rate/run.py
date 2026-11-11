"""Source-bound full-HD physical60/N2 dual MAIN; compile/startup are separate gates."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
SIM = HERE.parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    ap.add_argument('--compile-only', action='store_true')
    ap.add_argument('--startup-only', action='store_true')
    ap.add_argument('--frames-per-eye', type=int, default=4)
    ap.add_argument('--quality', type=int, default=75)
    ap.add_argument('--eye-phase-ns', type=int, default=329)
    ap.add_argument('--wall-timeout', type=int, default=14400)
    ap.add_argument('--stereo-hdr', action='store_true', help='drive two physical DOL2 VCs on each camera and use the HDR/v4 monitor')
    args = ap.parse_args()
    top = 'tb_stereo_hdr_top' if args.stereo_hdr else 'tb_unified_dual_rate'
    bench = HERE / (top + '.sv')
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        ap.error('invalid run identifier')
    if not 4 <= args.frames_per_eye <= 64 or not 1 <= args.quality <= 100 or not 0 <= args.eye_phase_ns < 16666667:
        ap.error('invalid bounded full-HD profile')
    if args.compile_only and args.startup_only:
        ap.error('compile-only and startup-only are distinct gates')
    run = ROOT / 'tmp/unified_dual_rate' / args.name
    run.mkdir(parents=True, exist_ok=False)
    td, ms = args.td_root.resolve(), args.modelsim_bin.resolve()
    fixture = json.loads((SIM / 'MAIN_FIXTURE.json').read_text())
    manifest = json.loads((ROOT / 'SOURCE_MANIFEST.json').read_text())
    production = [ROOT / row['path'] for row in manifest['files']]
    groups = {}
    for key, rows in fixture['groups'].items():
        group = []
        for row in rows:
            if 'modes' in row and 'dual' not in row['modes']:
                continue
            p = td / row['td_model'] if 'td_model' in row else ROOT / row['path']
            if p.name == 'tb_dual_imx415.sv':
                p = bench
            if p.name == 'anlogic2026_s08_boundaries.sv':
                p = HERE / 'axi_boundaries.sv'
            group.append(p)
        groups[key] = group
    models = [td / p for p in fixture['models']]
    includes = [HERE] + [ROOT / p for p in fixture['include_dirs']]
    # ROM models receive fresh HEX generated only from this candidate's MIFs.
    rom = run / 'rom_init'
    rom.mkdir()
    paths = set(production + models + [Path(__file__), SIM / 'MAIN_FIXTURE.json', ROOT / 'SOURCE_MANIFEST.json',
        ROOT / 'BASELINE_INPUTS.json', bench, HERE / 'unified_rate_monitor.vh',
        HERE / 'check.py', HERE / 'dual_reference.py', HERE / 'PROVENANCE.json'])
    for name, relative in fixture['local_rom_initializers'].items():
        source = ROOT / relative
        body = source.read_text()
        depth = int(re.search(r'DEPTH\s*=\s*(\d+)', body).group(1))
        values = {int(a, 16): b for a, b in re.findall(r'(?m)^\s*([0-9a-fA-F]+)\s*:\s*([0-9a-fA-F]+)\s*;', body)}
        if set(values) != set(range(depth)):
            raise ValueError('incomplete ROM initializer ' + str(source))
        target = rom / name
        target.write_text(''.join(values[n] + '\n' for n in range(depth)))
        paths.update([source, target])
    # Freeze the independent scalar and v4 parsers actually used after MAIN.
    refs = [ROOT / row['path'] for row in json.loads((ROOT / 'BASELINE_INPUTS.json').read_text())['files']
            if row['path'].startswith('verification_reference/')]
    paths.update(refs)
    protocol = SIM / 'merge_integration_20261101/protocol_reference'
    paths.update(p for p in protocol.rglob('*.py') if '__pycache__' not in p.parts)
    for group in groups.values():
        paths.update(group)
    queue, seen = list(paths), set()
    while queue:
        path = queue.pop()
        if path in seen or path.suffix not in ('.v', '.sv', '.vh'):
            continue
        seen.add(path)
        for name in re.findall(r'(?m)^\s*`include\s+"([^"\r\n]+)"', path.read_text(errors='replace')):
            found = next((p.resolve() for p in [path.parent / name] + [d / name for d in includes] if p.is_file()), None)
            if found is None:
                raise FileNotFoundError(str(path) + ': ' + name)
            if found not in paths:
                paths.add(found)
                queue.append(found)
    identity = {'schema': 1, 'mode': 'dual', 'quality': args.quality, 'restart': 0,
        'frames_per_eye': args.frames_per_eye, 'physical_period_ns': 16666667, 'capture_divisor': 2,
        'eye_phase_ns': args.eye_phase_ns, 'startup_only': args.startup_only, 'compile_only': args.compile_only,
        'production_lock': 'CURRENT_LOCAL_SOURCE_SNAPSHOT_NOT_OLD_QUALIFICATION',
        'td_root': str(td), 'modelsim_bin': str(ms), 'fixture': str(bench),
        'boundary_models': [str(HERE / 'axi_boundaries.sv')] + [str(ROOT / p) for p in fixture['boundary_models'] if not p.endswith('anlogic2026_s08_boundaries.sv')],
        'production_inputs': [{'path': str(p.resolve()), 'sha256': sha(p)} for p in production],
        'inputs': [{'path': str(p.resolve()), 'sha256': sha(p)} for p in sorted(paths)]}
    if args.stereo_hdr:
        identity.update(mode='dual_hdr',physical_period_ns=None,warmup_pairs=1,frames_per_eye=0 if args.startup_only else 1)
    (run / 'source_identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    result = {'status': 'RUNNING', 'scope': __doc__, 'source_identity_sha256': sha(run / 'source_identity.json'),
        'simulation': 'RUNNING', 'independent_oracle': 'NOT_RUN', 'synthesis': 'NOT_RUN', 'pnr': 'NOT_RUN',
        'timing': 'NOT_RUN', 'board': 'NOT_RUN', 'commands': []}
    start = time.monotonic()

    def command(label, argv, timeout=120):
        remaining = args.wall_timeout - (time.monotonic() - start)
        if remaining <= 0:
            raise TimeoutError('bounded local simulation wall budget exhausted')
        argv = list(map(str, argv))
        result['commands'].append(argv)
        with (run / (label + '.console.log')).open('w', encoding='utf-8') as output:
            proc = subprocess.run(argv, cwd=run, stdout=output, stderr=subprocess.STDOUT, timeout=min(timeout, remaining))
        body = (run / (label + '.console.log')).read_text(errors='replace')
        if proc.returncode or re.search(r'\*\* (Error|Fatal):', body):
            raise RuntimeError(label + ': ' + body[-10000:])
        return body

    def argfile(name, words):
        target = run / name
        target.write_text('\n'.join('"' + str(w).replace('\\', '/') + '"' for w in words) + '\n')
        return target

    try:
        command('vmap', [ms / 'vmap.exe', '-c'])
        for lib in ('work', 'ph1'):
            command('lib_' + lib, [ms / 'vlib.exe', lib])
            command('map_' + lib, [ms / 'vmap.exe', lib, lib])
        command('models', [ms / 'vlog.exe', '-quiet', '-work', 'ph1', *models])
        defs = ['PH1', 'R8_STAGE1', 'R8_BASIC_PREPROCESS', 'S08_CONFIGURED_CAPTURE', 'S04_RAW_FRAME_STORE',
                'R8_LIVE_F21', 'R8_STAGE2_COMPACT_TRANSPORT', 'R8_F21_FIXED_CONFIG_SESSION',
                'R8_HE_FIXED_CONFIG_SESSION', 'F21_AUTO_FIXED_LUT_PROFILE=0', 'S08_SIM_WIDTH=1920',
                'S08_SIM_HEIGHT=1080', 'DUAL_IMX415_MAIN=1']
        defs += ['fdct_mac19s14s_z33s_p34_m1p1_USE_' + p + '=1' for p in ['A', 'CE', 'PH1A', 'RST', 'Y', 'Z']]
        for filename, group in groups.items():
            opts = ['-quiet', '-work', 'work', '-timescale', '1ns/1ps']
            if filename == 'compile.args':
                opts += ['-sv']
            opts += ['+define+' + p for p in defs] + ['+incdir+' + str(p) for p in includes]
            afile = argfile(filename, opts + group)
            body = command(filename, [ms / 'vlog.exe', '-f', afile])
            if re.search(r'\*\* Warning:', body):
                raise RuntimeError(filename + ' contains compiler warnings: ' + body[-6000:])
        action = 'run 0; quit -f' if args.compile_only else 'run -all; quit -f'
        command('sim', [ms / 'vsim.exe', '-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
            'work.'+top, '-gROM_ROOT=' + rom.as_posix(), '-gJPEG_QUALITY=' + str(args.quality),
            '-gTHROUGHPUT_FRAMES=' + str(args.frames_per_eye), '-gSTARTUP_ONLY=' + str(int(args.startup_only)),
            '-gEYE_PHASE_NS=' + str(args.eye_phase_ns), '-l', 'run.log', '-do', action], args.wall_timeout)
        body = (run / 'run.log').read_text(errors='replace')
        warnings = [line for line in body.splitlines() if '** Warning:' in line]
        owned = [line for line in warnings if '/src_fpga/rtl/' in line.replace('\\', '/')]
        if owned:
            raise RuntimeError('owned runtime warning: ' + '\n'.join(owned))
        marker = 'RESULT: PASS UNIFIED_DUAL_RATE_STARTUP' if args.startup_only else 'RESULT: PASS UNIFIED_DUAL_RATE_MAIN'
        if args.stereo_hdr:
            marker='RESULT: PASS STEREO_HDR_TOP_STARTUP' if args.startup_only else 'RESULT: PASS STEREO_HDR_TOP_RECORDS'
        if not args.compile_only and marker not in body:
            raise RuntimeError('actual terminal self-check missing')
        for row in identity['inputs']:
            if sha(Path(row['path'])) != row['sha256']:
                raise RuntimeError('source drift during simulation: ' + row['path'])
        status = 'PASS_ELABORATION_ONLY' if args.compile_only else 'PASS_DUAL_RATE_STARTUP' if args.startup_only else 'PASS_DUAL_RATE_MAIN'
        if args.stereo_hdr and not args.compile_only:
            status='PASS_STEREO_HDR_TOP_STARTUP' if args.startup_only else 'PASS_STEREO_HDR_TOP_RECORDS'
        result.update(status=status, simulation=status, owned_warning_count=0, vendor_warning_count=len(warnings),
            metrics=[line.strip('# ') for line in body.splitlines() if 'PASS' in line])
        (run / 'qualification.json').write_text(json.dumps(result, indent=2) + '\n')
        if not args.compile_only and not args.startup_only and not args.stereo_hdr:
            command('oracle', [sys.executable, HERE / 'check.py', '--run-directory', run,
                '--output-directory', run / 'oracle'], args.wall_timeout)
            result.update(status='PASS_FULL_HD_DUAL_RATE_AND_ORACLE', independent_oracle='PASS')
        print(json.dumps({'run': str(run), 'status': result['status'], 'metrics': result.get('metrics', [])}))
    except Exception as exc:
        result.update(status='FAIL', error=str(exc))
        raise
    finally:
        result['elapsed_seconds'] = round(time.monotonic() - start, 3)
        (run / 'qualification.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
