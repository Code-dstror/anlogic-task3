"""Validate raw 8N1 output and independently exercise the public UART decoder."""

import argparse
import binascii
import struct
import sys
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[3]
OB_BYTES = 29
DJ_BYTES = 76
ROUND_BYTES = OB_BYTES + DJ_BYTES
ROUNDS = 5
SENSOR_INITIAL = (0x24682D70, 0x13570BE4)
SENSOR_UPDATED = (0x36A238E0, 0x5C682C20)


def dfi_page(last_source, epoch, session, jobs, rejects, expires, finishes, flags):
    return struct.pack("<4I2H8B", *last_source, epoch, session, *jobs,
                       *rejects, *expires, *finishes, 0xE4, flags)


def pixel_page(applied, admits, sensor, flags, target, cfg):
    return struct.pack("<I4H2IHIH", applied, *admits, *sensor, flags, target, cfg)


def crc16(data):
    return binascii.crc_hqx(data, 0xFFFF)


def crc8(data):
    checksum = 0
    for octet in data:
        checksum ^= octet
        for _ in range(8):
            checksum = ((checksum << 1) ^ (0x07 if checksum & 0x80 else 0)) & 0xFF
    return checksum


DFI_INITIAL = dfi_page((0x1230AC61, 0xC090350D), 0x10203040, 0x302EF001,
                       (1, 2), (1, 2), (1, 2), (1, 1), 0xC6)
DFI_WRAPPED = dfi_page((0x1230AC61, 0xC090350D), 0x10203040, 0x302EF001,
                       (1, 2), (0, 2), (1, 2), (1, 1), 0xC6)
DFI_STOPPED = DFI_WRAPPED[:-1] + b"\xc2"
DFI_NEW_RUN = dfi_page((0, 0), 0x10203041, 0x302EF002, (1, 0), (0, 1), (0, 0), (1, 0), 0xC6)
PIXEL_INITIAL = pixel_page(0x11223343, (2, 2, 1, 1), SENSOR_INITIAL, 0x30F3, 0x11223344, 0xA6CA)
PIXEL_RESUMED = pixel_page(0x11223344, (3, 3, 2, 2), SENSOR_INITIAL, 0x30F3, 0x11223345, 0xF12A)
PIXEL_STOPPED = pixel_page(0x11223344, (3, 3, 2, 2), SENSOR_UPDATED, 0x30F3, 0x11223345, 0xF12A)
PIXEL_NEW_RUN = pixel_page(0x11223344, (0, 0, 1, 0), SENSOR_UPDATED, 0x30F3, 0x11223345, 0xF12A)


def validate_wire(data):
    assert len(data) == ROUNDS * ROUND_BYTES, f"serial capture had {len(data)} octets"
    expected = (
        (DFI_INITIAL, PIXEL_INITIAL, (4, 2)),
        (DFI_WRAPPED, None, None),
        (DFI_STOPPED, PIXEL_RESUMED, (5, 4)),
        (DFI_STOPPED, PIXEL_STOPPED, (5, 4)),
        (DFI_NEW_RUN, PIXEL_NEW_RUN, (0, 1)),
    )
    previous_sequence = None
    for index, (dfi_expected, pixel_expected, fs_expected) in enumerate(expected):
        start = index * ROUND_BYTES
        ob = data[start:start + OB_BYTES]
        dj = data[start + OB_BYTES:start + ROUND_BYTES]
        assert ob[:4] == b"OB\x02\x1d", (index, ob[:4].hex())
        assert dj[:6] == b"DJ\x04\x01\x4c\x00", (index, dj[:6].hex())
        sequence = int.from_bytes(dj[6:8], "little")
        assert int.from_bytes(ob[4:6], "little") == sequence, (index, "OB/DJ round mismatch")
        if previous_sequence is not None:
            assert sequence == (previous_sequence + 1) & 0xFFFF, (index, previous_sequence, sequence)
        previous_sequence = sequence
        assert ob[6] <= 7 and ob[7] <= 7 and ob[8:10] == b"\x6b\x5a", (index, "OB masks or SYS flags")
        assert crc8(ob[:-1]) == ob[-1], (index, "OB CRC8")
        assert crc16(dj[:-2]) == int.from_bytes(dj[-2:], "little"), (index, "DJ CRC16")
        assert dj[8] <= 3 and dj[9] <= 3 and (dj[8] & dj[9] & 1), (index, "DFI page invalid")
        assert dj[70:74] == bytes(4), (index, "DJ reserved bytes")
        assert dj[10:38] == dfi_expected, (index, "DFI page", dj[10:38].hex(), dfi_expected.hex())
        if pixel_expected is None:
            assert not (dj[8] & 2) and not (ob[6] & 1), (index, "stopped PIX advertised fresh")
        else:
            assert dj[8] & dj[9] & 2, (index, "PIX page invalid")
            assert dj[38:66] == pixel_expected, (index, "PIX page", dj[38:66].hex(), pixel_expected.hex())
            assert struct.unpack("<2H", dj[66:70]) == fs_expected, (index, "FS counts", dj[66:70].hex())
        print(f"wire round={index + 1} sequence={sequence} fresh={dj[8]:#04x} resets={dj[9]:#04x}")


def synthetic_job(version, sequence):
    length = 76 if version == 4 else 68
    header = b"DJ" + struct.pack("<BBHHBB", version, 1, length, sequence, 3, 3)
    pixel = PIXEL_INITIAL
    trailer = b""
    if version == 2:
        pixel = struct.pack("<2H", 4, 2) + pixel[4:-2] + bytes(2)
    elif version == 4:
        trailer = struct.pack("<2H", 4, 2) + bytes(4)
    body = header + DFI_INITIAL + pixel + trailer
    return body + struct.pack("<H", crc16(body))


def validate_decoder(ob_wire):
    sys.path.insert(0, str(PROJECT / "tools"))
    from uart_observer import FrameDecoder, decode_job_frame

    old = synthetic_job(2, 0x428E)
    previous = synthetic_job(3, 0x428F)
    current = synthetic_job(4, 0x4291)
    corrupt = bytearray(synthetic_job(4, 0x4290))
    corrupt[53] ^= 0x20
    try:
        decode_job_frame(bytes(corrupt))
    except ValueError:
        pass
    else:
        raise AssertionError("decode_job_frame accepted altered CRC payload")

    # One-byte reads split every magic, length, sequence and CRC field.
    decoder = FrameDecoder(pixel_layout="stereo")
    frames = []
    for byte in b"\x9fD\x00" + old + ob_wire + bytes(corrupt) + previous + current:
        frames.extend(decoder.feed(bytes([byte])))
    jobs = [frame for frame in frames if frame.get("frame_type") == "job"]
    assert len(frames) == 4 and len(jobs) == 3, [frame.get("frame_type") for frame in frames]
    assert [(frame["version"], frame["sequence"]) for frame in jobs] == [(2, 0x428E), (3, 0x428F), (4, 0x4291)]
    for frame in jobs:
        assert frame["fresh_mask"] == frame["reset_n_mask"] == 3
        assert frame["dfi"]["last_source"] == [0x1230AC61, 0xC090350D]
        assert frame["dfi"]["jobs"] == [1, 2] and frame["dfi"]["bad_finish"] == [1, 1]
        assert frame["pixel"]["epoch"] == 0x11223344 and frame["pixel"]["capture_admit"] == [2, 2, 1, 1]
    assert jobs[0]["pixel"]["fs"] == jobs[2]["pixel"]["fs"] == [4, 2]
    assert "fs" not in jobs[1]["pixel"]
    for frame in jobs[1:]:
        assert frame["pixel"]["cfg_applied_epoch"] == 0x11223343
        assert frame["pixel"]["cfg_flags"] == 0xA6CA
    summary = decoder.summary()
    assert summary["job_frames"] == 3 and summary["job_crc_errors"] == 1, summary
    assert summary["trailing_bytes"] == 0, summary
    print("decode mixed=OB/v2,DJ/v2,DJ/v3,DJ/v4 fragmented=1B bad_dj_crc=1 recovered=2")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    args = parser.parse_args()
    data = args.capture.read_bytes()
    validate_wire(data)
    validate_decoder(data[:OB_BYTES])
    print(f"FUSION_UART_PASS rounds={ROUNDS} octets={len(data)}")


if __name__ == "__main__":
    main()
