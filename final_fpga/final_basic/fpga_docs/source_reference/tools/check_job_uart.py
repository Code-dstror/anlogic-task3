"""Exercise the candidate's TX bytes, independently stopped DFI clock and host decoder."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from uart_observer import FrameDecoder

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    if not args.name.isidentifier():
        parser.error("run name must be an identifier")
    run = ROOT / "tmp/job_uart" / args.name
    run.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "src_fpga/rtl" / (name + ".v") for name in
               ("reset_release_sync", "uart_observer_snapshot", "cfg_diag_snapshot", "uart_status_observer")]
    bench = ROOT / "src_fpga/simulation/control/tb_unified_job_uart.sv"

    def execute(exe, *words):
        subprocess.run([args.modelsim_bin / exe, *words], check=True, cwd=run)

    execute("vlib.exe", "work")
    execute("vlog.exe", "-quiet", "-sv", *sources, bench)
    execute("vsim.exe", "-c", "-l", "wire.log", "work.tb_unified_job_uart",
            "-do", "onerror {quit -code 1}; run -all; quit -f")
    wire = (run / "job_uart.bin").read_bytes()
    decoder = FrameDecoder()
    frames = decoder.feed(wire)
    jobs = [f for f in frames if f.get("frame_type") == "job"]
    assert len(wire) == 5*97 and len(frames) == 10 and len(jobs) == 5
    assert jobs[0]["dfi"]["raw"] is True and jobs[0]["dfi"]["hdr"] is False
    assert not any(f.get("frame_type") == "rx" for f in frames)
    assert jobs[0]["fresh_mask"] == 3 and jobs[0]["dfi"]["sequence"] == 0x12345678
    assert any(f["fresh_mask"] == 2 for f in jobs[1:4])
    assert jobs[-1]["fresh_mask"] == 3 and jobs[-1]["dfi"]["sequence"] == 0x89abcdef
    assert all(f["pixel"]["fs"] == [1, 0x5678] for f in jobs)
    damaged = bytearray(wire[29:97])
    damaged[17] ^= 1
    bad = FrameDecoder()
    assert not bad.feed(damaged) and bad.summary()["job_crc_errors"] == 1
    result = {"status": "PASS", "wire_bytes": len(wire), "rounds": len(jobs),
              "fresh_masks": [f["fresh_mask"] for f in jobs], "crc_negative": "PASS",
              "inputs": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in [*sources, bench, Path(__file__), ROOT / "tools/uart_observer.py"]}}
    (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
