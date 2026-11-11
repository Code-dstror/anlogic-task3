"""Official gray MAC: actual two-slot block, parent integration and frozen R1 transactions."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = "d86edbed408230828e6cd8a887bceec80c242307"
BASE_PATH = "refactor/hdr_jpeg_timing/src_fpga/rtl/preprocess_live_f21_pipeline4.v"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ports(source):
    start = source.index("module preprocess_live_f21_pipeline4")
    start += re.search(r"\)\s*\(", source[start:]).end()
    header = re.sub(r"//[^\n]*", "", source[start:source.index(");", start)])
    direction, width = None, None
    out = []
    for item in header.split(","):
        item = item.strip()
        match = re.fullmatch(r"(input|output)\s+(?:wire|reg)\s*(\[[^]]+\])?\s*(\w+)", item)
        if match:
            direction, width, name = match.groups()
        elif re.fullmatch(r"\w+", item) and direction:
            name = item
        else:
            raise RuntimeError("unparsed parent port: " + item)
        out.append((direction, width, name))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    run = PROJECT / "tmp/r3_gray_fifo" / args.name
    run.mkdir(parents=True, exist_ok=False)
    parent = PROJECT / "src_fpga/rtl/preprocess_live_f21_pipeline4.v"
    source = parent.read_text()
    match = re.search(r"// R3_GRAY_READY_BOUNDARY_BEGIN(.*?)// R3_GRAY_READY_BOUNDARY_END", source, re.S)
    if not match or "(gray_fifo_count!=0)" not in source:
        raise RuntimeError("actual approved boundary/pending term is missing")
    block = match[1]
    if "assign raw_gray_ready=gray_fifo_count<2'd2;" not in block:
        raise RuntimeError("producer READY is not solely the local count Q")
    raw = subprocess.check_output(["git", "show", f"{BASE}:{BASE_PATH}"], cwd=REPO)
    reference = raw.decode().replace("\r\n", "\n").replace("module preprocess_live_f21_pipeline4", "module r3_gray_r1_pipeline", 1)
    reference_path = run / "r3_gray_r1_pipeline.v"
    reference_path.write_text(reference, newline="\n")
    inputs_map = {
        "clk": "clk", "rst_n": "rst_n", "cfg_width": "13'd64", "cfg_height": "13'd8",
        "cfg_schema2": "1'b1", "m_f21_ready": "hook_gate&&return_ready",
        "s_f21_valid": "hook_valid&&hook_gate", "s_f21_rgb": "hook_rgb", "s_f21_y": "hook_y",
        "s_f21_sof": "hook_sof", "s_f21_eol": "hook_eol", "s_valid": "source_valid",
        "s_data": "source_rgb", "s_sof": "source_sof", "s_eol": "source_eol",
        "s_frame_done": "source_done", "s_frame_error": "source_error", "m_ready": "output_ready",
        "i_he_history_rst_n": "rst_n", "i_window_ready": "1'b1", "f22_record_ready": "1'b1", "f23_record_ready": "1'b1",
    }
    outputs_map = {
        "s_ready": "source_ready", "m_f21_valid": "hook_valid", "m_f21_rgb": "hook_rgb", "m_f21_y": "hook_y",
        "m_f21_sof": "hook_sof", "m_f21_eol": "hook_eol", "m_f21_last": "hook_last", "s_f21_ready": "return_ready",
        "m_valid": "output_valid", "m_data": "output_rgb", "m_luma": "output_y", "m_sof": "output_sof", "m_eol": "output_eol",
        "m_frame_done": "frame_done", "m_frame_error": "frame_error", "o_presented_valid": "pending", "o_input_owned": "owned",
        "o_neutral_valid": "neutral_valid", "o_neutral_rgb": "neutral_rgb", "o_neutral_luma": "neutral_y",
        "o_neutral_sof": "neutral_sof", "o_neutral_eol": "neutral_eol", "o_neutral_eof": "neutral_last",
    }
    connections = []
    for direction, width, name in ports(source):
        zero = "1'b0"
        if width:
            hi, lo = map(int, re.findall(r"\d+", width)); zero = f"{hi-lo+1}'d0"
        value = inputs_map.get(name, zero) if direction == "input" else outputs_map.get(name, "")
        connections.append(f".{name}({value})")
    parameters = "#(.MAX_WIDTH(64),.MAX_HEIGHT(8),.SHARED_Y_PROFILE(1),.GRAY_ONLY_ENABLE(1),.NEUTRAL_TAP_ENABLE(1))"
    probe = """`timescale 1ns/1ps
module r3_gray_parent_probe #(parameter integer REFERENCE=0)(
 input wire clk,rst_n,source_valid,source_sof,source_eol,source_done,source_error,hook_gate,output_ready,
 input wire [95:0] source_rgb,output wire source_ready,hook_valid,hook_ready,hook_sof,hook_eol,hook_last,
 output wire [95:0] hook_rgb,output wire [31:0] hook_y,
 output wire output_valid,output_sof,output_eol,frame_done,frame_error,pending,owned,
 output wire [95:0] output_rgb,output wire [31:0] output_y,
 output wire neutral_valid,neutral_sof,neutral_eol,neutral_last,
 output wire [95:0] neutral_rgb,output wire [31:0] neutral_y,output wire [1:0] fifo_count);
 wire return_ready;assign hook_ready=hook_gate&&return_ready;
 generate if(REFERENCE)begin:g_reference
 r3_gray_r1_pipeline """ + parameters + " dut(" + ",".join(connections) + """);
 assign fifo_count=0;
 end else begin:g_candidate
 preprocess_live_f21_pipeline4 """ + parameters + " dut(" + ",".join(connections) + """);
 assign fifo_count=dut.gray_fifo_count;
 end endgenerate
endmodule
module r3_gray_boundary_probe(
 input wire clk,rst_n,cancel,s_valid,s_sof,s_eol,g_down_ready,input wire [95:0] s_data,
 output wire g_ready,g_valid,g_sof,g_eol,output wire [95:0] g_original,output wire [31:0] g_luma,
 output wire pending);
 localparam integer MAX_WIDTH=64,MAX_HEIGHT=8,NEUTRAL_TAP_ENABLE=1;
 wire pipeline_rst_n=rst_n,active=1,input_complete=0,malformed=0,premature_done=0;
 wire [12:0] width=64,height=8;wire gray_pending;
""" + block + "\nassign pending=gray_fifo_count!=0||gray_pending;\nendmodule\n"
    probe_path = run / "r3_gray_actual_probes.v"
    probe_path.write_text(probe, newline="\n")
    (run / "r3_gray_extracted_boundary.json").write_text(json.dumps({"source": str(parent), "sha256": sha(parent), "block": block}, indent=2) + "\n")
    fixture = json.loads((PROJECT / "src_fpga/simulation/MAIN_FIXTURE.json").read_text())
    models = [args.td_root / p for p in fixture["models"]]
    macros = [PROJECT / row["path"] for row in fixture["groups"]["mac_compile.args"]]
    includes = [PROJECT / p for p in fixture["include_dirs"]]
    gsr = args.td_root / "sim_release/ph1/ph1_phy_gsr.v"
    common = [PROJECT / "src_fpga/rtl" / name for name in ("preprocess_gray_pending4.v", "preprocess_stream_pending2.v")]
    bench = HERE / "r3_gray_fifo_tb.sv"
    inputs = models + macros + [gsr, parent, bench, Path(__file__)] + common
    inputs += [p for directory in includes for p in directory.glob('*.vh')]
    identity = [{"path": str(p), "sha256": sha(p)} for p in inputs]
    result = {"status": "IN_PROGRESS", "inputs": identity,
              "baseline": {"commit": BASE, "path": BASE_PATH, "sha256": hashlib.sha256(raw).hexdigest()},
              "td_root": str(args.td_root), "scope": "REAL_PARENT_GRAY_ONLY_INTEGRATION_AND_EXTRACTED_ACTUAL_BUFFER_OFFICIAL_MAC",
              "synthesis": "NOT_RUN", "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN"}

    def execute(exe, words):
        completed = subprocess.run([str(args.modelsim_bin / exe)] + list(map(str, words)), cwd=run,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-10000:])

    try:
        execute("vmap.exe", ["-c"])
        for lib in ("work", "ph1"):
            execute("vlib.exe", [lib]); execute("vmap.exe", [lib, lib])
        execute("vlog.exe", ["-quiet", "-work", "ph1", "-l", "models.log"] + models)
        inc = ["+incdir+" + str(p) for p in includes]
        execute("vlog.exe", ["-quiet", "+define+PH1", "-l", "rtl.log"] + inc + [gsr] + macros + common + [parent, reference_path, probe_path])
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log", bench])
        execute("vsim.exe", ["-c", "-L", "ph1", "work.PH1_PHY_GSR", "ph1.glbl", "work.r3_gray_fifo_tb",
                             "-l", "run.log", "-do", "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "run.log").read_text()
        if "RESULT: PASS r3_gray_fifo_all" not in body or re.search(r"\*\*\s+(Error|Fatal):", body):
            raise RuntimeError(body[-10000:])
        warnings = []
        for name in ("models.log", "rtl.log", "bench.log", "run.log"):
            for line in (run / name).read_text().splitlines():
                if "** Warning:" not in line:continue
                accepted = "fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v(466)" in line and (
                    re.search(r"\(vopt-2685\).*Too few port connections for 'u_siou'.  Expected 51, found 39", line) or
                    re.search(r"\(vopt-2718\).*Missing connection for port '(cco|cpo|cyo|cxabo|cxbo|cxao|cci|cpi|cyi|cxabi|cxbi|cxai)'", line))
                if not accepted:raise RuntimeError("unclassified diagnostic: " + line)
                warnings.append(line)
        for row in identity:
            if sha(Path(row["path"])) != row["sha256"]:raise RuntimeError("input changed during gray check: " + row["path"])
        result["status"] = "PASS";result["accepted_vendor_warnings"] = sorted(set(warnings))
        result["metrics"] = [line.strip("# ") for line in body.splitlines() if "RESULT: PASS" in line]
        print("\n".join(result["metrics"]))
    except Exception as error:
        result["status"] = "FAIL";result["error"] = str(error);raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Results:", run / "RESULTS.json")


if __name__ == "__main__":main()
