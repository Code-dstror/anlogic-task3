"""Short native ModelSim wire/CDC regression. All outputs stay in project tmp."""
import argparse
import binascii
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    here = Path(__file__).resolve().parent
    project = here.parents[2]
    run = project / "tmp/rx_trace_uart" / args.name
    run.mkdir(parents=True, exist_ok=False)
    sources = [project / "src_fpga/rtl" / name for name in (
        "reset_release_sync.v", "uart_observer_snapshot.v", "cfg_diag_snapshot.v",
        "rx_first_loss_trace.v", "uart_status_observer.v")]
    bench = here / "uart_rx_trace_tb.sv"
    decoder_path = project / "tools/uart_observer.py"
    inputs = sources + [bench, decoder_path, Path(__file__)]
    identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    result = {"status": "IN_PROGRESS", "inputs": identities, "commands": [],
              "synthesis": "NOT_RUN", "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN"}

    def invoke(executable, words, label):
        argv = [str(args.modelsim_bin / executable)] + list(map(str, words))
        proc = subprocess.run(argv, cwd=run, timeout=60, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        (run / (label + ".console.log")).write_text(proc.stdout, encoding="utf-8")
        result["commands"].append({"argv": argv, "exit_code": proc.returncode})
        if proc.returncode:
            raise RuntimeError(proc.stdout[-10000:])

    def packets(raw):
        found = []
        at = 0
        while at < len(raw):
            magic = raw[at:at + 2]
            length = {b"OB": 29, b"CG": 68, b"RX": 64, b"RT": 64}[magic]
            packet = raw[at:at + length]
            if len(packet) != length:
                raise AssertionError("truncated actual wire frame")
            if magic != b"OB":
                assert int.from_bytes(packet[-2:], "little") == binascii.crc_hqx(packet[:-2], 65535)
            found.append(packet)
            at += length
        return found

    try:
        invoke("vmap.exe", ["-c"], "vmap_create")
        invoke("vlib.exe", ["work"], "vlib")
        invoke("vmap.exe", ["work", "work"], "vmap")
        invoke("vlog.exe", ["-quiet", "-l", "rtl.log", *sources], "rtl")
        invoke("vlog.exe", ["-quiet", "-sv", "-l", "bench.log", bench], "bench")
        spec = importlib.util.spec_from_file_location("trace_offline", decoder_path)
        observer = importlib.util.module_from_spec(spec); spec.loader.exec_module(observer)
        decoded_cases, wire_cases = {}, {}
        for enabled, real_leaf in [(0, 0), (1, 0), (1, 1)]:
            label = f"trace{enabled}_leaf{real_leaf}"
            invoke("vsim.exe", ["-c", "work.uart_rx_trace_tb", f"-gTRACE_ENABLED={enabled}",
                                f"-gREAL_LEAF={real_leaf}", "-l", label + ".log",
                                "-do", "onerror {quit -code 1}; run -all; quit -f"], label)
            body = (run / (label + ".log")).read_text()
            if "RESULT: PASS uart_rx_trace" not in body:
                raise RuntimeError(body[-10000:])
            raw = (run / ("uart_" + label + ".bin")).read_bytes()
            wire_cases[label] = packets(raw)
            decoder, view = observer.FrameDecoder(), observer.ProgressView()
            decoded = [view.annotate(frame) for frame in decoder.feed(raw)]
            assert len(decoded) == 50 * (4 if enabled else 3)
            assert decoder.discarded_bytes == decoder.crc_errors == decoder.invalid_headers == 0
            assert not decoder.buffer
            if enabled:
                trace = [f for f in decoded if f.get("frame_type") == "trace"]
                assert not trace[0]["fresh"]
                assert trace[1]["fresh"] and trace[1]["sample_index"] == 63
                assert view.trace_assembler.completed and view.trace_assembler.completed[0]["complete"]
                capture = view.trace_assembler.completed[0]
                assert capture["generation"] == (1 if real_leaf else 2)
                assert capture["valid_pre_count"] == 32
                if real_leaf:
                    assert [s["sample"]["raw_word"] for s in capture["samples"]] == list(range(18, 58))
                    assert capture["samples"][32]["sample"]["trigger"]
                (run / (label + ".assembly.json")).write_text(
                    json.dumps(view.trace_assembler.snapshot(), indent=2) + "\n")
            decoded_cases[label] = decoder.summary()
            for log in ("rtl.log", "bench.log", label + ".log"):
                if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / log).read_text()):
                    raise RuntimeError("unclassified diagnostic in " + log)
        legacy = wire_cases["trace0_leaf0"]
        for label in ("trace1_leaf0", "trace1_leaf1"):
            assert [p for p in wire_cases[label] if not p.startswith(b"RT")] == legacy, "legacy frame bytes changed"
        assert identities == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}, "source changed during run"
        result.update(status="PASS", offline_decoder=decoded_cases,
                      legacy_frames_byte_identical=150, complete_trace_samples=40,
                      actual_leaf_word_stop_and_late_ack="PASS")
        print("PASS UART trace: 3 wire cases; 150 legacy frames byte-identical; 40-sample actual-leaf capture")
    except Exception as error:
        result.update(status="FAIL", error=str(error))
        raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print(run / "RESULTS.json")


if __name__ == "__main__":
    main()
