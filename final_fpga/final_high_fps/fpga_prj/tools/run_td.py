#!/usr/bin/env python3
"""Run an Anlogic Tang Dynasty (TD) TCL script headlessly and report a reliable status.

The TD TCL interpreter (`td_commands_prompt.exe -nogui`) does NOT fail loudly:
`wait_run` returns success even when a synthesis/P&R run aborted, and many
errors are only warnings at the TCL level. This wrapper therefore judges
success by three independent signals:

  1. the process exit code (a TCL `exit N` or script error propagates),
  2. the per-step `.error.f` marker files TD writes inside each run directory,
  3. error/CRITICAL patterns in the captured log.

Usage:
    python run_td.py <script.tcl> [--workdir DIR] [--log FILE] [--td-root PATH]
    python run_td.py --find            # locate the TD installation and exit

Exit codes:
    0 = success, 1 = TD reported errors, 2 = wrapper/usage problem
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

# Error patterns that indicate a real tool failure rather than a benign warning.
ERROR_PATTERNS = [
    re.compile(r"^\s*USR-\d+ ERROR", re.M),
    re.compile(r"^\s*PRJ-\d+ ERROR", re.M),
    re.compile(r"^\s*PRJ-5303 WARNING: Run \S+ failed", re.M),
    re.compile(r"^\s*PRJ-8806 ERROR", re.M),
    re.compile(r"^\s*PRJ-8808 ERROR", re.M),
    # Match diagnostic words, not RTL identifiers such as o_error_code_reg.
    re.compile(r"CRITICAL-WARNING: .*\b(failed|error|invalid)\b", re.M | re.I),
    re.compile(r"ERROR: .*(not exist|invalid|failed|cannot|unable)", re.M | re.I),
]

# Warnings that are expected and harmless in normal flows.
BENIGN = [
    re.compile(r"could not find top-level module/unit", re.I),
    re.compile(r"HDL-5007 WARNING", re.I),
    re.compile(r"Device speed .* is invalid for .* auto change to default", re.I),
]

TD_EXE_NAMES = ["td_commands_prompt.exe", "td_commands_prompt"]
GUI_EXE_NAMES = ["td.exe"]
SEARCH_ROOTS = [
    r"C:\Anlogic",
    r"D:\Anlogic",
    r"E:\Anlogic",
    r"F:\Anlogic",
    r"C:\Program Files\Anlogic",
    r"C:\Program Files (x86)\Anlogic",
    r"D:\Program Files\Anlogic",
    r"E:\Program Files\Anlogic",
    r"C:\APP\Anlogic",
    r"D:\APP\Anlogic",
    r"E:\APP\Anlogic",
    r"F:\APP\Anlogic",
    r"D:\App\Anlogic",
    r"E:\App\Anlogic",
    r"C:\App",
    r"D:\App",
    r"E:\App",
    r"F:\App",
]


def find_td_root() -> Path | None:
    """Locate the TD installation directory (the one containing bin/)."""
    # 1. explicit environment overrides
    for var in ("TD_ROOT", "ANLOGIC_TD_ROOT", "TD_INSTALL_DIR"):
        val = os.environ.get(var)
        if val and (Path(val) / "bin" / "td_commands_prompt.exe").is_file():
            return Path(val)

    # 2. the running executable's own directory, if the wrapper ships inside TD
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "bin" / "td_commands_prompt.exe").is_file():
            return parent

    # 3. PATH
    for name in TD_EXE_NAMES:
        found = _which(name)
        if found:
            return found.parent.parent

    # 4. well-known install roots, one level of subdirectories deep
    for root in SEARCH_ROOTS:
        rp = Path(root)
        if not rp.is_dir():
            continue
        if (rp / "bin" / "td_commands_prompt.exe").is_file():
            return rp
        try:
            for child in sorted(rp.iterdir()):
                if child.is_dir() and (child / "bin" / "td_commands_prompt.exe").is_file():
                    return child
        except OSError:
            continue

    # 5. Windows registry
    try:
        import winreg  # type: ignore

        for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
            for sub in (
                r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
            ):
                try:
                    key = winreg.OpenKey(hive, sub)
                except OSError:
                    continue
                for i in range(winreg.QueryInfoKey(key)[0]):
                    try:
                        name = winreg.EnumKey(key, i)
                        with winreg.OpenKey(key, name) as sk:
                            disp = _regval(sk, "DisplayName")
                            loc = _regval(sk, "InstallLocation")
                            if loc and disp and "TD" in disp and "Anlogic" in disp.replace(" ", ""):
                                p = Path(loc.strip().strip('"'))
                                if (p / "bin" / "td_commands_prompt.exe").is_file():
                                    return p
                    except OSError:
                        continue
    except ImportError:
        pass

    return None


def _regval(key, name):
    try:
        import winreg  # type: ignore

        return winreg.QueryValueEx(key, name)[0]
    except Exception:
        return None


def _which(name: str) -> Path | None:
    from shutil import which

    p = which(name)
    return Path(p) if p else None


def _modified_since(path: Path, ts: float) -> bool:
    try:
        return path.stat().st_mtime >= ts
    except OSError:
        return False


def run(script: Path, workdir: Path, log_path: Path, td_root: Path) -> int:
    import time

    td_root = td_root.resolve()
    exe = td_root / "bin" / "td_commands_prompt.exe"
    if not exe.is_file():
        print(f"[run_td] FATAL: interpreter not found at {exe}", file=sys.stderr)
        return 2
    run_start_time = time.time()

    workdir.mkdir(parents=True, exist_ok=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    env = dict(os.environ)
    env["PATH"] = str(td_root / "bin") + os.pathsep + env.get("PATH", "")
    # TD 2026.2 also reads TD_ROOT during device-library loading. Inheriting
    # another installation's root can assert inside import_device even when
    # the selected executable and TD_HOME are correct. Pin only the child;
    # leave the caller and persistent Windows environment unchanged.
    for variable in ("TD_HOME", "TD_ROOT", "ANLOGIC_TD_ROOT", "TD_INSTALL_DIR"):
        env[variable] = str(td_root)

    # Pass the script path as argv: TD sources it and honours `exit N`.
    cmd = [str(exe), "-nogui", str(script.resolve())]
    print(f"[run_td] cwd={workdir}")
    print(f"[run_td] cmd={subprocess.list2cmdline(cmd)}")

    with open(log_path, "w", encoding="utf-8", errors="replace") as lf:
        proc = subprocess.run(
            cmd, cwd=str(workdir), stdout=lf, stderr=subprocess.STDOUT, env=env
        )
    rc = proc.returncode

    text = log_path.read_text(encoding="utf-8", errors="replace")

    # Signal 2: .error.f markers written by TD's flow scripts.
    # Only trust markers that this run touched: TD never removes them, so a
    # stale marker from an earlier failed run would otherwise poison the verdict.
    started = run_start_time
    err_markers = [
        m
        for m in sorted(workdir.rglob(".*.error.f"))
        if _modified_since(m, started)
    ]
    stale_markers = [
        m
        for m in sorted(workdir.rglob(".*.error.f"))
        if not _modified_since(m, started)
    ]

    # Signal 3: error patterns, after removing benign lines.
    scrub = text
    for b in BENIGN:
        scrub = b.sub("", scrub)
    hits: list[str] = []
    for pat in ERROR_PATTERNS:
        for m in pat.finditer(scrub):
            line = scrub[m.start():scrub.find("\n", m.start())].strip()
            if line and line not in hits:
                hits.append(line)

    print("")
    print("=" * 72)
    print(f"[run_td] TD exit code     : {rc}")
    print(f"[run_td] log              : {log_path}")
    print(f"[run_td] .error.f markers : {len(err_markers)} (fresh)")
    for m in err_markers:
        print(f"           - {m.relative_to(workdir)}")
    if stale_markers:
        print(f"[run_td]   ({len(stale_markers)} stale .error.f from earlier runs ignored)")
    print(f"[run_td] error lines      : {len(hits)}")
    for h in hits[:40]:
        print(f"           ! {h}")
    if len(hits) > 40:
        print(f"           ... and {len(hits) - 40} more (see log)")

    ok = rc == 0 and not err_markers and not hits
    print(f"[run_td] RESULT           : {'SUCCESS' if ok else 'FAILED'}")
    print("=" * 72)
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Run a TD TCL script headlessly.")
    ap.add_argument("script", nargs="?", help="TCL script to run")
    ap.add_argument("--workdir", default=None, help="working directory (default: script's dir)")
    ap.add_argument("--log", default=None, help="log file (default: <workdir>/td_run.log)")
    ap.add_argument("--td-root", default=None, help="explicit TD installation root")
    ap.add_argument("--find", action="store_true", help="locate TD installation and exit")
    args = ap.parse_args()

    if args.find or not args.script:
        # Repository references are now centralized outside the skill. Retain
        # support for older standalone bundles that still have a doc folder.
        skill_root = Path(__file__).resolve().parent.parent
        vendor_doc = skill_root.parents[2] / "references" / "vendor" / "安路科技_TD_技术文档"
        bundled_doc = vendor_doc if vendor_doc.is_dir() else skill_root / "doc"
        print(f"SKILL_ROOT={skill_root}")
        if bundled_doc.is_dir():
            n = sum(1 for _ in bundled_doc.rglob("*") if _.is_file())
            print(f"VENDOR_DOC={bundled_doc}  ({n} files, usable without TD)")
        else:
            print(f"VENDOR_DOC=MISSING ({bundled_doc})")

        root = Path(args.td_root) if args.td_root else find_td_root()
        if not root:
            print("[run_td] WARNING: TD installation NOT found - the vendor docs and",
                  file=sys.stderr)
            print("         reference/ files still work, but no tool can be run.",
                  file=sys.stderr)
            return 2
        print(f"TD_ROOT={root}")
        print(f"TD_TCL={root / 'bin' / 'td_commands_prompt.exe'}")
        print(f"TD_GUI={root / 'bin' / 'td.exe'}")
        print(f"TD_DOC={root / 'doc'}  (installed edition; repository index: VENDOR_DOC)")
        print(f"TD_SIM_RELEASE={root / 'sim_release'}")
        print(f"TD_ARCH={root / 'arch'}")
        return 0

    script = Path(args.script)
    if not script.is_file():
        print(f"[run_td] FATAL: script not found: {script}", file=sys.stderr)
        return 2

    td_root = Path(args.td_root) if args.td_root else find_td_root()
    if not td_root:
        print(
            "[run_td] FATAL: could not locate the Anlogic TD installation.\n"
            "         Set TD_ROOT or pass --td-root.",
            file=sys.stderr,
        )
        return 2

    workdir = Path(args.workdir) if args.workdir else script.parent
    log_path = Path(args.log) if args.log else workdir / "td_run.log"
    return run(script, workdir, log_path, td_root)


if __name__ == "__main__":
    sys.exit(main())
