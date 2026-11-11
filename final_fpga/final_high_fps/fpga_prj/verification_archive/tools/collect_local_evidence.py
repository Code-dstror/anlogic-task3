"""Retain small source-bound local qualification evidence; never copy tool databases."""
from pathlib import Path
import argparse, hashlib, json, shutil

ROOT=Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--product-run',required=True)
    args=parser.parse_args()
    if not args.product_run.startswith('blackbox_fusion_product_') or Path(args.product_run).name!=args.product_run:
        parser.error('Supply one existing product run basename')
    paths=[
        'tmp/blackbox_fusion_config_all_01',
        'tmp/blackbox_fusion_uart_01',
        'tmp/blackbox_fusion_datapath_raw_02',
        'tmp/blackbox_fusion_datapath_isp_02',
        'tmp/blackbox_fusion_datapath_merge_03',
        'tmp/blackbox_fusion_datapath_reader_01',
        'tmp/'+args.product_run,
        'tmp/native_read_final',
        'tmp/native_hierarchy_final_a2',
        'tmp/native_hierarchy_final',
        'tmp/blackbox_fusion_config_sdk_05',
        'tmp/blackbox_fusion_product_a10_all_b',
        'tmp/blackbox_fusion_product_a12_all',
        'tmp/color_pipe_equiv/identity_a1',
        'tmp/color_parent_compare/parent_a1',
        'tmp/control_flit_equiv/w375_a2',
        'tmp/control_flit_equiv/w147_a1',
        'experiments/raw_ingress_equiv/runs/full_window_r1',
    ]
    for relative in paths:
        if not (ROOT/relative).is_dir():
            raise RuntimeError('Required evidence source missing: '+relative)
    destination=ROOT/'docs/validation_20261110'
    destination.mkdir(exist_ok=False)
    records=[]
    for relative in paths:
        source=ROOT/relative
        if not source.is_dir():
            raise RuntimeError('Required evidence source missing: '+relative)
        files=[]
        for p in sorted(source.rglob('*')):
            if not p.is_file() or any(part.endswith('_Runs') or part in {'work','ph1','rom_init','libraries'}
                                      for part in p.relative_to(source).parts):
                continue
            if p.suffix not in {'.log','.json','.area','.params','.timing','.rpt'}:
                continue
            if p.stat().st_size>2_000_000:
                continue
            label=relative.replace('/','__')
            target=destination/label/p.relative_to(source)
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(p,target)
            if sha(p)!=sha(target):
                raise RuntimeError('Evidence copy changed bytes: '+str(p))
            files.append({'original':p.relative_to(ROOT).as_posix(),
                          'retained':target.relative_to(ROOT).as_posix(),
                          'sha256':sha(target),'bytes':target.stat().st_size})
        records.append({'run':relative,'files':files})
    seal=json.loads((ROOT/'docs/SOURCE_SEAL.json').read_bytes())
    index={'design_sha256':seal['design_sha256'],'source_seal_sha256':sha(ROOT/'docs/SOURCE_SEAL.json'),
           'scope':'Small immutable logs/results; model databases and reproducible vectors stay in original runs.',
           'records':records}
    (destination/'INDEX.json').write_text(json.dumps(index,indent=2)+'\n')
    print(json.dumps({'records':len(records),'files':sum(len(r['files']) for r in records),
                      'bytes':sum(f['bytes'] for r in records for f in r['files']),
                      'design_sha256':index['design_sha256']}))

if __name__=='__main__':
    main()
