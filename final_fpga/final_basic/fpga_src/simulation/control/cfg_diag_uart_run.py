"""Source-bound mixed OB/CG wire, coherent CDC and offline parser check. No serial access."""
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def crc16(data):
    value = 0xFFFF
    for byte in data:
        value ^= byte << 8
        for _ in range(8):
            value = ((value << 1) ^ (0x1021 if value & 0x8000 else 0)) & 0xFFFF
    return value


def packets(raw):
    """Independent framing reference: noise and bad packets consume one byte."""
    accepted = []
    at = 0
    while at + 2 <= len(raw):
        if raw[at:at + 2] == b"OB":
            length = 29
            header = b"OB\x02\x1d"
            valid = lambda data: data[-1] == crc8(data[:-1])
        elif raw[at:at + 2] == b"CG":
            length = 68
            header = b"CG" + raw[at + 2:at + 3] + b"\x01\x44\x00"
            valid = lambda data: int.from_bytes(data[-2:], "little") == crc16(data[:-2])
            if raw[at + 2:at + 3] not in (b"\x01", b"\x02"):
                at += 1
                continue
        else:
            at += 1
            continue
        data = raw[at:at + length]
        if len(data) == length and data.startswith(header) and valid(data):
            accepted.append(data)
            at += length
        else:
            at += 1
    return accepted


def crc8(data):
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = ((value << 1) ^ (7 if value & 128 else 0)) & 255
    return value


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name", required=True)
    ap.add_argument("--modelsim-bin", type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        ap.error("unsafe run name")
    run = ROOT / "tmp/cfg_diag" / args.name
    run.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "src_fpga/rtl" / name for name in (
        "reset_release_sync.v", "uart_observer_snapshot.v", "cfg_diag_snapshot.v", "uart_status_observer.v")]
    bench = HERE / "cfg_diag_uart_tb.sv"
    main_bench = HERE / "cfg_diag_main_receiver_tb.sv"
    main_receiver = ROOT / "src_fpga/simulation/assets/readonly_uart_main_decode.vh"
    decoder_path = ROOT / "tools/uart_observer.py"
    inputs = sources + [bench, main_bench, main_receiver, decoder_path, Path(__file__)]
    identity = [{"path": str(p), "sha256": sha(p)} for p in inputs]
    result = {"status": "IN_PROGRESS", "inputs": identity, "modelsim_bin": str(args.modelsim_bin),
              "synthesis": "NOT_RUN", "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN",
              "real_serial_access": "NOT_RUN"}

    def execute(exe, words):
        command = [str(args.modelsim_bin / exe)] + list(map(str, words))
        proc = subprocess.run(command, cwd=run, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if proc.returncode:
            raise RuntimeError(proc.stdout[-12000:])

    try:
        execute("vmap.exe", ["-c"])
        execute("vlib.exe", ["work"])
        execute("vmap.exe", ["work", "work"])
        execute("vlog.exe", ["-quiet", "-l", "rtl.log"] + sources)
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log", bench])
        body = ""
        raw = b""
        for version in (1, 2):
            log = "run_v" + str(version) + ".log"
            execute("vsim.exe", ["-c", "work.cfg_diag_uart_tb", "-gCFG_TEST_VERSION=" + str(version),
                                  "-l", log, "-do", "onerror {quit -code 1}; run -all; quit -f"])
            version_body = (run / log).read_text()
            if "RESULT: PASS cfg_diag_uart" not in version_body:
                raise RuntimeError(version_body[-12000:])
            body += version_body
            capture = run / ("cfg_diag_wire_v" + str(version) + ".bin")
            (run / "cfg_diag_wire.bin").rename(capture)
            version_raw = capture.read_bytes()
            version_frames = packets(version_raw)
            if any(p[2] != version for p in version_frames if p.startswith(b"CG")):
                raise RuntimeError("wrong actual wire version")
            cause_masks = {(int.from_bytes(p[58:62], "little") >> 26) & 31
                           for p in version_frames if p.startswith(b"CG") and p[8] & 2}
            if not {0, 1, 2, 4, 8, 16, 31}.issubset(cause_masks):
                raise RuntimeError("missing directed wire cause masks")
            raw += version_raw
        (run / "cfg_diag_wire.bin").write_bytes(raw)
        for name in ("rtl.log", "bench.log", "run_v1.log", "run_v2.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError("unclassified diagnostic in " + name)
        execute("vlog.exe", ["-quiet", "-sv", "-l", "main_bench.log",
                              "+incdir+" + str(main_receiver.parent), main_bench])
        main_body = ""
        for version in (1, 2):
            log = "main_receiver_v" + str(version) + ".log"
            execute("vsim.exe", ["-c", "work.cfg_diag_main_receiver_tb", "-gCFG_TEST_VERSION=" + str(version),
                                  "-l", log, "-do", "onerror {quit -code 1}; run -all; quit -f"])
            version_body = (run / log).read_text()
            if "RESULT: PASS cfg_diag_main_receiver" not in version_body:
                raise RuntimeError(version_body[-12000:])
            main_body += version_body
            (run / "uart_frames.hex").rename(run / ("main_uart_frames_v" + str(version) + ".hex"))
        for name in ("main_bench.log", "main_receiver_v1.log", "main_receiver_v2.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError("unclassified diagnostic in " + name)
        frames = packets(raw)
        if b"".join(frames) != raw or not any(p.startswith(b"CG") for p in frames):
            raise RuntimeError("independent wire parser did not consume exact mixed stream")
        damaged = bytearray(next(p for p in frames if p.startswith(b"CG")))
        damaged[27] ^= 128
        samples = frames[-2:]
        damaged_stream = b"noiseOBC" + bytes(damaged) + b"CG\xff\x01\x44\x00" + b"".join(samples)
        if packets(damaged_stream) != samples:
            raise RuntimeError("independent bad-frame resynchronization failed")
        # Run the connected production decoder as a second implementation.
        module_spec = importlib.util.spec_from_file_location("cfg_diag_decoder", decoder_path)
        decoder_module = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(decoder_module)
        decoder = decoder_module.FrameDecoder()
        decoded = decoder.feed(raw)
        if len(decoded) != len(frames):
            raise RuntimeError("production decoder lost mixed frames")
        for packet, item in zip(frames, decoded):
            if packet.startswith(b"CG"):
                pixel = item["domains"]["pixel"]
                available = packet[2] == 2
                if item["version"] != packet[2] or pixel["cause_bits_available"] != available:
                    raise RuntimeError("version-dependent cause availability")
                expected = {label: bool(packet[61] & (1 << (bit - 24))) if available else None
                            for bit, label in decoder_module.CFG_PIXEL_CAUSE_NAMES.items()}
                if pixel["cause_values"] != expected or (not available and pixel["cause_state"] != "UNKNOWN"):
                    raise RuntimeError("production decoder cause bits differ from wire")
        for split in range(len(damaged_stream) + 1):
            decoder = decoder_module.FrameDecoder()
            recovered = decoder.feed(damaged_stream[:split]) + decoder.feed(damaged_stream[split:])
            if len(recovered) != 2:
                raise RuntimeError("production decoder resync/split " + str(split))
        decoder = decoder_module.FrameDecoder()
        bytewise = [item for byte in raw for item in decoder.feed(bytes((byte,)))]
        if len(bytewise) != len(frames):
            raise RuntimeError("production decoder bytewise mixed stream")
        (run / "decoded_frames.json").write_text(json.dumps(decoded, indent=2) + "\n")
        for row in identity:
            if sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("input changed during run: " + row["path"])
        result.update(status="PASS", metrics=[s.strip("# ") for s in (body + main_body).splitlines() if "RESULT: PASS" in s or "UART_READONLY_MAIN PASS" in s],
                      wire_capture_sha256=sha(run / "cfg_diag_wire.bin"), mixed_packets=len(frames),
                      resync_split_cases=len(damaged_stream) + 1, bytewise_packets=len(bytewise))
        print("\n".join(result["metrics"]))
    except Exception as error:
        result.update(status="FAIL", error=str(error))
        raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print(run / "RESULTS.json")


if __name__ == "__main__":
    main()
