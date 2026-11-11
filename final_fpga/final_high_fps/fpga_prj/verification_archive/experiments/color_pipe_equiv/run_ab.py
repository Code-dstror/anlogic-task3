"""Run a bounded, isolated TD A/B for the production WB/Tone/Gamma leaf."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REPO = PROJECT.parents[1]
BASELINE = "camera_fusion_r1_initial"
PARENT_SRC = "refactor/camera_raw_r2/src_fpga"
PROBE = "hdr_quality_color_probe"
LIMIT_SECONDS = 150
MULT = "ip/dsp_mult_fixed/mult_18s18s_p1"
MAC = "ip/stage3/fdct_mac19s14s_z33s_p34_m1p1"
ROM_DIRS = ("ip/stage3/tone96_rom0", "ip/stage3/tone96_rom1", "ip/gamma_rom_8x1024_ip")
IP_PREFIXES = (MULT, MAC, *ROM_DIRS)
REGISTERED_IP = (f"{MULT}/mult_18s18s_p1.xml", f"{MAC}/fdct_mac19s14s_z33s_p34_m1p1.xml",
                 *(f"{folder}/{folder.split('/')[-1]}.ipc" for folder in ROM_DIRS))
RTL = ("rtl/wide_color_pipeline.v", "rtl/hdr_tone96_shared4.v", "rtl/gamma_lut_10to8.v",
       "rtl/td_dsp_mult.v")
DATA = ("rtl/isp/color/gamma22_10to8.mif", "ip/coefficients/tone96_0.mif", "ip/coefficients/tone96_1.mif")
DIFFERING = (*RTL[:2], *DATA[1:])


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO)


def fixed_bytes(name):
    return git("show", f"{BASELINE}:{PARENT_SRC}/{name}")


def sha(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def run_variant(work, candidate, common, td_root):
    work.mkdir()
    payload = dict(common)
    for name in DIFFERING:
        payload[name] = ((HERE / ("candidate" if candidate else "baseline") / "wide_color_pipeline.v").read_bytes()
                         if name == "rtl/wide_color_pipeline.v" else (PROJECT / "src_fpga" / name).read_bytes())
    for name, content in payload.items():
        path = work / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    for name in ("probe.v", "probe.sdc"):
        (work / name).write_bytes((HERE / name).read_bytes())
    if candidate:
        (work / "candidate.flag").write_bytes(b"1\n")
    source_list = work / "sources.lst"
    source_list.write_text("\n".join([*REGISTERED_IP, *RTL, "probe.v", "probe.sdc"]) + "\n", encoding="ascii")
    input_files = [source_list, *(work / name for name in payload), work / "probe.v", work / "probe.sdc"]
    if candidate:
        input_files.append(work / "candidate.flag")
    input_hashes = sha(input_files)
    log_path = work / "td.log"
    command = [sys.executable, "-B", str(REPO / "tools/run_td.py"), str(HERE / "probe.tcl"),
               "--td-root", str(td_root), "--workdir", str(work), "--log", str(log_path)]
    result = {"baseline_commit": BASELINE, "variant": work.name, "command": command,
              "timeout_seconds": LIMIT_SECONDS, "input_sha256": input_hashes,
              "runner_sha256": sha((HERE / "probe.tcl", Path(__file__)))}
    manifest = work / "manifest.json"
    manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    start = time.monotonic()
    timed_out = False
    with (work / "launcher.log").open("wb") as log:
        process = subprocess.Popen(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            code = process.wait(timeout=LIMIT_SECONDS)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                           stdout=log, stderr=subprocess.STDOUT, timeout=4, check=False)
            code = process.wait(timeout=1)
    native = work / f"{PROBE}_Runs/syn_1"
    artifacts = [work / name for name in (f"{PROBE}.al", "reopened.area", "effective.params",
                 "reopened.timing", "reopened_check.timing", "color.timing", "tone.timing")]
    artifacts.extend(native / f"{PROBE}_gate.{ext}" for ext in ("db", "area", "timing"))
    passed = (code == 0 and not timed_out and all(p.is_file() and p.stat().st_size for p in artifacts)
              and (native / ".opt_gate.end.f").is_file() and not list(native.glob(".*.error.f"))
              and log_path.is_file() and "HDR_QUALITY_COLOR_PROBE_NATIVE_REOPENED" in
              log_path.read_text(encoding="utf-8", errors="replace") and sha(input_files) == input_hashes)
    optional = [work / "wb_normalize.timing", log_path, work / "launcher.log"]
    result.update(status="PASS" if passed else ("TIMEOUT" if timed_out else "FAIL"), returncode=code,
                  elapsed_seconds=round(time.monotonic() - start, 3),
                  artifact_sha256=sha(p for p in [*artifacts, *optional] if p.is_file()))
    manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{work.name}: {result['status']} ({result['elapsed_seconds']:.3f} s) {work}", flush=True)
    return passed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--variant", choices=("both", "baseline", "candidate"), default="both")
    args = parser.parse_args()
    if not args.name.isascii() or not args.name.replace("_", "").isalnum():
        parser.error("use a new ASCII alphanumeric run name")
    ip_files = tuple(p.relative_to(PROJECT / "src_fpga").as_posix()
                     for prefix in IP_PREFIXES for p in (PROJECT / "src_fpga" / prefix).rglob("*") if p.is_file())
    common = {name: (PROJECT / "src_fpga" / name).read_bytes() for name in (*ip_files, *RTL[2:], DATA[0])}
    work = PROJECT / "tmp/color_pipe_equiv" / args.name
    work.mkdir(parents=True)
    results = [run_variant(work / label, variant, common, args.td_root.resolve())
               for label, variant in (("baseline", False), ("candidate", True))
               if args.variant in ("both", label)]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
