"""Actual shell, single Receiver and CFG clients over the existing no-device RK ioctl fixture."""
from dataclasses import asdict
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from dual_host import pcie_protocol_v1 as s
from dual_host.stereo_control_v1 import STEREO_MAGIC
from linux.dma_c2h_candidate.c2h_legacy_policy import WRITABLE
from linux.rk_debug import cli
from linux.rk_debug.tests.test_session import SessionBar, SessionIO, Consumers
from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration
from test_shared_stereo import wire


class PhysicalBar(SessionBar):
    def __init__(self):
        super().__init__()
        self.registers.update({p.PCIE_REG_CFG_SESSION:7,p.PCIE_REG_CFG_ACTIVE_SESSION:7,
            p.PCIE_REG_CFG_MODE_EPOCH:0,p.PCIE_REG_CFG_EXT_V2_MODES:5,
            p.PCIE_REG_RECORD_SELECTED_VERSION:2,p.PCIE_REG_RECORD_SELECTED_HEADER_LENGTH:192,
            s.PCIE_REG_STEREO_MAGIC:STEREO_MAGIC,s.PCIE_REG_STEREO_ABI_VERSION:2,
            s.PCIE_REG_STEREO_CAPABILITIES:0xff000203,s.PCIE_REG_STEREO_ACTIVE_DIVISOR:2})
        self.registers[p.PCIE_REG_STATUS] |= p.PCIE_STATUS_LINK_UP | p.PCIE_STATUS_USER_RESET_RELEASED
        self.registers[p.PCIE_REG_RECORD_FEATURES] |= p.PCIE_RECORD_V4_FEATURE_VERSION4 | p.PCIE_RECORD_V4_FEATURE_LANE_POINTS
        self.registers[p.PCIE_REG_RECORD_SUPPORTED_VERSIONS] |= 1<<4

    def write32(self, offset, value):
        if offset in WRITABLE and offset >= s.PCIE_REG_STEREO_MAGIC:
            if value != {s.PCIE_REG_STEREO_REQUEST_MODE:1,s.PCIE_REG_STEREO_REQUEST_DIVISOR:2,
                         s.PCIE_REG_STEREO_COMMAND:1}[offset]:
                raise PermissionError('published DUAL/N2 kernel guard')
            self.writes.append((offset,value))
            self.registers[offset]=value
            if offset == s.PCIE_REG_STEREO_COMMAND:
                mode=self.registers[s.PCIE_REG_STEREO_REQUEST_MODE]
                self.registers.update({s.PCIE_REG_STEREO_ACTIVE_MODE:mode,s.PCIE_REG_STEREO_STATUS:2|(mode<<3),
                    s.PCIE_REG_STEREO_ACTIVE_DIVISOR:self.registers[s.PCIE_REG_STEREO_REQUEST_DIVISOR],
                    p.PCIE_REG_CFG_COMPILED_PROFILE:p.PCIE_CFG_PROFILE_DUAL1920 if mode else p.PCIE_CFG_PROFILE_MONO1920,
                    p.PCIE_REG_CFG_CAMERA_PRESENT:3 if mode else 1,p.PCIE_REG_CFG_EXT_V2_ENABLES:15 if mode else 63})
        else:
            super().write32(offset,value)


def wait_until(fn):
    end=time.monotonic()+2
    while not fn():
        if time.monotonic()>end:
            raise AssertionError('timed out waiting for the real RK owner worker')
        time.sleep(.002)


class ModeShell(unittest.TestCase):
    def args(self, topology, output):
        args=cli.build_parser().parse_args(['shell','--device','/dev/no-device','--expected-bdf','0000:21:00.0',
            '--config-timeout','1','--drain-timeout','1','--command-timeout','2',
            '--report-output',str(output),'--shared-camera',topology,'--poll-seconds','.001'])
        cli.validate_options(args)
        return args

    def test_original_cli_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            args=cli.build_parser().parse_args(['shell','--device','/dev/no-device','--expected-bdf','0000:21:00.0',
                '--config-timeout','1','--drain-timeout','1','--command-timeout','2','--report-output',tmp+'/r'])
            cli.validate_options(args)
            self.assertEqual((args.jpeg_version,args.shared_camera),(3,None))

    def test_mono_dual_same_owner(self):
        for topology in ('mono','dual'):
            with self.subTest(topology=topology), tempfile.TemporaryDirectory() as tmp:
                args=self.args(topology,Path(tmp)/'report')
                options=dict(shared_camera=topology)
                hdr=MonoConfiguration(product_mode=2,hdr_ratio=4,hdr_black_long=50,hdr_black_short=50,
                    hdr_motion_base=53,hdr_motion_shift=2,hdr_qualification=15,hdr_max_delta_ns=123456,
                    hdr_max_wait_ns=600000,hdr_max_age_ns=900000)
                recipe=Path(tmp)/'owner.json'
                recipe.write_text(json.dumps(dict(schema=2,extension=asdict(hdr))))
                io=SessionIO();io.bar=PhysicalBar()
                from linux.dma_c2h_candidate.receiver import Receiver
                with patch('linux.dma_c2h_candidate.receiver.Receiver',side_effect=lambda *a,**k:Receiver(_io=io,nonblocking=True)):
                    device=cli.NativeFactory().receiver(args)
                consumers=Consumers()
                run=cli.NativeFactory().session(device,args,consumers)
                try:
                    run.start()
                    self.assertEqual([(k,v) for k,v in io.bar.writes if k>=s.PCIE_REG_STEREO_MAGIC],[] if topology=='mono' else [
                        (s.PCIE_REG_STEREO_REQUEST_MODE,1),(s.PCIE_REG_STEREO_REQUEST_DIVISOR,2),
                        (s.PCIE_REG_STEREO_COMMAND,1)])
                    self.assertIs(run.cold.transactions.bar,device)
                    self.assertEqual((run.cold.selection.version,run.cold.selection.session),(4,7))
                    for eye in range(run.cameras):io.enqueue(wire(eye,0,1))
                    wait_until(lambda:len(consumers.items)==run.cameras)
                    with self.assertRaises(ValueError):
                        cli._shell_step('mode hdr dehaze',**options)
                    if topology=='dual':
                        with self.assertRaises(ValueError):cli._shell_step('mode sdr lane',**options)
                    else:
                        self.assertEqual(cli._shell_step('mode sdr lane',**options)['configuration']['extension']['processing_enables'],48)
                    command=cli._shell_step('mode hdr gray gaussian he dehaze',hdr_policy=recipe,**options)
                    before=list(io.bar.writes)
                    for invalid in (dict(product_mode=1),dict(hdr_ratio=3),dict(hdr_black_long=49),
                                    dict(hdr_max_age_ns=0),dict(hdr_max_delta_ns=1<<32),dict(dehaze_lut_generation=2)):
                        bad=dict(command['configuration'],extension=dict(command['configuration']['extension'],**invalid))
                        with self.assertRaises(RuntimeError):run.submit('configure',bad).wait(2)
                    self.assertEqual(io.bar.writes,before)
                    io.bar.allow_applied.clear()
                    request=run.submit('configure',command['configuration'])
                    wait_until(io.bar.commit_seen.is_set)
                    before=io.released_records
                    io.enqueue(wire(0,1,2,mask=15,hdr=True))
                    wait_until(lambda:io.released_records>before)
                    eye=run.cameras-1
                    io.enqueue(wire(eye,1,2 if eye else 3,mask=15,hdr=True,haze_applied=True))
                    wait_until(lambda:io.released_records==before+2)
                    io.enqueue(wire(0,1,4,mask=15,hdr=True))
                    self.assertEqual(len(consumers.items),run.cameras)
                    io.bar.allow_applied.set()
                    applied=request.wait(2)
                    self.assertEqual((applied.session,applied.mode_epoch),(7,1))
                    self.assertEqual(applied.extension.words(),MonoConfiguration(**command['configuration']['extension']).words())
                    self.assertEqual(applied.extension.words()[0],0x3e02)
                    self.assertEqual(tuple(io.bar.registers[p.PCIE_REG_CFG_EXT_ACTIVE_BASE+i*4] for i in range(32)),
                                     applied.extension.words())
                    wait_until(lambda:len(consumers.items)==run.cameras+3)
                    self.assertEqual(len(run.snapshot()['camera_mode']['seen_cameras']),run.cameras)
                    next_doc=cli._shell_step('mode sdr',**options)['configuration']
                    restored=run.submit('configure',next_doc).wait(2)
                    self.assertEqual((restored.mode_epoch, restored.extension.words()[0]),(2,2))
                    for eye in range(run.cameras):io.enqueue(wire(eye,2,5))
                    wait_until(lambda:len(consumers.items)==2*run.cameras+3)
                    self.assertEqual(run.snapshot()['camera_mode']['last_by_camera'][0]['epoch'],2)
                    if topology=='mono':
                        doc=cli._shell_step('mode sdr lane',**options)['configuration']
                        lane=run.submit('configure',doc).wait(2)
                        self.assertEqual((lane.mode_epoch,lane.extension.words()[0]),(3,0xc002))
                        io.enqueue(wire(0,3,6,mask=48))
                        wait_until(lambda:len(consumers.items)==6)
                        self.assertEqual(run.snapshot()['camera_mode']['last_by_camera'][0]['lane_points'],0)
                finally:
                    io.bar.allow_applied.set()
                    run.close()
                    if not device._closed:device.abandon()  # anonymous fake mmap only


if __name__=='__main__':unittest.main()
