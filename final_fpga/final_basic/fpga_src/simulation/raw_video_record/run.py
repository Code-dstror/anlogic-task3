"""Check the ARAW formatter and RK decoder from an immutable source snapshot."""

import argparse
import hashlib
import json
from pathlib import Path
import re
from struct import pack
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
FIXTURES = {
    1: (1, 4, 1), 2: (15, 4, 3), 3: (16, 8, 2),
    4: (17, 8, 2), 5: (65, 4, 13), 6: (80, 16, 4),
}
RTL = Path("src_fpga/rtl")
INC = RTL / "include/00_rtl"
TB = (HERE / "tb_raw_video_record.sv").relative_to(PROJECT)
SOURCES = (
    RTL / "raw_video_record_formatter.v", INC / "raw_video_v1.vh", TB,
    HERE.relative_to(PROJECT) / "run.py", Path("docs/raw_video_v1.json"),
    Path("rk_sdk/raw_video.py"), Path("rk_sdk/raw_video_constants.py"),
    Path("rk_sdk/linux/__init__.py"), Path("rk_sdk/linux/task3_pipeline/__init__.py"),
    Path("rk_sdk/linux/task3_pipeline/raw_frame_store.py"),
    Path("rk_sdk/linux/task3_pipeline/pcie_protocol_v1.py"),
)


def expected_fields(schema, tag, length, width, height):
    return dict(magic=schema["magic"], version=schema["version"], header_bytes=schema["header_bytes"],
                payload_bytes=length, width=width, height=height, source_sequence=0x91A20000 | tag,
                source_session=0x78563412, mode_epoch=0xFEDC0000 | tag, camera=tag & 1,
                format=schema["format_raw10"], bayer_phase=(tag - 1) % 4,
                flags=schema["flag_timestamp_valid"] if tag & 2 else 0,
                capture_time_ns=0x8877665544332200 | tag, job_id=0x80000000DCEB0000 | tag,
                reserved=0)


def header_bytes(schema, values):
    head = bytearray(schema["header_bytes"])
    for field in schema["fields"]:
        offset, size = field["offset"], field["bytes"]
        head[offset:offset + size] = values[field["name"]].to_bytes(size, schema["byte_order"])
    return head


def verify_records(path, schema, parse, raw_error):
    beats = {tag: [] for tag in FIXTURES}
    for line in path.read_text(encoding="ascii").splitlines():
        tag, word, keep, last = line.split()
        mask = int(keep, 16)
        if not mask or mask & (mask + 1):
            raise ValueError(f"non-contiguous KEEP in trace: {line}")
        beats[int(tag)].append((int(word, 16).to_bytes(16, "little")[:mask.bit_count()], last == "1"))

    def reject(data, label):
        try:
            parse(data)
        except raw_error:
            return
        raise ValueError(f"RK parser accepted {label}")

    samples_checked = 0
    for tag, (length, width, height) in FIXTURES.items():
        values = expected_fields(schema, tag, length, width, height)
        payload = bytearray()
        for index in range((length + 15) // 16):
            word = (tag << 20) ^ index
            payload.extend(pack("<IIII", word, word ^ 0x89ABCDEF, word + 0x13579BDF, word ^ 0xFFFFFFFF))
        del payload[length:]
        expected = header_bytes(schema, values) + payload
        actual = bytearray().join(chunk for chunk, _ in beats[tag])
        if actual != expected or [last for _, last in beats[tag]] != [False] * (len(beats[tag]) - 1) + [True]:
            raise ValueError(f"record {tag} differs from the byte oracle")
        if length != width // 4 * height * 5:
            reject(actual, f"synthetic fixture {tag} with wrong RAW10 geometry")
            continue
        frame = parse(actual)
        fields = (frame.width, frame.height, frame.source_sequence, frame.source_session,
                  frame.mode_epoch, frame.camera, frame.bayer_phase, frame.capture_time_ns, frame.job_id)
        expected_fields_tuple = (width, height, values["source_sequence"], values["source_session"],
                                 values["mode_epoch"], values["camera"], values["bayer_phase"],
                                 values["capture_time_ns"] if values["flags"] else None, values["job_id"])
        if fields != expected_fields_tuple or frame.payload != payload:
            raise ValueError(f"RK decoded incorrect metadata or payload for record {tag}")
        if not frame.payload.readonly or frame.payload.obj is not actual:
            raise ValueError("RK copied the payload or exposed a writable DMA view")
        # Use a bit-addressed reference independent of the SDK's unpacker.
        number = int.from_bytes(payload, "little")
        reference = [(number >> (10 * i)) & 1023 for i in range(width * height)]
        if frame.unpack_samples() != reference:
            raise ValueError(f"RK reconstructed incorrect RAW10 samples for record {tag}")
        samples_checked += len(reference)

    fixture = bytearray().join(chunk for chunk, _ in beats[6])
    fixture_length, cols, rows = FIXTURES[6]
    base_fields = expected_fields(schema, 6, fixture_length, cols, rows)
    bad_fields = dict(magic=0, version=2, header_bytes=48, payload_bytes=0, width=15,
                      height=0, source_session=0, camera=2, format=2, bayer_phase=4,
                      flags=0x81, job_id=0, reserved=1)
    for name, bad_value in bad_fields.items():
        invalid_header = header_bytes(schema, base_fields | {name: bad_value})
        reject(invalid_header + fixture[schema["header_bytes"]:], name)
    reject(fixture[:63], "short header")
    reject(fixture[:-1], "short payload")
    reject(fixture + b"\x00", "extra byte")
    reject(memoryview(fixture)[::2], "strided buffer")

    # Verify the capacity guard independently of length and geometry checks.
    length = 252 // 4 * 53261 * 5
    maximum = bytearray(schema["header_bytes"] + length)
    maximum[:schema["header_bytes"]] = header_bytes(schema, expected_fields(schema, 6, length, 252, 53261))
    if parse(maximum).payload.nbytes != schema["payload_max_bytes"] - 1:
        raise ValueError("largest legal multiple-of-five payload did not parse")
    del maximum
    length = 65532 // 4 * 205 * 5
    oversize = bytearray(schema["header_bytes"] + length)
    oversize[:schema["header_bytes"]] = header_bytes(schema, expected_fields(schema, 6, length, 65532, 205))
    reject(oversize, "internally consistent oversized record")
    return dict(byte_records=len(FIXTURES), raw10_samples=samples_checked,
                malformed_records=len(bad_fields) + 8, max_legal_payload_bytes=schema["payload_max_bytes"] - 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--modelsim-bin", type=Path, required=True)
    ap.add_argument("--name", required=True)
    args = ap.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        ap.error("name must be a lowercase run identifier")
    ms = args.modelsim_bin.resolve()
    for name in ("vlib", "vlog", "vsim"):
        if not (ms / f"{name}.exe").is_file():
            ap.error(f"missing {ms / (name + '.exe')}")

    run = PROJECT / "tmp/raw_video_record" / args.name
    snapshot = run / "inputs"
    snapshot.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    result = dict(status="IN_PROGRESS", scope="RAW_FORMATTER_AND_RK_BYTE_ORACLE", inputs=[], commands=[],
                  runner_argv=[sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
                  synthesis="NOT_RUN", place_route="NOT_RUN", timing="NOT_RUN", board="NOT_RUN")

    def command(label, exe, args, timeout=20):
        argv = [str(ms / f"{exe}.exe"), *map(str, args)]
        log = run / f"{label}.log"
        record = dict(argv=argv, timeout_seconds=timeout, log=log.name)
        result["commands"].append(record)
        with log.open("wb") as output:
            completed = subprocess.run(argv, cwd=run, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        record["returncode"] = completed.returncode
        text = log.read_text(encoding="utf-8", errors="replace")
        if completed.returncode or re.search(r"\*\* (Error|Fatal|Warning)\b", text):
            raise RuntimeError(f"{label} failed\n{text[-5000:]}")
        return text

    try:
        for source in SOURCES:
            data = (PROJECT / source).read_bytes()
            target = snapshot / source
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            result["inputs"].append(dict(path=source.as_posix(), sha256=hashlib.sha256(data).hexdigest()))
        result["modelsim_version"] = command("version", "vsim", ["-version"]).strip()
        command("library", "vlib", ["work"])
        command("compile", "vlog", ["-work", "work", "-sv", f"+incdir+{snapshot / INC}",
                                     snapshot / RTL / "raw_video_record_formatter.v", snapshot / TB])
        simulation = command("simulation", "vsim", ["-c", "work.tb_raw_video_record", "-do",
                                                    "run -all; quit -f"], timeout=60)
        if "RESULT: PASS raw_video_record" not in simulation:
            raise RuntimeError(f"incomplete simulator run\n{simulation[-5000:]}")
        result["cases"] = [line.strip("# ") for line in simulation.splitlines() if "CASE:" in line]

        sys.path.insert(0, str(snapshot / "rk_sdk"))
        from raw_video import RawVideoError, parse_raw_video
        schema = json.loads((snapshot / "docs/raw_video_v1.json").read_text(encoding="utf-8"))
        result["byte_oracle"] = verify_records(run / "records.hex", schema, parse_raw_video, RawVideoError)
        for item in result["inputs"]:
            if hashlib.sha256((PROJECT / item["path"]).read_bytes()).hexdigest() != item["sha256"]:
                raise RuntimeError(f"input changed during run: {item['path']}")
        result.update(status="PASS", input_hash_recheck="PASS")
        print("\n".join(result["cases"]))
        print(json.dumps(result["byte_oracle"]))
    except Exception as error:
        result.update(status="FAIL", error=str(error))
        raise
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
        (run / "qualification.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(f"{result['status']} {run.as_posix()} ({result['elapsed_seconds']} s)")


if __name__ == "__main__":
    main()
