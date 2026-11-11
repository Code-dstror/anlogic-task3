"""Short source-bound admission subsystem tests for the current resilient candidate."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[3]
ROOT=PROJECT.parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--name',required=True);ap.add_argument('--modelsim-bin',type=Path,required=True)
a=ap.parse_args();assert re.fullmatch(r'[a-z][a-z0-9_]{0,48}',a.name)
run=PROJECT/'tmp/resilience/admission'/a.name;run.mkdir(parents=True,exist_ok=False)
names=['anlogic2026.v','physical_identity_source_fence.v','frame_admission_qualification.v','jpeg_frame_admission.v',
       'frame_record_extension_builder.v','frame_record_v3_join.v','cfg_diag_pixel.v','include/04_include/pcie_protocol_v1.vh']
inputs=[]
for n in names:
    source=PROJECT/'src_fpga/rtl'/n;data=source.read_bytes();dest=run/Path(n).name;dest.write_bytes(data)
    inputs.append({'path':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(data).hexdigest()})
top=(run/'anlogic2026.v').read_text()
start=top.index('        // Keep an already queued next FS');end=top.index('        physical_identity_source_fence #',start)
snippet=top[start:end]
(run/'top_admission.vh').write_text(snippet)
body=(HERE/'tb.sv').read_text().replace('__TOP_ADMISSION__',snippet)
fence_end=top.index(');',end)+2
fence=top[end:fence_end].replace(' u_fence(', ' fence(').replace('.o_drop_count(),.o_stale_event_count()', '.o_drop_count(drop_count),.o_stale_event_count(stale_count)')
(run/'top_fence.vh').write_text(fence)
body=body.replace('__TOP_FENCE__',fence)
(run/'tb.sv').write_text(body)
result={'status':'IN_PROGRESS','baseline_commit':'b68fdc2d79b9ae3579174366f0fdce89dfc9f389','candidate':'hdr_rx_resilient',
 'inputs':inputs,'scope':'TOP defer/admission block plus actual qualification/fence/JPEG admission. Additional real extension builder+V3 join+CFG observer cases. Events/encoder arithmetic/CSI/DDR/native transport/CDC are excluded. Conditional resource tests remain labeled conditional.',
 'commands':[],'synthesis':'NOT_RUN','pnr':'NOT_RUN','timing':'NOT_RUN','board':'NOT_RUN'}
try:
    for i,args in enumerate([['vlib.exe','work'],['vlog.exe','-sv','+incdir+.','-work','work']+[Path(n).name for n in names if n.endswith('.v') and n!='anlogic2026.v']+['tb.sv'],['vsim.exe','-c','work.tb','-do','onerror {quit -code 1}; run -all; quit -f']]):
        cmd=[str(a.modelsim_bin/args[0])]+args[1:];result['commands'].append(cmd)
        p=subprocess.run(cmd,cwd=run,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=120)
        (run/f'command_{i}.log').write_text(p.stdout)
        if p.returncode or re.search(r'\*\* (?:Error|Fatal):',p.stdout):raise RuntimeError(p.stdout[-8000:])
    if 'RESULT PASS ADVERSARIAL_RETIREMENT' not in p.stdout:raise RuntimeError('PASS sentinel absent')
    result['metrics']=[x for x in p.stdout.splitlines() if 'CASE ' in x or 'RESULT ' in x]
    result['source_changes_during_run']=[x['path'] for x in inputs if hashlib.sha256((ROOT/x['path']).read_bytes()).hexdigest()!=x['sha256']]
    result['status']='STALE' if result['source_changes_during_run'] else 'PASS'
except Exception as e:
    result['status']='BLOCKED' if isinstance(e,OSError) else 'FAIL';result['error']=str(e);raise
finally:
    result['bench_sha256']=hashlib.sha256((run/'tb.sv').read_bytes()).hexdigest()
    (run/'RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2))
