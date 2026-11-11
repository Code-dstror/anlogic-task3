"""Exercise online schema2 configuration using the complete physical dual-camera TOP fixture."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import sys

HERE=Path(__file__).resolve().parent
BASE=HERE.parent/'unified_dual_rate'
ROOT=HERE.parents[2]


def replace_once(text, original, changed):
    if text.count(original)!=1:
        raise ValueError('dual MAIN fixture changed at '+original)
    return text.replace(original, changed)


def main():
    args=argparse.ArgumentParser(description=__doc__)
    args.add_argument('--name',required=True)
    args.add_argument('--modelsim-bin',type=Path,required=True)
    args.add_argument('--td-root',type=Path,required=True)
    args.add_argument('--dehaze',action='store_true',help='apply DCP+HE+gray+Gaussian, then return to color')
    opts=args.parse_args()
    if not opts.name.isidentifier():args.error('invalid run name')
    stage=ROOT/'tmp/stereo_filter_cfg'/opts.name
    stage.mkdir(parents=True,exist_ok=False)
    for name in ('axi_boundaries.sv','check.py','dual_reference.py','PROVENANCE.json','unified_rate_monitor.vh'):
        shutil.copyfile(BASE/name,stage/name)
    bench=(BASE/'tb_unified_dual_rate.sv').read_text(encoding='utf-8')
    bench=replace_once(bench,'        set_jpeg_quality();','        // Use cold BOOT epoch0.')
    bench=replace_once(bench,'    integer guard,old_crc;', (HERE/'online_cfg.vh').read_text(encoding='utf-8-sig')+'\n    integer guard,old_crc;')
    calls = 'dual_filter_config(15,0);dual_filter_config(0,1);' if opts.dehaze else 'dual_filter_config(13,0);'
    bench=replace_once(bench,'        observer_mode_ready_at=$time;', f'''        {calls}
        write_bar(`PCIE_REG_CONTROL,0);wait(dut.raw_region_quiet);
        done=1;$display("RESULT: PASS UNIFIED_DUAL_RATE_STARTUP online_cfg_test_only");$finish;
        observer_mode_ready_at=$time;''')
    (stage/'tb_unified_dual_rate.sv').write_text(bench,encoding='utf-8')
    spec=importlib.util.spec_from_file_location('dual_rate_runner',BASE/'run.py')
    runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
    runner.HERE=stage
    extra_inputs=[HERE/'online_cfg.vh',Path(__file__),BASE/'run.py',BASE/'tb_unified_dual_rate.sv']
    hashes={str(p):runner.sha(p) for p in extra_inputs}
    sys.argv=[str(BASE/'run.py'),'--startup-only','--name',opts.name,'--modelsim-bin',str(opts.modelsim_bin),
              '--td-root',str(opts.td_root),'--wall-timeout','180']
    runner.main()
    out=ROOT/'tmp/unified_dual_rate'/opts.name
    log=(out/'run.log').read_text(errors='replace')
    if log.count('RESULT: PASS DUAL_FILTER_ONLINE_CFG')!=(2 if opts.dehaze else 1) or hashes!={str(p):runner.sha(p) for p in extra_inputs}:
        raise RuntimeError('missing dual filter outcome or input changed')
    (out/'filter_cfg_result.json').write_text(json.dumps({'status':'PASS','profile_enables':[15,0] if opts.dehaze else [13],'additional_inputs':hashes,
        'scope':'armed dual AXI CFG, real cam0/cam1 crop and epoch, CRC negative terminals; no complete frame'},indent=2)+'\n')

if __name__=='__main__':main()
