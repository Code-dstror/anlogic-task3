"""Bounded real-TOP cold DUAL/N2, HDR + automatic dehaze + HE, through all four trusted FS."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
COMMON = HERE.parent / "unified_dual_rate"
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name", required=True)
    ap.add_argument("--td-root", required=True)
    ap.add_argument("--modelsim-bin", required=True)
    args = ap.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,40}", args.name):
        ap.error("invalid evidence directory name")
    start = time.monotonic()
    out = ROOT / "tmp/stereo_hdr_dehaze_short" / args.name
    out.mkdir(parents=True, exist_ok=False)
    fixture = out / "fixture"
    fixture.mkdir()
    manifest = json.loads((ROOT / "SOURCE_MANIFEST.json").read_bytes())
    production = {ROOT / row["path"]: row["sha256"] for row in manifest["files"]}
    if ROOT / "src_fpga/rtl/dehaze_dcp_restore4.v" not in production:
        raise ValueError("production closure does not include the selected restoration kernel")
    own_inputs = [Path(__file__), HERE / "hdr_he.patch", COMMON / "run.py",
                  ROOT / "SOURCE_MANIFEST.json", ROOT / "docs/SOURCE_SEAL.json"]
    for name in ("tb_stereo_hdr_top.sv", "axi_boundaries.sv", "PROVENANCE.json", "check.py",
                 "dual_reference.py", "unified_rate_monitor.vh"):
        shutil.copyfile(COMMON / name, fixture / name)
        own_inputs.append(COMMON / name)
    own = {p: sha(p) for p in own_inputs}
    result = {"status": "RUNNING", "inputs": {str(p): h for p,h in own.items()},
              "scope": "through trusted FS before sensor warmup; no APPLIED or JPEG yet"}
    try:
        for p, expected in production.items():
            if sha(p) != expected:
                raise RuntimeError("stale production seal before launch: "+str(p))
        subprocess.run(["git", "-c", "core.autocrlf=false", "apply", "--no-index", "--whitespace=nowarn",
                        str(HERE/"hdr_he.patch")], cwd=fixture,
                       env=dict(os.environ, GIT_CEILING_DIRECTORIES=str(out)), check=True)
        modspec = importlib.util.spec_from_file_location("hdr_top_short_driver",COMMON/"run.py")
        driver = importlib.util.module_from_spec(modspec)
        modspec.loader.exec_module(driver)
        driver.HERE = fixture
        # The existing native runner selects the same project/HD geometry, checks all
        # stage inputs at the end and records every tool command. Only the bench differs.
        sys.argv = [str(COMMON/"run.py"), "--name",args.name, "--stereo-hdr","--startup-only",
                    "--td-root",args.td_root,"--modelsim-bin",args.modelsim_bin,
                    "--wall-timeout",str(max(1, int(179 - (time.monotonic()-start))))]
        driver.main()
        raw = ROOT / "tmp/unified_dual_rate" /args.name
        q = json.loads((raw/"qualification.json").read_bytes())
        marker = "RESULT: PASS STEREO_HDR_TOP_STARTUP HDR_DEHAZE_HE"
        if q["status"] != "PASS_STEREO_HDR_TOP_STARTUP" or not any(marker in line for line in q["metrics"]):
            raise RuntimeError("required dehaze-specific physical cold-boot check missing")
        if any(sha(p)!=h for p,h in {**own, **production}.items()):
            raise RuntimeError("source, seal or test changed during validation")
        result.update(status="PASS_HDR_DEHAZE_HE_COLD",checks=q["metrics"],
                      design_sha256=json.loads((ROOT/"docs/SOURCE_SEAL.json").read_bytes())["design_sha256"],
                      source_identity_sha256=q["source_identity_sha256"])
    except Exception as exc:
        result.update(status="FAIL",error=str(exc))
        raise
    finally:
        result["elapsed_s"]=round(time.monotonic()-start,3)
        (out/"result.json").write_text(json.dumps(result,indent=2)+"\n")
        print(out/"result.json")


if __name__ == "__main__":
    main()
