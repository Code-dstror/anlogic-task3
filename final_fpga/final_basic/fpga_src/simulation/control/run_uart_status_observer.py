"""UART wire/CDC self-check plus offline PC decoding; never opens a real port."""
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    run = PROJECT / "tmp/uart_observer" / args.name
    run.mkdir(parents=True, exist_ok=False)
    sources = [PROJECT / "src_fpga/rtl" / name for name in
               ("reset_release_sync.v", "uart_observer_snapshot.v", "cfg_diag_snapshot.v", "uart_status_observer.v")]
    bench = HERE / "tb_uart_status_observer.sv"
    # Preserve this historical OB-only fixture while adapting its wildcard
    # connection to newly added, disabled-by-default CFG input ports.
    bench_text = bench.read_text()
    seam = "module tb_uart_status_observer;"
    if bench_text.count(seam) != 1:
        raise RuntimeError("OB-only fixture adaptation seam changed")
    adapted_bench = run / "tb_uart_status_observer.sv"
    adapted_bench.write_text(bench_text.replace(seam, seam +
        "\n    wire i_trace_ack=0; wire [319:0] i_trace_data=0; wire o_trace_request; wire [5:0] o_trace_index;"
        "\n    wire i_rx_word_clk=0; wire [383:0] i_rx_domains=0; wire [2:0] i_rx_reset_n=0;\n    wire [447:0] i_cfg_domains=0;\n    wire [1:0] i_cfg_domain_reset_n=0;"), newline="\n")
    decoder_path = PROJECT / "tools/uart_observer.py"
    inputs = sources + [bench, decoder_path, Path(__file__)]
    identity = [{"path": str(path), "sha256": sha(path)} for path in inputs]
    result = {"status": "IN_PROGRESS", "inputs": identity,
              "modelsim_bin": str(args.modelsim_bin), "synthesis": "NOT_RUN",
              "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN",
              "real_serial_access": "NOT_RUN"}

    def execute(exe, words):
        completed = subprocess.run([str(args.modelsim_bin / exe)] + list(map(str, words)), cwd=run,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-10000:])

    try:
        execute("vmap.exe", ["-c"])
        execute("vlib.exe", ["work"])
        execute("vmap.exe", ["work", "work"])
        execute("vlog.exe", ["-quiet", "-l", "rtl.log"] + sources)
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log", adapted_bench])
        execute("vsim.exe", ["-c", "work.tb_uart_status_observer", "-l", "run.log",
                             "-do", "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "run.log").read_text()
        if "RESULT: PASS uart_status_observer" not in body:
            raise RuntimeError(body[-10000:])
        for name in ("rtl.log", "bench.log", "run.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError("unclassified diagnostic in " + name)
        spec = importlib.util.spec_from_file_location("uart_observer_offline", decoder_path)
        decoder_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(decoder_module)
        decoder = decoder_module.FrameDecoder()
        raw = (run / "uart_frames.bin").read_bytes()
        frames = decoder.feed(raw)
        expected = int(re.search(r"RESULT: PASS uart_status_observer.*frames=(\d+)", body)[1])
        if len(frames) != expected or len(raw) != expected * 29 or decoder.crc_errors:
            raise RuntimeError("PC decoder did not recover every exact wire frame")
        if not any(frame["fresh_mask"] == 7 for frame in frames):
            raise RuntimeError("no fully fresh report")
        if not any(frame["fresh_mask"] != 7 for frame in frames):
            raise RuntimeError("no unavailable-domain report")
        if not any(frame["reset_n_mask"] != 7 for frame in frames):
            raise RuntimeError("no business-reset report")
        (run / "decoded_frames.json").write_text(json.dumps(frames, indent=2) + "\n")
        for row in identity:
            if sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("input changed during simulation: " + row["path"])
        result["status"] = "PASS"
        result["metrics"] = [line.strip("# ") for line in body.splitlines() if "RESULT: PASS" in line]
        result["offline_decoder"] = decoder.summary()
        result["wire_capture_sha256"] = sha(run / "uart_frames.bin")
        print("\n".join(result["metrics"]))
        print("Offline decoder:", json.dumps(decoder.summary()))
    except Exception as error:
        result["status"] = "FAIL"
        result["error"] = str(error)
        raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Results:", run / "RESULTS.json")


if __name__ == "__main__":
    main()
