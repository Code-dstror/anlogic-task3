"""Exercise the opaque UART decoder with independently packed DJ frames."""

from binascii import crc_hqx
import importlib.util
from pathlib import Path
import struct
import sys


PROJECT = Path(__file__).resolve().parents[3]
DFI_LAST = (0x41278839, 0xA2168645)
DFI_EPOCH, DFI_SESSION = 0xB3827291, 0x81960243
DFI_JOBS, REJECTS, EXPIRES, BAD = (28, 71), (0x82, 0x14), (0x35, 0x47), (0x6A, 0x9B)
PIX_FS, PIX_ADMIT = (0x12A5, 0x3406), (0x73, 0x106, 0x209, 0x41C)
PIX_EPOCH = 0x756431E8
SENSORS = (0x781D5A67, 0x96432C18)


def make_job(version, sequence):
    header = struct.pack("<2sBBHHBB", b"DJ", version, 1, 68, sequence, 3, 3)
    dfi = struct.pack("<4I2H8B", *DFI_LAST, DFI_EPOCH, DFI_SESSION, *DFI_JOBS,
                      *REJECTS, *EXPIRES, *BAD, 0b11_01_10_00, 0x55)
    sys_overlay = struct.pack("<2I", *SENSORS) if version == 2 else bytes(8)
    pix = struct.pack("<6H8sHIH", *PIX_FS, *PIX_ADMIT, sys_overlay, 0x2187, PIX_EPOCH, 0)
    frame = header + dfi + pix
    assert len(frame) == 66
    return frame + struct.pack("<H", crc_hqx(frame, 0xFFFF))


def load_dut():
    spec = importlib.util.spec_from_file_location("uart_observer_blackbox_dut", PROJECT / "tools" / "uart_observer.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def check_event(event, version):
    assert event["frame_type"] == "job" and event["version"] == version
    if version == 1:
        return  # Legacy v1 event schema differs; this vector checks mixed-stream framing.
    dfi, pix = event["dfi"], event["pixel"]
    for name, expected in (("last_source", DFI_LAST), ("jobs", DFI_JOBS), ("begin_reject", REJECTS),
                           ("pair_expire", EXPIRES), ("bad_finish", BAD)):
        assert tuple(dfi[name]) == expected, (name, dfi[name], expected)
    assert dfi["epoch"] == DFI_EPOCH and dfi["session"] == DFI_SESSION
    assert dfi["raw"] and not dfi["hdr"] and dfi["run"]
    assert tuple(pix["fs"]) == PIX_FS and tuple(pix["capture_admit"]) == PIX_ADMIT
    assert pix["epoch"] == PIX_EPOCH and pix["hdr"] and pix["stereo"] and pix["raw"]
    for i, (sensor, bits) in enumerate(zip(event["sensor_sys"], SENSORS, strict=True)):
        expected = {"index": (bits >> 16) & 0xFF, "phase": (bits >> 12) & 0xF}
        for name, bit in (("clock_locked", 11), ("source_fault", 9), ("written", 6),
                          ("stable", 5), ("error", 4), ("i2c_error", 0)):
            expected[name] = bool(bits & (1 << bit))
        for name, wanted in expected.items():
            assert sensor[name] == wanted, (i, name, sensor[name], wanted)


def main():
    module = load_dut()
    v1, v2 = make_job(1, 0x193B), make_job(2, 0x193C)
    check_event(module.decode_job_frame(v2), 2)
    assert b"DJ" not in v1[2:] and b"DJ" not in v2[2:]
    bad_header = v2[:4] + b"\x43" + v2[5:]
    bad_crc = v2[:35] + bytes((v2[35] ^ 1,)) + v2[36:]
    stream = b"\xa3D\x90O\xc1\xff" + v1 + b"\xe2\xfa" + bad_header + bad_crc + v2[:23] + v2
    decoder = module.FrameDecoder(pixel_layout="stereo")
    events = [event for byte in stream for event in decoder.feed(bytes((byte,)))]
    assert len(events) == 2, [(event.get("frame_type"), event.get("version")) for event in events]
    for event, version in zip(events, (1, 2), strict=True):
        check_event(event, version)
    assert decoder.crc_errors == 2 and decoder.invalid_headers == 1
    assert decoder.discarded_bytes > 0
    summary = decoder.summary()
    assert summary["job_crc_errors"] == 2 and summary["job_invalid_headers"] == 1
    print(f"PASS_FIELD_DECODER frames={len(events)} crc_errors={decoder.crc_errors} "
          f"invalid_headers={decoder.invalid_headers} discarded_bytes={decoder.discarded_bytes}")


if __name__ == "__main__":
    main()
