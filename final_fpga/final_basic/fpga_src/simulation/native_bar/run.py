"""Exercise the PH1A BAR request and completion ports with the real register bridge."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RTL = ROOT / "src_fpga/rtl"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--tx-candidate", type=Path, help="use an isolated candidate for the completion stage")
    args = parser.parse_args()
    if not re.fullmatch("[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("use a fresh run name")
    run = ROOT / "tmp/native_bar" / args.name
    run.mkdir(parents=True, exist_ok=False)
    sources = [RTL / name for name in ("camera_pcie_bar_rx.v", "camera_pcie_bar_tx.v", "c2h_bar_cq.v")]
    if args.tx_candidate:
        sources[1] = args.tx_candidate.resolve()
    bench = HERE / "tb_native_bar.sv"
    include = RTL / "include/04_include"
    inputs = [*sources, bench, include / "pcie_protocol_v1.vh", Path(__file__)]
    def snapshot():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    identity = snapshot()
    for label, argv in (
        ("lib", ["vlib", "work"]),
        ("rtl", ["vlog", "+incdir+" + str(include), *sources]),
        ("bench", ["vlog", "-sv", bench]),
        ("sim", ["vsim", "-c", "tb_native_bar", "-do", "onerror {quit -code 1}; run -all; quit -f"]),
    ):
        cmd = [args.modelsim_bin / (argv[0] + ".exe"), *argv[1:]]
        result = subprocess.run(cmd, cwd=run, capture_output=True, timeout=45)
        log = result.stdout + result.stderr
        (run / (label + ".log")).write_bytes(log)
        if result.returncode or re.search(rb"\*\* (?:Error|Fatal|Warning):", log):
            raise RuntimeError(log.decode(errors="replace")[-4000:])
    marker = re.search(rb"PASS native_bar checks=\d+ completed=\d+", log)
    if not marker or snapshot() != identity:
        raise RuntimeError("missing pass marker or changed inputs")
    summary = {"status": "PASS", "scope": "PH1A signal-level BAR RX -> camera registers -> native client1",
               "metric": marker.group().decode(), "sha256": identity}
    (run / "result.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf8")
    print(summary["metric"])


if __name__ == "__main__":
    main()
