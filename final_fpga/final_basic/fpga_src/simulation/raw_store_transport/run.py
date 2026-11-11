"""Short RAW outlet, AXI debt and slot retirement simulation."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        parser.error('invalid run name')

    here = Path(__file__).resolve().parent
    project = here.parents[2]
    rtl = project / 'src_fpga/rtl'
    include = rtl / 'include/00_rtl'
    td_root = args.td_root.resolve(strict=True)
    ms = args.modelsim_bin.resolve(strict=True)
    td_models = td_root / 'sim_release'
    models = [td_models / name for name in ('common/al_phy_glbl.v', 'ph1/ph1_logic_eram.v', 'ph1/ph1_phy_eram.v')]
    sources = [td_models / 'ph1/ph1_phy_gsr.v',
               project / 'src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v']
    sources += [rtl / f'{name}.v' for name in ('td_sdp_ram40', 'hdr_pair_directory', 'stereo_raw_owner',
                'stereo_raw_reader', 'stereo_raw_store', 'raw_video_record_formatter')]
    sources.append(here / 'tb_raw_store_transport.sv')
    inputs = [*models, *sources, include / 'raw_video_v1.vh', Path(__file__).resolve()]
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    out = project / 'tmp/raw_store_transport' / args.name
    out.mkdir(parents=True, exist_ok=False)

    started = time.monotonic()
    result = {'status': 'RUNNING', 'inputs': hashes, 'commands': [],
              'boundary': 'Actual store, directory RAM, RAW reader and formatter. Capture writer terminal, AXI memory and host SAFE are modeled.',
              'synthesis': 'NOT_RUN', 'pnr': 'NOT_RUN', 'board': 'NOT_RUN'}

    def run(log_name, tool, *options):
        command = [str(ms / f'{tool}.exe'), *map(str, options)]
        result['commands'].append(command)
        remaining = 180 - (time.monotonic() - started)
        completed = subprocess.run(command, cwd=out, timeout=max(remaining, 0.01),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, errors='replace', creationflags=subprocess.CREATE_NO_WINDOW)
        (out / log_name).write_text(completed.stdout, encoding='utf-8')
        if completed.returncode:
            raise RuntimeError(completed.stdout[-4000:])
        return completed.stdout

    try:
        run('ph1_lib.log', 'vlib', 'ph1')
        run('work_lib.log', 'vlib', 'work')
        run('models.log', 'vlog', '-work', 'ph1', *models)
        run('compile.log', 'vlog', '-sv', '+define+PH1', f'+incdir+{include}', *sources)
        log = run('run.log', 'vsim', '-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                  'work.tb_raw_store_transport', '-do', 'run -all; quit -f')
        marker = re.search(r'RESULT: PASS RAW_STORE_TRANSPORT checks=(\d+)', log)
        if not marker or re.search(r'\*\* (Error|Fatal):', log):
            raise RuntimeError(log[-4000:])
        if any(hashlib.sha256(path.read_bytes()).hexdigest() != hashes[str(path)] for path in inputs):
            raise RuntimeError('simulation input changed during run')
        result.update(status='PASS', checks=int(marker[1]))
        print(marker[0])
    except Exception as error:
        result.update(status='FAIL', error=str(error))
        raise
    finally:
        result['seconds'] = time.monotonic() - started
        result['logs'] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in out.glob('*.log')}
        (out / 'qualification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        print(out)


if __name__ == '__main__':
    main()
