"""Extract the actual USER observer block and check first-observed cause/phase only."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def one(pattern, source):
    found = re.findall(pattern, source, re.S)
    if len(found) != 1:
        raise RuntimeError(f"expected one observer source block, got {len(found)}: {pattern}")
    return found[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    run = PROJECT / "tmp/user_fault_observe" / args.name
    run.mkdir(parents=True, exist_ok=False)
    top = PROJECT / "src_fpga/rtl/anlogic2026.v"
    source = top.read_text()
    scope = source[source.index("begin:g_status_uart"):]
    blocks = {
        "flags_registers": one(r"(reg\s+\[11:0\]\s+user_flags_meta,user_flags;)", scope),
        "fault_registers": one(r"(reg\s+\[3:0\]\s+pixel_faults,dfi_faults,user_faults;)", scope),
        "progress_registers": one(r"(reg\s+\[1:0\]\s+pixel_progress,dfi_progress,user_progress;)", scope),
        "phase_register": one(r"(reg\s+\[2:0\]\s+user_first_fault_phase;)", scope),
        "causes": one(r"(wire\s+\[3:0\]\s+user_causes\s*=.*?;)", scope),
        "flags": one(r"(wire\s+\[11:0\]\s+user_observe_flags\s*=.*?;)", scope),
        "sequential": one(r"(always\s*@\(posedge user_clk or negedge debug_user_rst_n\)\s*begin.*?\n\s{12}end)\b", scope),
    }
    # These signals exist in the real top but must have no control dependency
    # in this passive observer block. Keep them as stimulus-only probe inputs.
    for forbidden in ("actual_c2h_valid", "actual_c2h_ready", "actual_c2h_last", "debug_app_rst_n", "app_hard_rst_n"):
        if re.search(r"\b" + forbidden + r"\b", "\n".join(blocks.values())):
            raise RuntimeError("unexpected event/reset dependency: " + forbidden)
    probe = """`timescale 1ns/1ps
module extracted_user_observer(
 input wire user_clk,debug_user_rst_n,user_rst_n,debug_app_rst_n,app_hard_rst_n,
 input wire [7:0] transport_observe,input wire [1:0] product_fault_user,
 input wire product_axil_fault,transport_recovery,memory_fault_user,
 input wire reset_pending_user,memory_owner_ready,product_buffer_armed,cfg_user_initialized,user_link_up,
 input wire jpeg_user_retire_valid,jpeg_user_retire_ready,
 input wire actual_c2h_valid,actual_c2h_ready,actual_c2h_last,
 output wire [3:0] o_faults,o_causes,output wire [2:0] o_first_phase,
 output wire [11:0] o_flags,output wire [1:0] o_progress);
""" + "\n".join(blocks.values()) + """
 assign o_faults=user_faults;assign o_causes=user_causes;assign o_first_phase=user_first_fault_phase;
 assign o_flags=user_observe_flags;assign o_progress=user_progress;
endmodule
"""
    extracted = run / "extracted_user_observer.v"
    extracted.write_text(probe, newline="\n")
    (run / "EXTRACTED_SOURCE.json").write_text(json.dumps({"top": str(top), "top_sha256": sha(top), "blocks": blocks}, indent=2) + "\n")
    bench = HERE / "tb_user_fault_observe.sv"
    inputs = [{"path": str(path), "sha256": sha(path)} for path in (top, bench, Path(__file__))]
    result = {"status": "IN_PROGRESS", "inputs": inputs, "extracted_sha256": sha(extracted),
              "scope": "ACTUAL_TOP_USER_OBSERVER_ONLY_NO_BUSINESS_OR_UART_PROTOCOL_CHANGE",
              "synthesis": "NOT_RUN", "physical": "NOT_RUN", "board": "NOT_RUN"}

    def execute(exe, words):
        completed = subprocess.run([str(args.modelsim_bin / exe)] + list(map(str, words)), cwd=run,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-10000:])

    try:
        execute("vmap.exe", ["-c"]); execute("vlib.exe", ["work"]); execute("vmap.exe", ["work", "work"])
        execute("vlog.exe", ["-quiet", "-l", "rtl.log", extracted])
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log", bench])
        execute("vsim.exe", ["-c", "work.tb_user_fault_observe", "-l", "run.log",
                             "-do", "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "run.log").read_text()
        if "RESULT: PASS user_fault_observe" not in body:
            raise RuntimeError(body[-10000:])
        for name in ("rtl.log", "bench.log", "run.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError("unclassified diagnostic in " + name)
        for row in inputs:
            if sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("source changed during observer check: " + row["path"])
        result["status"] = "PASS"
        result["metrics"] = [line.strip("# ") for line in body.splitlines() if "RESULT: PASS" in line]
        print("\n".join(result["metrics"]))
    except Exception as error:
        result["status"] = "FAIL"; result["error"] = str(error); raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Results:", run / "RESULTS.json")


if __name__ == "__main__":
    main()
