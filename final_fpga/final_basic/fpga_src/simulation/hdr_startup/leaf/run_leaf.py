"""Short A/B leaf parser checks; each run binds only its actual five RTL inputs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REPO = ROOT.parents[1]
BASE = "77a0d36befb697dd9cbd5f0a8e56cfc5aeb491b1"
FIX = "82d5c04f58c21c33773462c8ac050a549771d387"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--modelsim-bin", type=Path, required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--baseline", action="store_true")
    args = ap.parse_args()
    assert re.fullmatch(r"[A-Za-z0-9_-]{1,48}", args.name)
    run = ROOT / "tmp/hdr_startup/leaf" / args.name
    run.mkdir(parents=True, exist_ok=False)
    result = dict(status="IN_PROGRESS", baseline_commit=BASE, fix_commit=FIX,
        expected_startup_fix=not args.baseline, inputs=[], commands=[],
        boundary="Direct complete CSI WORD headers; valid-low gaps; finite output stalls; configuration fault synchronization",
        synthesis="NOT_RUN", pr="NOT_RUN", timing="NOT_RUN", bitgen="NOT_RUN", board="NOT_RUN")
    start = time.monotonic()
    names = ["real_hdr_csi_word_core.v", "imx415_hdr2_recipe_rom.v", "imx415_hdr2_config_owner.v",
             "camera_i2c_write.v", "real_hdr_sensor_config.v"]
    sources = []
    sha = lambda b: hashlib.sha256(b).hexdigest()

    def call(argv):
        entry = dict(argv=list(map(str, argv)), cwd=str(run))
        result["commands"].append(entry)
        process = subprocess.run(entry["argv"], cwd=run, capture_output=True, text=True,
            errors="replace", timeout=55)
        log = f"command_{len(result['commands']):02d}.log"
        (run / log).write_text(process.stdout + process.stderr, encoding="utf-8")
        entry.update(returncode=process.returncode, log=log)
        assert process.returncode == 0, process.stdout[-4000:] + process.stderr[-1000:]

    try:
        for name in names:
            path = ROOT / "src_fpga/rtl" / name
            body = path.read_bytes()
            source = path
            if args.baseline and name == names[0]:
                body = subprocess.check_output(["git", "show", BASE + ":refactor/hdr_dehaze_auto/src_fpga/rtl/" + name], cwd=REPO)
                source = run / name
                source.write_bytes(body)
            if not args.baseline and name == names[0]:
                fixed = subprocess.check_output(["git", "show", FIX + ":refactor/hdr_startup_fix/src_fpga/rtl/" + name], cwd=REPO)
                assert body == fixed
            result["inputs"].append(dict(path=str(source), sha256=sha(body)))
            sources.append(source)
        bench = HERE / "tb_hdr_startup_leaf.sv"
        result["bench_sha256"] = sha(bench.read_bytes())
        ms = args.modelsim_bin
        call([ms / "vsim.exe", "-version"])
        call([ms / "vmap.exe", "-c"])
        call([ms / "vlib.exe", "work"])
        call([ms / "vmap.exe", "work", "work"])
        call([ms / "vlog.exe", "-sv", "-work", "work", "-l", "compile.log"] + sources + [bench])
        call([ms / "vsim.exe", "-c", "work.tb_hdr_startup_leaf", "-gEXPECT_STARTUP_FIX=" + str(int(not args.baseline)),
              "-l", "simulation.log", "-do", "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "simulation.log").read_text(errors="replace")
        assert not re.search(r"CHECK_FAIL|\*\*\s+(?:Error|Fatal):", body), body[-5000:]
        summary = re.search(r"RESULT: PASS cases=(\d+) checks=(\d+) hold_checks=(\d+) expect_fix=(\d+)", body)
        assert summary and int(summary[1]) == 11, body[-5000:]
        for row in result["inputs"]:
            assert sha(Path(row["path"]).read_bytes()) == row["sha256"]
        result.update(status="PASS", cases=int(summary[1]), checks=int(summary[2]), hold_checks=int(summary[3]))
    except Exception as exc:
        result.update(status="FAIL", error=str(exc))
        raise
    finally:
        result["elapsed_s"] = round(time.monotonic() - start, 3)
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(dict(run=str(run), status=result["status"], error=result.get("error"))))


if __name__ == "__main__":
    main()
