"""Replay the immutable a10 bench with passive internal tracing in a fresh run."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
ORIGINAL = PROJECT / "tmp/blackbox_fusion_product_a10_all_b"
BENCH = PROJECT / "tmp/blackbox_fusion_product_a10_inputs/bench"


def continuation_bench(run):
    """Preserve a10 traffic and observe the recovery-required interval after SOURCE."""
    body = (BENCH / "tb_fusion_product.sv").read_text(encoding="utf-8")
    for signal, expected, label in (
        ("o_replay_source_ok", "!frame_bad", "RAW replay SOURCE polarity"),
        ("o_jpeg_source_failed", "frame_bad", "JPEG SOURCE polarity"),
        ("o_jpeg_result_ok", "!frame_bad", "JPEG result polarity"),
        ("o_writer_ack_ok", "!frame_bad", "writer ACK polarity"),
        ("o_ticket_error", "frame_bad", "ticket error polarity"),
    ):
        old = f'check({signal} == {expected}, "{label}");'
        if body.count(old) != 1:
            raise ValueError(f"Unexpected a10 diagnostic observation: {label}")
        # This is an implementation trace with a negative terminal, so it must
        # not stop at the original positive expectation.
        body = body.replace(old, f'if (!$test$plusargs("DIAG_CONTINUE")) {old}')
    body = body.replace('if (!frame_bad)\n', 'if (!frame_bad && !$test$plusargs("DIAG_CONTINUE"))\n')
    target = '        complete_product("first");'
    if body.count(target) != 1:
        raise ValueError("Unexpected a10 first transaction")
    body = body.replace(target, '''        if ($test$plusargs("DIAG_CONTINUE")) begin
            wait (source_count != 0);
            repeat (12000) @(negedge i_mem_clk);
            $display("DIAG_POST_TIMEOUT t_ns=%0t faults=%b capture=%b buffer=%b armed=%b raw_empty=%b record_quiet=%b axi_debt=%b source=%d jpeg_source=%d jpeg_result=%d writer=%d ticket=%d raw_retire=%d record_offer=%d record_retire=%d host_bytes=%d",
                     $time, o_fault, o_capture_enabled, o_buffer_armed, o_session_armed,
                     o_raw_empty, o_record_quiet, !all_axi_drained(), source_count,
                     jpeg_source_count, result_count, writer_count, ticket_count,
                     raw_retire_count, offer_count, retire_count, host_bytes);
            $finish;
        end
''' + target)
    path = run / "tb_fusion_product_continue.sv"
    path.write_text(body, encoding="utf-8")
    return path


def run_step(argv, cwd, label, limit):
    log = cwd / f"{label}.log"
    receipt = cwd / f"{label}.json"
    command = [str(arg) for arg in argv]
    record = dict(argv=command, cwd=str(cwd), timeout_seconds=limit, log=str(log))
    try:
        with log.open("xb") as out:
            result = subprocess.run(command, cwd=cwd, stdout=out, stderr=subprocess.STDOUT,
                                    timeout=limit, check=False)
        record["returncode"] = result.returncode
    except subprocess.TimeoutExpired:
        record["timeout"] = True
        raise
    finally:
        receipt.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"{label} exited {result.returncode}, see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--continue-after-timeout", action="store_true")
    args = parser.parse_args()
    run = args.run_dir.resolve()
    if not run.is_relative_to(PROJECT / "tmp") or run == PROJECT / "tmp":
        parser.error("Use a fresh diagnostic subdirectory under this project's tmp")
    run.mkdir()
    for name in ("work", "ph1"):
        shutil.copytree(ORIGINAL / name, run / name)
    shutil.copytree(ORIGINAL / "normal/rom_init", run / "rom_init")
    ini = (ORIGINAL / "normal/modelsim.ini").read_text(encoding="utf-8")
    ini = ini.replace(ORIGINAL.as_posix(), run.as_posix())
    (run / "modelsim.ini").write_text(ini, encoding="utf-8")
    tools = args.modelsim_bin.resolve()
    run_step([tools / "vlog.exe", "-sv", "-work", "work", HERE / "trace_a10.sv"], run, "compile_trace", 30)
    switches = []
    if args.continue_after_timeout:
        bench = continuation_bench(run)
        run_step([tools / "vlog.exe", "-sv", "-work", "work", f"+incdir+{BENCH.as_posix()}", bench],
                 run, "compile_continuation", 30)
        switches.append("+DIAG_CONTINUE")
    run_step([tools / "vsim.exe", "-c", "-L", "ph1", "-voptargs=+acc",
              "work.tb_fusion_product", "work.PH1_PHY_GSR", "ph1.glbl", "work.trace_a10",
              "+CASE=normal", *switches, "-onfinish", "stop", "-do", "run -all; quit -f"], run, "simulate", 60)


if __name__ == "__main__":
    main()
