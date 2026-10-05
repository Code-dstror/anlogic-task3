expected_files={'linux/task3_pipeline/capture_v1_record.py': 'a263a64c9275db37e5f5accd5dc4f2a9cf00ca28372be2ec7f0591e752e55a59', 'linux/task3_pipeline/session_rearm.py': '2cf1768e9c637266bc50850e619369445f376b7b2670ddc5872a45b4ca84e74b', 'linux/task3_pipeline/pcie_protocol_v1.py': '2d5dd5d7a18196b24c8888b5e3fa6f50489c9fb374d94c1bda0d64107f4c7e73', 'tests/test_capture_v1_record.py': '08f6154feccc6add75b1237f44b0a3c5e9e88b6d396b2dadd8486290a79949f0', 'tests/test_session_rearm.py': '08b9c23e941b6aa7846a6221436437a65eca1d36bfc5c888e1a822c2fdb48e4d', 'docs/pcie_protocol_v1.json': '7e337af3d41467ede724d8d0685ac230358203dabca78255404e15900829f449', 'fpga_debug/20260930/host_tools/fixtures/c2h_fixture_395.record': '949e5784bdc0101421596c3e93b39d5fa51dfaf20bedba1e1119e737f7d7eab7', 'linux/__init__.py': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'linux/task3_pipeline/__init__.py': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'tests/__init__.py': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'}
import os,json,time,hashlib,subprocess,traceback,sys,tempfile,stat
from pathlib import Path
r={'operation':'authorized FDI4 ten independent single-record sessions','boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'uptime_before':Path('/proc/uptime').read_text().strip()}
def run(args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=15)
 return {'code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def snapshot(bar):
 return {hex(off):hex(bar.read32(off)) for off in range(0,64,4)}
try:
 assert r['boot_id']=='ef755806-6941-41d6-8d43-d109ed7ead89','Boot changed'
 pkg=Path('/tmp/task3-fdi4-capture-vc4vuuhy')
 for name,h in expected_files.items():assert hashlib.sha256((pkg/name).read_bytes()).hexdigest()==h,name
 assert Path('/sys/module/anlogic_pci').exists(),'Driver absent'
 r['parameters']={p.name:p.read_text().strip() for p in Path('/sys/module/anlogic_pci/parameters').glob('*')}
 assert r['parameters']['poll_mode']=='1' and r['parameters']['enable_st_c2h_credit']=='1'
 eps=[p for p in Path('/sys/bus/pci/devices').iterdir() if (p/'vendor').read_text().strip()=='0x1edb' and (p/'device').read_text().strip()=='0xabcd']
 assert len(eps)==1
 ep=eps[0];r['endpoint']=ep.name
 assert (ep/'driver').resolve().name=='Anlogic-pcie'
 r['root_link_before']=run(['lspci','-Dnnvv','-s',ep.resolve().parent.name])
 assert 'DLActive+' in r['root_link_before']['stdout'],'Root link inactive'
 nodes={}
 for n in Path('/dev').glob('ANLOGIC*'):
  st=n.stat();sp=(Path('/sys/dev/char')/(str(os.major(st.st_rdev))+':'+str(os.minor(st.st_rdev)))).resolve()
  if stat.S_ISCHR(st.st_mode) and str(ep.resolve())+'/' in str(sp):nodes[n.name]=str(n)
 users=[v for k,v in nodes.items() if k.endswith('_user')];c2hs=[v for k,v in nodes.items() if k.endswith('_c2h_0')]
 assert len(users)==len(c2hs)==1
 r['nodes']={'user':users[0],'c2h':c2hs[0]}
 holders=[]
 for proc in Path('/proc').iterdir():
  if not proc.name.isdigit():continue
  try:
   for f in (proc/'fd').iterdir():
    try:
     if os.readlink(f) in nodes.values():holders.append([proc.name,f.name,os.readlink(f)])
    except OSError:pass
  except OSError:pass
 assert not holders,holders
 os.chdir(pkg);sys.path.insert(0,str(pkg))
 from linux.task3_pipeline.capture_v1_record import UserBar,ProcessReader,capture_one,validate_device
 out=Path(tempfile.mkdtemp(prefix='task3-fdi4-repeat10-'));r['output_directory']=str(out);r['trace']=[]
 class TracedBar(UserBar):
  last_status=None
  def read32(self,off):
   value=super().read32(off)
   if off==0x1c and value!=self.last_status:
    r['trace'].append({'time':time.monotonic(),'status':hex(value)})
    self.last_status=value
   return value
  def write32(self,off,value):
   assert off==0x18 and value in (0,1,2),'Unexpected reset/control write refused'
   r['trace'].append({'time':time.monotonic(),'write':hex(off),'value':value})
   return super().write32(off,value)
 class SavedReader(ProcessReader):
  def receive(self):
   kind,value=super().receive()
   if kind=='ok' and isinstance(value,bytes):
    (out/'received.raw').write_bytes(value)
    r['raw_bytes']=len(value);r['raw_sha256']=hashlib.sha256(value).hexdigest()
   return kind,value
 batch=out;r['frames']=[]
 with TracedBar(users[0]) as bar:
  validate_device(bar.read32);r['registers_before']=snapshot(bar)
  assert bar.read32(0x18)==0 and bar.read32(0x1c)==0x83,'Previous completed session state changed'
  assert bar.read32(0x10)==16777216 and bar.read32(0x14)==64
  initial_producer=bar.read32(0x28);initial_consumed=bar.read32(0x2c)
  for index in range(1,11):
   out=batch/('frame-%02d'%index);out.mkdir()
   item={'index':index,'start':time.monotonic()};r['frames'].append(item)
   r['trace'].append({'frame':index,'start':time.monotonic()})
   try:
    assert bar.read32(0x18)==0 and bar.read32(0x1c)==0x83,'Session not in expected stopped state'
    assert bar.read32(0x38)==0 and bar.read32(0x3c)==0,'Error already present'
    data,header=capture_one(bar,c2hs[0],16777280,10,worker_factory=SavedReader)
    (out/'frame.record').write_bytes(data);(out/'frame.jpg').write_bytes(data[64:])
    item.update({'capture':'PASS','bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'header':header,'registers_after':snapshot(bar)})
    assert bar.read32(0x18)==0 and bar.read32(0x1c)==0x83,'Unexpected end state'
    assert bar.read32(0x28)==initial_producer+index and bar.read32(0x2c)==initial_consumed+index,'Count mismatch'
    assert bar.read32(0x38)==0 and bar.read32(0x3c)==0,'DMA error'
   except Exception as exc:
    item.update({'capture':'FAIL','exception':str(exc),'traceback':traceback.format_exc()})
    break
   finally:
    item['end']=time.monotonic()
    (batch/'progress.json').write_text(json.dumps(r,indent=2,default=lambda x:x.hex() if isinstance(x,bytes) else str(x)))
  r['registers_after']=snapshot(bar)
 r['capture']='PASS' if len(r['frames'])==10 and all(x['capture']=='PASS' for x in r['frames']) else 'FAIL_STOPPED'
 r['root_link_after']=run(['lspci','-Dnnvv','-s',ep.resolve().parent.name])
except Exception as exc:r['exception']=str(exc);r['traceback']=traceback.format_exc()
r['uptime_after']=Path('/proc/uptime').read_text().strip()
d=run(['dmesg']);d['stdout']='\n'.join(d['stdout'].splitlines()[-100:]);r['dmesg']=d
if 'output_directory' in r:Path(r['output_directory'],'result.json').write_text(json.dumps(r,indent=2,default=lambda x:x.hex() if isinstance(x,bytes) else str(x)))
print('TASK3_RESULT_BEGIN',flush=True)
print(json.dumps(r,default=lambda x:x.hex() if isinstance(x,bytes) else str(x)),flush=True)
print('TASK3_RESULT_END',flush=True)
