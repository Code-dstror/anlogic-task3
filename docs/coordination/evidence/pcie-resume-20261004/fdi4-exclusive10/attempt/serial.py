import os,time,select,termios,tty,json,re
from pathlib import Path
root=Path(__file__).resolve().parent
port=Path('/dev/serial/by-id/usb-1a86_USB_Single_Serial_5B32022900-if00')
real=str(port.resolve(strict=True));holders=[]
for p in Path('/proc').iterdir():
 if not p.name.isdigit():continue
 try:
  for f in (p/'fd').iterdir():
   try:
    if os.readlink(f)==real:holders.append((p.name,(p/'comm').read_text().strip()))
   except OSError:pass
 except OSError:pass
assert not holders,holders
fd=None;attrs=None;raw=bytearray()
try:
 fd=os.open(port,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
 attrs=termios.tcgetattr(fd);tty.setraw(fd,termios.TCSANOW)
 a=termios.tcgetattr(fd);a[4]=a[5]=termios.B1500000
 a[2]=(a[2]&~(termios.PARENB|termios.CSTOPB|termios.CSIZE|termios.CRTSCTS))|termios.CS8|termios.CREAD|termios.CLOCAL
 termios.tcsetattr(fd,termios.TCSANOW,a)
 def collect(seconds):
  until=time.monotonic()+seconds
  while time.monotonic()<until:
   if select.select([fd],[],[],max(0,min(.1,until-time.monotonic())))[0]:
    try:raw.extend(os.read(fd,65536))
    except BlockingIOError:pass
 collect(.5);os.write(fd,b'\r');collect(1)
 clean=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',raw.decode(errors='replace'))
 assert re.search(r'root@linaro-alip:[^\r\n]*#\s*$',clean),repr(clean[-400:])
 print('RK shell prompt confirmed',flush=True)
 cmd="python3 - <<'TASK3_READONLY_EOF'\r"+(root/'query.py').read_text().replace('\n','\r')+"\rTASK3_READONLY_EOF\r"
 for start in range(0,len(cmd),96):
  b=cmd[start:start+96].encode();sent=0
  while sent<len(b):
   try:sent+=os.write(fd,b[sent:])
   except BlockingIOError:time.sleep(.02)
  collect(.01)
 end=time.monotonic()+90
 while time.monotonic()<end:
  collect(.2)
  if b'\nTASK3_RESULT_END\r\n' in raw:collect(.2);break
 text=raw.decode(errors='replace').replace('\r\n','\n')
 start=text.index('TASK3_RESULT_BEGIN\n')+len('TASK3_RESULT_BEGIN\n');stop=text.index('\nTASK3_RESULT_END',start)
 result=json.loads(text[start:stop]);(root/'result.json').write_text(json.dumps(result,indent=2))
 shown={k:v for k,v in result.items() if k not in ('root_link_before','root_link_after','dmesg','trace','frames')}
 shown['frames']=[{'index':x['index'],'capture':x.get('capture'),'bytes':x.get('bytes'),'exception':x.get('exception')} for x in result.get('frames',[])]
 print(json.dumps(shown,indent=2),flush=True)
finally:
 if fd is not None:
  try:
   if attrs is not None:termios.tcsetattr(fd,termios.TCSANOW,attrs)
  finally:os.close(fd)
 with (root/'serial.raw').open('xb') as f:f.write(raw)
 print('Serial released',flush=True)
