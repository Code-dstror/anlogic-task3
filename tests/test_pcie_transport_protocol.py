"""Check compatibility of the frozen capture ABI and dependency-free CLI."""
import json
from pathlib import Path
import subprocess
import sys
import unittest
from linux.pcie_transport import pcie_protocol_v1 as capture
from linux.task3_pipeline import pcie_protocol_v1 as pipeline

class CaptureProtocolTests(unittest.TestCase):
 def test_wire_header_compatible_with_existing_pipeline(self):
  for name in ['FRAME_HEADER_FORMAT','FRAME_HEADER_FIELD_NAMES','FRAME_HEADER_FIELD_OFFSETS','FRAME_HEADER_FIELD_SIZES','FRAME_HEADER_EXPECTED_VALUES','FRAME_HEADER_SIZE','FRAME_MAGIC','PROTOCOL_VERSION','MAX_PAYLOAD']:
   self.assertEqual(getattr(capture,name),getattr(pipeline,name),name)
 def test_cli_help_without_site_packages_or_device_access(self):
  root=Path(__file__).resolve().parents[1]
  result=subprocess.run([sys.executable,'-S','-m','linux.pcie_transport.capture_v1_record','--help'],cwd=root,capture_output=True,text=True,timeout=10)
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('--c2h-device',result.stdout)
