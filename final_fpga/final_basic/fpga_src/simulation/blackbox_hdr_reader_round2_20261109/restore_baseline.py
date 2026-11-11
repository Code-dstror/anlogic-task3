"""Restore the opaque fixed pre-change HDR cursor; never overwrite other data."""
from pathlib import Path
import hashlib
import subprocess

PROJECT = Path(__file__).resolve().parents[3]
REPO = PROJECT.parents[1]
COMMIT = "492c53845ef6d4830a6bad0759aef82c8d002df3"
EXPECTED = "328a0bf1501df4962859f4ef480857039781baeff65fbbaf26c493adcfb6d879"


def main():
    body = subprocess.check_output([
        "git", "show", COMMIT + ":refactor/camera_raw_r2/src_fpga/rtl/hdr_pair_read_cursor.v"
    ], cwd=REPO)
    if hashlib.sha256(body).hexdigest() != EXPECTED:
        raise RuntimeError("Fixed source hash differs")
    target = REPO / "tmp/seed12_round2_20261109/hdr_reader_baseline/hdr_pair_read_cursor.v"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() != body:
        raise RuntimeError("Preserved baseline differs; refusing overwrite")
    if not target.exists():
        target.write_bytes(body)
    print(str(target), EXPECTED)


if __name__ == "__main__":
    main()
