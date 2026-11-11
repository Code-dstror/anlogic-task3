"""Source-bound color subsystem comparison against the full-build Rate R2 parent."""
import argparse, importlib.util, json
from pathlib import Path

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
REPO=PROJECT.parents[1]
original=PROJECT.parent/'camera_hdr_quality_r1/analysis/tone'
spec=importlib.util.spec_from_file_location('color_native_runner',original/'run_probe.py')
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.BASELINE='d1e5dce43634bd303663342106cf57a26f700394'
m.PARENT_SRC='refactor/camera_rate_r2/src_fpga'
m.REPO=REPO
m.LIMIT_SECONDS=150

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--name',required=True)
    parser.add_argument('--td-root',type=Path,required=True)
    args=parser.parse_args()
    if not args.name.isascii() or not args.name.replace('_','').isalnum():
        parser.error('Use a fresh ASCII label')
    work=PROJECT/'tmp/color_parent_compare'/args.name
    work.mkdir(parents=True,exist_ok=False)
    carrier=work/'carrier';carrier.mkdir()
    for name in ('probe.v','probe.sdc','probe.tcl'):
        (carrier/name).write_bytes((original/name).read_bytes())
    m.HERE=carrier
    staging=work/'candidate_inputs'
    for name in m.DIFFERING:
        dst=staging/'src_fpga'/name
        dst.parent.mkdir(parents=True,exist_ok=True)
        src=HERE/'candidate/wide_color_pipeline.v' if name=='rtl/wide_color_pipeline.v' else PROJECT/'src_fpga'/name
        dst.write_bytes(src.read_bytes())
    m.PROJECT=staging
    ip_files=tuple(p.relative_to(PROJECT/'src_fpga').as_posix()
                   for prefix in m.IP_PREFIXES for p in (PROJECT/'src_fpga'/prefix).rglob('*') if p.is_file())
    common={name:(PROJECT/'src_fpga'/name).read_bytes() for name in (*ip_files,*m.RTL[2:],m.DATA[0])}
    # All frozen IP, generic multiplier and Gamma bytes must match the old full-build source.
    for name,content in common.items():
        if content.replace(b'\r\n',b'\n')!=m.fixed_bytes(name).replace(b'\r\n',b'\n'):
            raise RuntimeError('Frozen parent input differs: '+name)
    results=[m.run_variant(work/label,variant,common,args.td_root.resolve())
             for label,variant in [('rate_r2',False),('fused_optimized',True)]]
    (work/'RESULTS.json').write_text(json.dumps({'status':'PASS' if all(results) else 'FAIL',
        'baseline_commit':m.BASELINE,'whole_design_synthesis':'NOT_RUN','physical_STA':'NOT_RUN'},indent=2)+'\n')
    return 0 if all(results) else 1

if __name__=='__main__':
    raise SystemExit(main())
