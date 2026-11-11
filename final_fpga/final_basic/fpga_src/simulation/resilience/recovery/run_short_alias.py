"""All 16 representable early-lane aliases must fail the old SOURCE, then recover."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,time
HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source-root',type=Path,required=True);ap.add_argument('--output-root',type=Path,required=True);ap.add_argument('--name',required=True);ap.add_argument('--modelsim-bin',type=Path,required=True);args=ap.parse_args()
 if not re.fullmatch('[a-z0-9_]+',args.name):ap.error('ASCII name required')
 run=args.output_root.resolve()/args.name;run.mkdir(parents=True,exist_ok=False);started=time.monotonic()
 result=dict(status='IN_PROGRESS',inputs=[],commands=[],synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
 def copy(p,name):
  target=run/'inputs'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(p.read_bytes());result['inputs'].append(dict(original=str(p.resolve()),path=str(target),sha256=sha(target)));return target
 def cmd(name,words):
  argv=[str(args.modelsim_bin/words[0]),*map(str,words[1:])];result['commands'].append(dict(cwd=str(run),argv=argv));p=subprocess.run(argv,cwd=run,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=90);(run/(name+'.console.log')).write_text(p.stdout,encoding='utf-8')
  if p.returncode:raise RuntimeError(name+': '+p.stdout[-3000:])
 try:
  sources=[copy(args.source_root/'src_fpga/rtl'/name,Path('rtl')/name) for name in ('physical_csi_word_core.v','csi_rx_byte_align_observed.v','csi_rx_word_align_observed.v')]
  sources.append(copy(args.source_root/'src_fpga/ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v',Path('ip/csi_rx_word_gear_box.v')))
  fixture=copy(HERE/'vectors/short_alias.json',Path('vectors/short_alias.json'));template=copy(HERE/'templates/closedloop.sv',Path('templates/closedloop.sv'))
  rows=json.loads(fixture.read_text(encoding='utf-8'))['cases'];lines=[]
  for row in rows:
   e=lines.append;e(f'start_case("{row["name"]}_real_feedback",1\'b0);expected_ctrl=-1;')
   expected=[int(x,16) for x in row['expected_words']];payload=b''.join(x.to_bytes(4,'little') for x in expected[1:])[:60]
   for i in range(12):
    b=payload[5*i:5*i+5];value=sum(((b[j]<<2)|((b[4]>>(2*j))&3))<<(10*j) for j in range(4));e(f"golden[{i}]=40'h{value:010x};")
   e("short_packet(32'h00000000,40);")
   for word in row['raw_words']:e(f"ww(32'h{word:08x});")
   e('zero(40);check(negs==1&&positive==0,"malformed alias did not negatively terminate exactly the old SOURCE");check(!owner,"old SOURCE terminal missing before next FS");check(eol1==0,"corrupted frame released a final EOL group");')
   e("short_packet(32'h00000000,40);ww(32'hb8b8b8b8);")
   for word in expected:e(f"ww(32'h{word:08x});")
   e("zero(40);short_packet(32'h07000001,40);zero(30);check(nctrl==4,\"old/new control conservation\");check(positive==1&&negs==1,\"clean following SOURCE failed\");finish_case(2,1'b0,3'bxxx,-1,12);")
  bench=template.read_text(encoding='utf-8').replace('__CASES__','\n'.join(lines)).replace('#(.RX_DIAG_ENABLE(1)) dut(','#(.RX_DIAG_ENABLE(1),.FRAME_RESYNC_ENABLE(1)) dut(')
  # This suite checks authentic terminal/identity recovery. Exact sticky error
  # category varies with lane/lead and is retained in the log, not guessed.
  bench=bench.replace('check({le,ce,ee}===err,"sticky errors");','if(err!==3\'bxxx)check({le,ce,ee}===err,"sticky errors");')
  target=run/'tb_closedloop.sv';target.write_text(bench,encoding='utf-8');result['bench_sha256']=sha(target)
  cmd('version',['vsim.exe','-version']);cmd('vmap',['vmap.exe','-c']);cmd('work',['vlib.exe','work']);cmd('compile',['vlog.exe','-quiet','-sv','-l','compile.log',*sources,target]);cmd('run',['vsim.exe','-c','-voptargs=+acc','work.tb_closedloop','-l','run.log','-do','run -all; quit -f'])
  log=(run/'run.log').read_text(errors='replace');result['cases']=[dict(name=m[0],status=m[1],details=m[2]) for m in re.findall(r'CASE\|([^|]+)\|(PASS|FAIL)\|([^\r\n]+)',log)];result['metrics']=[x.lstrip('# ') for x in log.splitlines() if 'RESULT|' in x];result['mismatches']=[x.lstrip('# ') for x in log.splitlines() if 'MISMATCH|' in x];result['warnings']=[x for p in ('compile.log','run.log') for x in (run/p).read_text(errors='replace').splitlines() if re.search(r'\*\* (Warning|Error|Fatal)',x)]
  if len(result['cases'])!=16 or not result['metrics']:raise RuntimeError('incomplete bounded result')
  for item in result['inputs']:
   if sha(Path(item['original']))!=item['sha256'] or sha(Path(item['path']))!=item['sha256']:raise RuntimeError('input drift')
  result['status']='FAIL' if result['mismatches'] or result['warnings'] else 'PASS'
 except Exception as exc:result.update(status='FAIL',error=str(exc));raise
 finally:
  result['elapsed_seconds']=round(time.monotonic()-started,3);(run/'RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:result.get(k) for k in ('status','metrics','cases','mismatches','warnings','error')},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
