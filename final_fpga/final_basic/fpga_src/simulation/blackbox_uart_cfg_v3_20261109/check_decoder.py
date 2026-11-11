"""Check the offline UART parser against hand-built public DJ/v1-v3 fixtures."""

import argparse
from binascii import crc_hqx
import importlib.util
from pathlib import Path
import struct
import sys


def finish_crc(frame):
    struct.pack_into("<H", frame, 66, crc_hqx(frame[:66], 0xFFFF))
    return bytes(frame)


def frame_header(version, packet_sequence):
    frame = bytearray(68)
    frame[:6] = bytes((0x44, 0x4A, version, 1, 68, 0))
    struct.pack_into("<HBB", frame, 6, packet_sequence, 3, 3)
    return frame


def v1_fixture():
    frame = frame_header(1, 0xAB01)
    struct.pack_into("<IIIIHH", frame, 10,
                     0x15769423, 0x82FD4071, 0x13724A09, 0x26284310, 0x112, 0x225)
    struct.pack_into("<HHHH", frame, 38, 0x1234, 0x7856, 0x0402, 0x0605)
    return finish_crc(frame)


def live_fixture(version):
    frame = frame_header(version, 0xAB00 + version)
    struct.pack_into("<IIIIHHBBBBBBBB", frame, 10,
                     0x31415927, 0x10203040, 0x1122A302, 0x13724A09,
                     0x143, 0x7A2, 11, 39, 7, 23, 1, 2, 0xE4, 0xA7)
    if version == 2:
        struct.pack_into("<HH", frame, 38, 0x1234, 0x7856)
    else:
        struct.pack_into("<I", frame, 38, 0x1122A301)
        struct.pack_into("<H", frame, 64, 0xA76B)
    struct.pack_into("<HHHHIIHI", frame, 42,
                     0x0402, 0x0605, 0x0807, 0x0A09, 0x691AA442, 0x5AC36B31,
                     0x03F3, 0x1122A302)
    return finish_crc(frame)


def expect(actual, expected, context):
    if type(actual) is not type(expected) or actual != expected:
        raise AssertionError(f"{context} expected {expected!r}, got {actual!r}")


def expect_fields(record, expected, context):
    for key, value in expected.items():
        if key not in record:
            raise AssertionError(f"{context}.{key} is missing")
        expect(record[key], value, f"{context}.{key}")


def check_decoded(record, version):
    label = f"DJ/v{version}"
    expect_fields(record, {
        "frame_type": "job", "version": version, "sequence": 0xAB00 + version,
        "fresh_mask": 3, "reset_n_mask": 3,
    }, label)
    dfi = record["dfi"]
    pixel = record["pixel"]
    if version == 1:
        expect_fields(dfi, {
            "sequence": 0x15769423, "generation": 0x82FD4071, "session": 0x13724A09,
            "epoch": 0x26284310, "jobs": [0x112, 0x225],
        }, f"{label}.dfi")
        expect_fields(pixel, {"fs": [0x1234, 0x7856], "raw_admit": [0x0402, 0x0605]},
                      f"{label}.pixel")
        return

    expect_fields(dfi, {
        "last_source": [0x31415927, 0x10203040], "epoch": 0x1122A302,
        "session": 0x13724A09, "jobs": [0x143, 0x7A2], "begin_reject": [11, 39],
        "pair_expire": [7, 23], "bad_finish": [1, 2], "bank_states": [0, 1, 2, 3],
        "flags": 0xA7, "raw": True, "hdr": True, "run": True,
    }, f"{label}.dfi")
    expect_fields(pixel, {
        "capture_admit": [0x0402, 0x0605, 0x0807, 0x0A09], "flags": 0x03F3,
        "epoch": 0x1122A302, "hdr": True, "stereo": True, "raw": False,
    }, f"{label}.pixel")
    sensors = record["sensor_sys"]
    expect(len(sensors), 2, f"{label}.sensor_sys length")
    expect_fields(sensors[0], {
        "raw": 0x691AA442, "index": 0x1A, "phase": 0xA, "clock_locked": False,
        "source_fault": False, "written": True, "stable": False, "error": False,
        "i2c_error": False,
    }, f"{label}.sensor_sys[0]")
    expect_fields(sensors[1], {
        "raw": 0x5AC36B31, "index": 0xC3, "phase": 6, "clock_locked": True,
        "source_fault": True, "written": False, "stable": True, "error": True,
        "i2c_error": True,
    }, f"{label}.sensor_sys[1]")

    if version == 2:
        expect_fields(pixel, {"fs": [0x1234, 0x7856]}, f"{label}.pixel")
    else:
        expect("fs" in pixel, False, f"{label}.pixel exposes old FS counts")
        expect_fields(pixel, {
            "cfg_applied_epoch": 0x1122A301, "cfg_flags": 0xA76B, "cfg_state": 3,
        }, f"{label}.pixel")
        expect_fields(pixel["cfg_gates"], {
            "frame_accept": True, "source_ready": True, "response_active": False,
            "response_space": True, "remote_fault": False, "remote_applied": True,
            "remote_sent": True, "remote_pending": False, "frame_apply_eligible": True,
        }, f"{label}.pixel.cfg_gates")
        expect_fields(pixel["quiet"], {
            "cfg_pipeline": False, "physical_source": True, "maintenance": False,
            "native_pipeline": True,
        }, f"{label}.pixel.quiet")


def expect_bad_direct(decode_job_frame, frame, context):
    try:
        decode_job_frame(frame)
    except ValueError:
        return
    raise AssertionError(f"{context} was accepted by decode_job_frame")


def load_parser(path):
    spec = importlib.util.spec_from_file_location("uart_observer_under_test", path)
    parser = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = parser
    spec.loader.exec_module(parser)
    return parser


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("parser_path", type=Path)
    args = cli.parse_args()
    parser = load_parser(args.parser_path)

    v1, v2, v3 = v1_fixture(), live_fixture(2), live_fixture(3)
    for version, data in enumerate((v1, v2, v3), 1):
        check_decoded(parser.decode_job_frame(data), version)
        print(f"DONE_UART_PARSER decode DJ/v{version}")

    bad_crc = bytearray(v3)
    bad_crc[42] ^= 0x80
    bad_header = bytearray(v2)
    bad_header[4] = 67
    expect_bad_direct(parser.decode_job_frame, bytes(bad_crc), "bad CRC")
    expect_bad_direct(parser.decode_job_frame, finish_crc(bad_header), "bad length header")

    stream = parser.FrameDecoder(pixel_layout="stereo")
    for fragment in (b"\x17" + v1[:1], v1[1:2], v1[2:31]):
        expect(stream.feed(fragment), [], "incomplete DJ/v1")
    [record] = stream.feed(v1[31:])
    check_decoded(record, 1)
    expect(stream.feed(bytes(bad_crc) + v2[:14]), [], "bad CRC and incomplete DJ/v2")
    expect(stream.crc_errors, 1, "stream CRC errors")
    [record] = stream.feed(v2[14:])
    check_decoded(record, 2)
    expect(stream.feed(bytes(bad_header[:6]) + v3[:1]), [], "bad header and incomplete DJ/v3")
    expect(stream.invalid_headers, 1, "stream invalid headers")
    expect(stream.feed(v3[1:2]), [], "split DJ/v3 magic")
    [record] = stream.feed(v3[2:])
    check_decoded(record, 3)
    expect(stream.feed(b""), [], "no duplicate record after reassembly")
    print("PASS_UART_PARSER versions=1,2,3 crc_errors=1 invalid_headers=1")


if __name__ == "__main__":
    main()
