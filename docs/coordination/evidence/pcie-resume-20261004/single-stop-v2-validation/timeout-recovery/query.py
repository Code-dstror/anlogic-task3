expected_files={'candidate-origin.json': 'fff8cc3cd851c09855c21bf6bbc685ab72a1d3ca74b86dfc1f201ea7bf52e9bc', 'docs/pcie_protocol_v1.json': '7e337af3d41467ede724d8d0685ac230358203dabca78255404e15900829f449', 'linux/__init__.py': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'linux/task3_pipeline/pcie_protocol_v1.py': '2d5dd5d7a18196b24c8888b5e3fa6f50489c9fb374d94c1bda0d64107f4c7e73', 'linux/task3_pipeline/capture_v1_record.py': '8ba54580eeea25a8ead8c5e9b448e25821f85f8a89016e6b01d7038bf75865ac', 'linux/task3_pipeline/__init__.py': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'linux/task3_pipeline/session_rearm.py': '615e0df8bc7dfa6ecb34881561e139f3d12bda5b699b2f1ee5c6b435ec3df4f9', 'tests/test_single_frame_stop_order.py': 'e08ffb8fbb549667b2949ea39c36852ef73632dfa60714a0bec8c2f67309f3fa', 'tests/test_session_rearm.py': '08b9c23e941b6aa7846a6221436437a65eca1d36bfc5c888e1a822c2fdb48e4d', 'tests/__init__.py': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'tests/test_capture_v1_record.py': '08f6154feccc6add75b1237f44b0a3c5e9e88b6d396b2dadd8486290a79949f0', 'fpga_debug/20260930/host_tools/fixtures/c2h_fixture_395.record': '949e5784bdc0101421596c3e93b39d5fa51dfaf20bedba1e1119e737f7d7eab7'}
import os,json,time,hashlib,subprocess,traceback,sys,tempfile,stat
from pathlib import Path
r={'operation':'FDI4 no-data timeout and one recovery capture','boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'uptime_before':Path('/proc/uptime').read_text().strip()}
def run(args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=15)
 return {'code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def snapshot(bar):
 return {hex(off):hex(bar.read32(off)) for off in range(0,64,4)}
try:
 assert r['boot_id']=='ef755806-6941-41d6-8d43-d109ed7ead89','Boot changed'
 pkg=Path('/tmp/task3-stop-v2-4b0kcmgz')
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
 out=Path(tempfile.mkdtemp(prefix='task3-stop-v2-timeout-'));r['output_directory']=str(out);r['trace']=[]
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
 def save_raw(data):
  assert bar.read32(0x18)==0,'Raw save before APP_ENABLE disabled'
  r['trace'].append({'time':time.monotonic(),'event':'raw_save_after_disable'})
  (out/'received.raw').write_bytes(data)
 class CheckedReader(ProcessReader):
  def start(self):
   state=bar.read32(0x1c)
   assert state&0x40 and not state&0x8,'Rearm not ready/idle before DMA'
   r['trace'].append({'time':time.monotonic(),'event':'start_dma_after_rearm','status':hex(state)})
   super().start()
 batch=out;r['frames']=[]
 with TracedBar(users[0]) as bar:
  validate_device(bar.read32);r['registers_before']=snapshot(bar)
  assert bar.read32(0x18)==0 and bar.read32(0x1c) in (0x83,0x8b),'Stopped state changed'
  assert bar.read32(0x10)==16777216 and bar.read32(0x14)==64
  from linux.task3_pipeline.session_rearm import wait_for_session_rearm_ready
  from linux.task3_pipeline.capture_v1_record import _wait_dma_running, _cleanup_worker
  wait_for_session_rearm_ready(bar.read32,bar.write32,10)
  worker=CheckedReader(c2hs[0],16777280)
  nt={'start':time.monotonic()};r['no_data_test']=nt
  try:
   worker.start()
   _wait_dma_running(bar.read32,worker,10,.001,time.monotonic,time.sleep)
   nt['running_observed']=True
   assert bar.read32(0x18)==0,'APP_ENABLE unexpectedly set'
   deadline=time.monotonic()+12
   while not worker.poll() and time.monotonic()<deadline:time.sleep(.02)
   if worker.poll():
    kind,value=worker.receive();nt['reader_result']={'kind':kind,'value':value if not isinstance(value,bytes) else {'bytes':len(value)}}
    nt['natural_completion']=True
    assert kind=='error','Expected driver read timeout/error with no app enable'
   else:
    nt['natural_completion']=False
    raise TimeoutError('Driver no-data read did not complete within12s; cleanup requested')
  finally:
   bar.write32(0x18,0)
   _cleanup_worker(worker,12,force=True)
   nt['end']=time.monotonic();nt['registers_after']=snapshot(bar)
  assert not bar.read32(0x1c)&4,'C2H still running after no-data cleanup'
  assert bar.read32(0x1c)&0x40 and not bar.read32(0x1c)&8,'Rearm state not ready after no-data'
  initial_producer=bar.read32(0x28);initial_consumed=bar.read32(0x2c)
  for index in range(1,2):
   out=batch/('frame-%02d'%index);out.mkdir()
   item={'index':index,'start':time.monotonic()};r['frames'].append(item)
   r['trace'].append({'frame':index,'start':time.monotonic()})
   try:
    assert bar.read32(0x18)==0 and bar.read32(0x1c) in (0x43,0x63),'Session not rearm ready after no-data'
    assert bar.read32(0x38)==0 and bar.read32(0x3c)==0,'Error already present'
    data,header=capture_one(bar,c2hs[0],16777280,10,worker_factory=CheckedReader,record_sink=save_raw)
    (out/'frame.record').write_bytes(data);(out/'frame.jpg').write_bytes(data[64:])
    item.update({'capture':'PASS','bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'header':header,'registers_after':snapshot(bar)})
    assert bar.read32(0x18)==0 and bar.read32(0x1c) in (0x83,0x8b),'Unexpected end state'
    assert bar.read32(0x28)==initial_producer+index and bar.read32(0x2c)==initial_consumed+index,'Count mismatch'
    assert bar.read32(0x38)==0 and bar.read32(0x3c)==0,'DMA error'
   except Exception as exc:
    item.update({'capture':'FAIL','exception':str(exc),'traceback':traceback.format_exc()})
    break
   finally:
    item['end']=time.monotonic()
    (batch/'progress.json').write_text(json.dumps(r,indent=2,default=lambda x:x.hex() if isinstance(x,bytes) else str(x)))
  r['registers_after']=snapshot(bar)
 r['capture']='PASS' if len(r['frames'])==1 and all(x['capture']=='PASS' for x in r['frames']) else 'FAIL_STOPPED'
 r['root_link_after']=run(['lspci','-Dnnvv','-s',ep.resolve().parent.name])
except Exception as exc:r['exception']=str(exc);r['traceback']=traceback.format_exc()
r['uptime_after']=Path('/proc/uptime').read_text().strip()
d=run(['dmesg']);d['stdout']='\n'.join(d['stdout'].splitlines()[-100:]);r['dmesg']=d
if 'output_directory' in r:Path(r['output_directory'],'result.json').write_text(json.dumps(r,indent=2,default=lambda x:x.hex() if isinstance(x,bytes) else str(x)))
print('TASK3_RESULT_BEGIN',flush=True)
print(json.dumps(r,default=lambda x:x.hex() if isinstance(x,bytes) else str(x)),flush=True)
print('TASK3_RESULT_END',flush=True)
