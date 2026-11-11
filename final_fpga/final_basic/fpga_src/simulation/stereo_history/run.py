"""Compile the shared equalizer against the configured Anlogic TD memory and DSP models."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    parser.add_argument('--name', required=True)
    a = parser.parse_args()
    if not a.name.isidentifier():
        parser.error('name must be a single run identifier')
    run = PROJECT / 'tmp' / 'stereo_history' / a.name
    run.mkdir(parents=True, exist_ok=False)
    sim = a.td_root / 'sim_release'
    ip = PROJECT / 'src_fpga' / 'ip'
    rtl = PROJECT / 'src_fpga' / 'rtl'
    models = [sim/'common/al_phy_glbl.v', sim/'ph1/ph1_logic_eram.v',
              sim/'ph1/ph1_phy_eram.v', *sorted((sim/'ph1').glob('ph1_phy_dsp*.v'))]
    mac = ip/'stage3/fdct_mac19s14s_z33s_p34_m1p1'
    sources = [sim/'ph1/ph1_phy_gsr.v', *mac.glob('*.v'), *mac.glob('RTL/*.v'),
               ip/'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
               ip/'isp_line_ram_20x1024_ip/isp_line_ram_20x1024_ip.v']
    sources += [rtl/name for name in ('td_sdp_ram.v','td_sdp_ram40.v','preprocess_count_ram24x512.v',
               'preprocess_lut_ram8x512.v','preprocess_hist_lane.v','stage3_he_div_32u24u_iter16.v',
               'preprocess_gray4.v','preprocess_he_color4.v','preprocess_hist_eq4.v')]
    sources += [HERE/'tb_stereo_he.sv']
    files = models + sources + [Path(__file__)]
    def identity():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    record = dict(status='FAIL', inputs=identity(), td_root=str(a.td_root), modelsim_bin=str(a.modelsim_bin),
                  synthesis='NOT_RUN', route='NOT_RUN', board='NOT_RUN')
    def invoke(program, words):
        with (run/'console.log').open('a', encoding='utf-8') as stream:
            stream.write(' '.join(map(str, [program]+words))+'\n');stream.flush()
            subprocess.run([a.modelsim_bin/(program+'.exe'), *words], cwd=run, stdout=stream,
                           stderr=subprocess.STDOUT, check=True, timeout=90)
    try:
        invoke('vmap',['-c'])
        for lib in ('work','ph1'): invoke('vlib',[lib])
        invoke('vlog',['-quiet','-work','ph1',*models])
        invoke('vlog',['-quiet','-timescale','1ns/1ps','+define+PH1',*sources[:-1]])
        invoke('vlog',['-quiet','-sv','+define+PH1',sources[-1]])
        invoke('vsim',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_stereo_he',
                       '-l','run.log','-do','run -all; quit -f'])
        log=(run/'run.log').read_text(errors='replace')
        if 'RESULT: PASS STEREO_HE frames=8 pixels=64' not in log or identity()!=record['inputs']:
            raise RuntimeError('test failed or inputs changed; inspect run.log')
        record['status']='PASS'
    finally:
        (run/'RESULTS.json').write_text(json.dumps(record,indent=2)+'\n')
    print(run, record['status'])

if __name__=='__main__':
    main()
