"""Restore the fixed seed12 input as an opaque baseline, without overwriting it."""
from pathlib import Path
import hashlib
import subprocess

PROJECT = Path(__file__).resolve().parents[3]
REPO = PROJECT.parents[1]
COMMIT = "4a08ae35391e7b7ea6767260d7d1b4b182ef4bb9"
RELATIVE = "refactor/camera_raw_r2/src_fpga/rtl/real_hdr_pair_cycle_gate.v"
EXPECTED = "9a8aaad1b7e59827c9afb0ddfd539bcbc3f78ca39002a1a0e2861f4c789fb2ae"


def main():
    body = subprocess.check_output(["git", "show", COMMIT + ":" + RELATIVE], cwd=REPO)
    if hashlib.sha256(body).hexdigest() != EXPECTED:
        raise RuntimeError("Fixed board-source hash differs")
    target = PROJECT / "tmp/seed12fix_20261109/baseline/real_hdr_pair_cycle_gate.v"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() != body:
        raise RuntimeError("Preserved baseline differs; refusing to overwrite it")
    if not target.exists():
        target.write_bytes(body)
    print(str(target), EXPECTED)


if __name__ == "__main__":
    main()
