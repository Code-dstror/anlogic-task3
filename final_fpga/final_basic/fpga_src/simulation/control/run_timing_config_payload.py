"""Check config session payload and APPLIED kind timing cuts against fixed a4."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = "a4ce0e9ddfa46379386c67791962ce9d8ce814d7"
BASE_ENGINE = "refactor/hdr_jpeg_timing/src_fpga/rtl/mono_config_engine_v2.v"
BASE_BENCH = "refactor/hdr_jpeg/src_fpga/simulation/control/tb_mono_config_ack_pipeline.sv"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def adapt_bench(body):
    old = '''            check(base.m_config_data===ref_m_config_data&&base.active_config===ref_active_config,
                "full 1184-bit remote and active tuples remain cycle equivalent");'''
    new = '''            check(base.active_config===ref_active_config,"full active tuple always exact");
            check({base.m_config_data[1183:64],base.m_config_data[31:0]}===
                {ref_m_config_data[1183:64],ref_m_config_data[31:0]},
                "only unowned prepared-session bits may differ");
            if(base.m_config_valid)check(base.m_config_data===ref_m_config_data,
                "full owned remote tuple exact including stall and ACK");
            check({base.dut.prepared_fields[341:64],base.dut.prepared_fields[31:0]}===
                {reference_dut.prepared_fields[341:64],reference_dut.prepared_fields[31:0]},
                "all other 310 prepared bits including unused bits exact");
            if(base.dut.state==1||base.dut.state==2||base.dut.state==3||
                ((base.dut.rx_active||base.dut.rx_done)&&base.dut.rx_capture))
                check(base.dut.prepared_fields===reference_dut.prepared_fields,
                    "full prepared owner exact after accepted header");
            check({base.dut.state,base.dut.initialized,base.dut.tx_state,
                base.dut.rx_active,base.dut.rx_done,base.dut.rx_capture,base.dut.rx_shape_bad,
                base.dut.rx_fields_bad,base.dut.rx_identity_bad,base.dut.rx_schema2,
                base.dut.ack_compare_valid,base.dut.ack_compare_eligible,base.dut.ack_compare_ok,base.dut.ack_compare_boot,
                base.dut.ack_result_valid,base.dut.ack_result_eligible,base.dut.ack_result_ok,base.dut.ack_result_boot,
                base.dut.remote_pending,base.dut.remote_sent,base.dut.remote_applied,base.dut.remote_fault}===
                {reference_dut.state,reference_dut.initialized,reference_dut.tx_state,
                reference_dut.rx_active,reference_dut.rx_done,reference_dut.rx_capture,reference_dut.rx_shape_bad,
                reference_dut.rx_fields_bad,reference_dut.rx_identity_bad,reference_dut.rx_schema2,
                reference_dut.ack_compare_valid,reference_dut.ack_compare_eligible,reference_dut.ack_compare_ok,reference_dut.ack_compare_boot,
                reference_dut.ack_result_valid,reference_dut.ack_result_eligible,reference_dut.ack_result_ok,reference_dut.ack_result_boot,
                reference_dut.remote_pending,reference_dut.remote_sent,reference_dut.remote_applied,reference_dut.remote_fault},
                "packet, shape, identity, state and ACK authority controls exact");
            check(base.dut.expected_payload_word===reference_dut.expected_payload_word,
                "expected identity unaffected even during incomplete PREPARE");
            if(base.dut.tx_state!=0)check(base.dut.reply_kind===reference_dut.reply_kind,
                "owned reply kind exact");
            if(base.dut.ack_compare_eligible)check(base.dut.ack_word_match===reference_dut.ack_word_match,
                "all eligible ACK word comparisons exact");
            if(base.dut.ack_result_eligible)check(base.dut.ack_result_match===reference_dut.ack_result_match,
                "eligible ACK result exact");'''
    if body.count(old) != 1:
        raise RuntimeError("tuple comparison seam changed")
    body = body.replace(old, new)
    old = '            check(base.response_data===ref_response_data,"all response bits remain cycle equivalent, including stalls");'
    assert body.count(old) == 1
    body = body.replace(old, '            if(base.response_valid)' + old.strip())
    old = "                    base.frame_sequence=base.frame_sequence+32'h11990b07;"
    assert body.count(old) == 1
    body = body.replace(old, old + "\n                    base.command_valid=0;base.command_data={8'h00,random_word()};")
    old = "            send_packet(3,0,32'h12345678,70);base.take_plan(plan);base.send_ack(plan,1);"
    assert body.count(old) == 1
    body = body.replace(old, "            base.command_valid=0;\n"
        "            repeat(6)begin @(negedge base.clk);base.command_data={8'h00,random_word()};end\n" + old)
    return body.replace("fixed f3fc9adb", "fixed a4ce0e9ddf")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    run = PROJECT / "tmp/config_payload" / args.name
    run.mkdir(parents=True, exist_ok=False)
    manifest = PROJECT / "SOURCE_MANIFEST.json"
    includes = [PROJECT / item for item in json.loads(manifest.read_text())["include_dirs"]]
    sources = [PROJECT / "src_fpga/rtl" / name for name in
               ("mono_config_legacy_scan_v1.v", "mono_config_scan_v2.v", "mono_config_engine_v2.v")]
    template = HERE / "tb_timing_config_control.sv"
    bench = run / "tb_timing_config_payload.sv"
    bench.write_text(adapt_bench(template.read_text()), newline="\n")
    baselines = []

    def frozen(path):
        body = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=REPO)
        baselines.append({"commit": BASE, "path": path, "sha256": hashlib.sha256(body).hexdigest()})
        return body.decode().replace("\r\n", "\n")

    reference_text, count = re.subn(r"\bmodule\s+mono_config_engine_v2\b",
                                    "module timing_config_engine_reference", frozen(BASE_ENGINE))
    if count != 1:
        raise RuntimeError("baseline engine identity did not match")
    reference = run / "timing_config_engine_reference.v"
    reference.write_text(reference_text, newline="\n")
    base_text = frozen(BASE_BENCH)
    replacements = {
        "module tb_mono_config_ack_pipeline;":
            "module timing_config_base #(parameter integer TRUSTED_COMMANDS=0)(output reg done=0);",
        "mono_config_engine_v2 #(.V2_SUPPORTED_MODES":
            "mono_config_engine_v2 #(.TRUSTED_COMMANDS(TRUSTED_COMMANDS),.V2_SUPPORTED_MODES",
        "$finish;": "done=1;",
    }
    for old, new in replacements.items():
        if base_text.count(old) != 1:
            raise RuntimeError("fixed ACK fixture transformation did not match: " + old)
        base_text = base_text.replace(old, new)
    base_bench = run / "timing_config_base.sv"
    base_bench.write_text(base_text, newline="\n")
    headers = [path for directory in includes for path in directory.glob("*.vh")]
    inputs = sources + [bench, template, manifest, Path(__file__)] + headers
    identity = [{"path": str(path), "sha256": sha(path)} for path in inputs]
    result = {"status": "IN_PROGRESS", "inputs": identity, "baseline": baselines,
              "modelsim_bin": str(args.modelsim_bin), "synthesis": "NOT_RUN",
              "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN"}

    def execute(exe, words):
        completed = subprocess.run([str(args.modelsim_bin / exe)] + list(map(str, words)), cwd=run,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-10000:])

    try:
        execute("vmap.exe", ["-c"])
        execute("vlib.exe", ["work"])
        execute("vmap.exe", ["work", "work"])
        include_args = ["+incdir+" + str(path) for path in includes]
        execute("vlog.exe", ["-quiet", "-l", "rtl.log"] + include_args + sources + [reference])
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log"] + include_args + [base_bench, bench])
        execute("vsim.exe", ["-c", "work.tb_timing_config_control", "-l", "run.log",
                             "-do", "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "run.log").read_text()
        if "RESULT: PASS timing_config_control_all" not in body:
            raise RuntimeError(body[-10000:])
        for name in ("rtl.log", "bench.log", "run.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError("unclassified diagnostic in " + name)
        for row in identity:
            if Path(row["path"]) != manifest and sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("input changed during simulation: " + row["path"])
        result["status"] = "PASS"
        result["metrics"] = [line.strip("# ") for line in body.splitlines() if "RESULT: PASS" in line]
        print("\n".join(result["metrics"]))
    except Exception as error:
        result["status"] = "FAIL"
        result["error"] = str(error)
        raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Results:", run / "RESULTS.json")


if __name__ == "__main__":
    main()
