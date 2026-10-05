import unittest
from linux.pcie_transport import pcie_protocol_v1 as p
from linux.pcie_transport.capture_v1_record import capture_one, CaptureError
from linux.pcie_transport.session_rearm import wait_for_session_rearm_ready, SessionRearmTimeout
from tests.test_capture_v1_record import FakeBar, FakeWorker, FakeTime, make_record

class StopOrderTests(unittest.TestCase):
 def test_disable_before_raw_sink_and_accept_stopped_busy(self):
  class BusyAfterArm(FakeBar):
   def read32(self,offset):
    value=super().read32(offset)
    return value|p.PCIE_STATUS_TX_BUSY if offset==p.PCIE_REG_STATUS and self.armed else value
  bar=BusyAfterArm();worker=FakeWorker(bar,('ok',make_record()));saved=[]
  def sink(data):
   self.assertEqual(bar.events[-1],('write',p.PCIE_REG_CONTROL,0))
   saved.append(data)
  record,_=capture_one(bar,'unused',4096,1,worker_factory=lambda *a:worker,record_sink=sink)
  self.assertEqual(saved,[record])
  self.assertEqual(sum(e==('write',p.PCIE_REG_CONTROL,2) for e in bar.events),0)
 def test_malformed_raw_preserved_after_disable(self):
  bar=FakeBar();worker=FakeWorker(bar,('ok',b'bad'));saved=[]
  def sink(data):
   self.assertEqual(bar.events[-1],('write',p.PCIE_REG_CONTROL,0));saved.append(data)
  with self.assertRaises(CaptureError):capture_one(bar,'unused',4096,1,worker_factory=lambda *a:worker,record_sink=sink)
  self.assertEqual(saved,[b'bad']);self.assertTrue(worker.closed)
 def test_rearm_waits_for_busy_clear_with_one_reset(self):
  ticks=FakeTime();writes=[];states=iter([0x8b,0x6b,0x63])
  value=wait_for_session_rearm_ready(lambda _:next(states),lambda o,v:writes.append(v),1,clock=ticks.clock,sleep=ticks.sleep)
  self.assertEqual(value,0x63);self.assertEqual(writes,[2])
 def test_rearm_persistent_busy_times_out(self):
  ticks=FakeTime();writes=[];reads=[0]
  def read(_):
   reads[0]+=1;return 0x8b if reads[0]==1 else 0x6b
  with self.assertRaises(SessionRearmTimeout):wait_for_session_rearm_ready(read,lambda o,v:writes.append(v),.003,clock=ticks.clock,sleep=ticks.sleep)
  self.assertEqual(writes,[2,0])
