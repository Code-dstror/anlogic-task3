"""Restore opaque fixed-board sources for the independent A/B runners."""
from pathlib import Path
import hashlib
import subprocess

PROJECT = Path(__file__).resolve().parents[3]
REPO = PROJECT.parents[1]
COMMIT = "8258220fdb54d8db8d9f9fd8b77b8185f0c7546d"
DEST = PROJECT / "tmp/fieldfix_20261109/baseline"


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for name in ("mono_config_engine_v2.v", "mono_config_service_v2.v", "real_hdr_pair_cycle_gate.v"):
        relative = "refactor/camera_raw_r2/src_fpga/rtl/" + name
        body = subprocess.check_output(["git", "show", COMMIT + ":" + relative], cwd=REPO)
        target = DEST / name
        if target.exists() and target.read_bytes() != body:
            raise RuntimeError("Preserved baseline differs; refusing to overwrite " + str(target))
        if not target.exists():
            target.write_bytes(body)
        print(name, hashlib.sha256(body).hexdigest())


if __name__ == "__main__":
    main()
