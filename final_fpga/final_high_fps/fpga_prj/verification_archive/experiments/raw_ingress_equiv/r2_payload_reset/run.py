"""Run the same native RAW10 ingress carriers with the payload reset A/B."""

import argparse
import importlib.util
from pathlib import Path
import re
import sys


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("raw_ingress_probe", HERE.parent / "run.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
probe.HERE = HERE
probe.BASELINE = HERE / "baseline" / probe.LEAF
probe.BASELINE_SHA = "8569d76989de58b9940cfa9090f8f3fd3ecd6c3eddea75b34fa31e01743381c3"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--name", required=True)
parser.add_argument("--td-root", type=Path, required=True)
args = parser.parse_args()
if not re.fullmatch(r"[a-z][a-z0-9_-]+", args.name):
    parser.error("Use a fresh run name with lower-case letters, digits, underscores or dashes")
args.td_root = args.td_root.resolve(strict=True)
if probe.digest(probe.BASELINE) != probe.BASELINE_SHA:
    raise SystemExit("Adopted five-window baseline SHA256 mismatch")
results = [probe.run(args, profile, arm) for profile in probe.PROFILES for arm in ("baseline", "candidate")]
sys.exit(0 if all(results) else 1)
