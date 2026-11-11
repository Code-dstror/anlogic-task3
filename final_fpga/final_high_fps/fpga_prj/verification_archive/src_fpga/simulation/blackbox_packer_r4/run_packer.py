"""Run both opaque packer arms through the same bounded public-port bench."""

import argparse
import hashlib
import json
import re
import subprocess
import time
from datetime import datetime
from pathlib import Path

STAGE = Path(__file__).resolve().parents[3]
CONTRACT = STAGE / "experiments" / "packer_reachable_r4_20261110"
BENCH = Path(__file__).with_name("tb_packer.sv")


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run_command(command, cwd, log, deadline, records):
    timeout = min(35, deadline - time.monotonic())
    if timeout <= 0:
        raise RuntimeError("Black-box wall-clock budget expired")
    record = {"command": subprocess.list2cmdline(command), "cwd": str(cwd), "log": str(log)}
    records.append(record)
    started = time.monotonic()
    with log.open("wb") as output:
        with subprocess.Popen(
            command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW,
        ) as process:
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                subprocess.run(
                    ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3, check=False,
                    creationflags=subprocess.CREATE_NO_WINDOW,
                )
                if process.poll() is None:
                    process.kill()
                record["status"] = "TIMEOUT"
                raise RuntimeError(f"Command timed out, see {log}") from None
    record.update(returncode=code, elapsed_seconds=round(time.monotonic() - started, 3))
    if code != 0:
        raise RuntimeError(f"Command exited {code}, see {log}")


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    args = parser.parse_args()
    model_bin = args.modelsim_bin.resolve(strict=True)
    root = STAGE / "tmp" / ("packer_r4_blackbox_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    root.mkdir(parents=True, exist_ok=False)
    print(f"Run directory {root}", flush=True)
    deadline = time.monotonic() + 110
    opaque = CONTRACT / "OPAQUE_SOURCES.json"
    profiles = json.loads(opaque.read_text(encoding="utf-8"))
    hashes = {path: sha256(path) for path in (BENCH, opaque, CONTRACT / "PORTS.vh",
                                              CONTRACT / "PUBLIC_CONTRACT.md", Path(__file__))}
    records = []
    verdicts = []
    error = None

    def model(executable, args, cwd, log):
        run_command([str(model_bin / (executable + ".exe")), *args], cwd, log, deadline, records)

    try:
        for items in profiles["variants"].values():
            for item in items:
                path = STAGE / item["path"]
                hashes[path] = sha256(path)
                if hashes[path] != item["sha256"]:
                    raise RuntimeError(f"Opaque source hash differs from manifest: {path}")
        model("vsim", ["-version"], root, root / "tool_version.log")
        for arm, items in profiles["variants"].items():
            cwd = root / arm
            cwd.mkdir()
            model("vlib", ["work"], cwd, cwd / "vlib.log")
            model("vlog", ["-work", "work", *(str(STAGE / item["path"]) for item in items)],
                  cwd, cwd / "vlog_dut.log")
            model("vlog", ["-sv", "-work", "work", str(BENCH)], cwd, cwd / "vlog_bench.log")
            for limit in profiles["legal_test_max_payload_bytes"]:
                log = cwd / f"MAX{limit}.log"
                model("vsim", [
                    "-c", "-onfinish", "exit", f"-gMAX_BYTES={limit}",
                    "-l", f"MAX{limit}.transcript", "work.tb_packer",
                    "-do", "onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0",
                ], cwd, log)
                markers = re.findall(
                    rf"^\s*(?:#\s*)?(PACKER PASS MAX={limit} .+)$",
                    log.read_text(encoding="utf-8", errors="replace"), re.MULTILINE,
                )
                if len(markers) != 1:
                    raise RuntimeError(f"Expected one scored PASS marker, see {log}")
                verdicts.append({"arm": arm, "max": limit, "result": markers[0]})
                print(f"{arm}: {markers[0]}", flush=True)
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        error = str(exc)

    bindings = {}
    for path, digest in hashes.items():
        after = sha256(path)
        bindings[str(path)] = {"before": digest, "after": after}
        if after != digest and error is None:
            error = f"Input changed during run: {path}"
    report = {
        "baseline_commit": profiles["baseline_commit"],
        "status": "FAIL" if error else "PASS",
        "error": error,
        "source_bindings": bindings,
        "commands": records,
        "results": verdicts,
    }
    (root / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if error:
        raise SystemExit(error)


if __name__ == "__main__":
    run()
