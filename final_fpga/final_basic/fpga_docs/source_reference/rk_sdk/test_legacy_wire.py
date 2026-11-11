"""Offline schema2 wire compatibility with the pre-refactor 06a122ee70 RK release."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest

SDK = Path(__file__).resolve().parent
REPO = SDK.parents[2]
PACKAGE = REPO/"deliverables/DUAL_HDR_06a122ee70_seed1_RK_Debug_20261101"


def serialized_profiles(sdk):
    # Runs in a separate isolated interpreter for each SDK. Calling words()
    # compares wire encoding even for modes that the old policy would refuse.
    sys.path.insert(0,str(sdk))
    from linux.task3_pipeline.mono_config_v2 import MonoConfiguration
    from linux.task3_pipeline import pcie_protocol_v1 as p
    assert Path(p.__file__).resolve().is_relative_to(sdk)
    policies={}
    for hdr in (False,True):
        for mask in range(64):
            if mask & 32 and not mask & 16:
                continue
            params=dict(product_mode=2 if hdr else 0, processing_enables=mask)
            if hdr:
                params.update(hdr_ratio=4,hdr_black_long=50,hdr_black_short=50,hdr_motion_base=0x241,
                              hdr_motion_shift=7,hdr_qualification=15,hdr_max_delta_ns=0x10203,
                              hdr_max_wait_ns=0x80010203,hdr_max_age_ns=0xff123456)
            for generation in ((0,1) if mask & 2 else (0,)):
                frame=MonoConfiguration(**params,dehaze_lut_generation=generation)
                words=frame.words()
                if MonoConfiguration.from_words(words)!=frame:
                    raise ValueError("32-word schema2 round trip changed a field")
                policies[f"{hdr}/{mask}/{generation}"]=struct.pack("<32I",*words).hex()
    return policies


class LegacyWireTest(unittest.TestCase):
    def test_control_image(self):
        binding=json.loads((PACKAGE/"runtime/SOURCE_BINDING.json").read_bytes())
        for row in binding:
            self.assertTrue(row["source"].startswith("git:06a122ee7060d56c5a4f783112cb727209c54ed5:"))
            self.assertEqual(hashlib.sha256((PACKAGE/row["path"]).read_bytes()).hexdigest(),row["sha256"])
        def get(sdk):
            text=subprocess.check_output([sys.executable,"-I","-B",__file__,"--emit",str(sdk)],timeout=10)
            return json.loads(text)
        archived,current=get(PACKAGE/"runtime"),get(SDK)
        self.assertEqual(len(archived),144)
        self.assertEqual(archived,current)


if __name__=="__main__":
    if len(sys.argv)==3 and sys.argv[1]=="--emit":
        print(json.dumps(serialized_profiles(Path(sys.argv[2]).resolve())))
    else:
        unittest.main()
