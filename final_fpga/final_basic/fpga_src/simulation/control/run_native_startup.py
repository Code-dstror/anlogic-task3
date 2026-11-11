"""Native startup matrix with exact top forwarding extraction and frozen negative controls."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = "f3fc9adb5462ea91b50886be6dfa23449eec4d74"
ORIGIN = "refactor/hdr_jpeg/src_fpga/rtl/"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exactly(pattern, body):
    found = re.findall(pattern, body, re.S)
    if len(found) != 1:
        raise RuntimeError(f"expected one source block for {pattern!r}, got {len(found)}")
    return found[0]


def ports(source):
    start = re.search(r"\bmodule\s+\w+\s*\(", source).end()
    header = source[start:source.index(");", start)]
    header = re.sub(r"//[^\n]*", "", header)
    result = []
    direction, width = None, None
    for item in header.split(","):
        item = item.strip()
        match = re.fullmatch(r"(input|output)\s+wire\s*(\[[^]]+\])?\s*(\w+)", item)
        if match:
            direction, width, name = match.groups()
        elif re.fullmatch(r"\w+", item) and direction:
            name = item
        else:
            raise RuntimeError("unparsed native port: " + item)
        result.append((direction, width, name))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    run = PROJECT / "tmp/native_startup" / args.name
    run.mkdir(parents=True, exist_ok=False)
    rtl = PROJECT / "src_fpga/rtl"
    baseline = []

    def frozen(name):
        raw = subprocess.check_output(["git", "show", f"{BASE}:{ORIGIN}{name}"], cwd=REPO)
        baseline.append({"commit": BASE, "path": ORIGIN + name, "sha256": hashlib.sha256(raw).hexdigest()})
        return raw.decode().replace("\r\n", "\n")

    current_supervisor = (rtl / "c2h_link_supervisor.v").read_text()
    current_top = (rtl / "anlogic2026.v").read_text()
    current_native = (rtl / "c2h_native_rx_transport.v").read_text()
    old_supervisor, old_top, old_native = map(frozen, ("c2h_link_supervisor.v", "anlogic2026.v", "c2h_native_rx_transport.v"))
    endpoint = (rtl / "c2h_pcie_endpoint.v").read_text()
    store = (rtl / "ddr3_jpeg_store.v").read_text()
    ownership = exactly(r"(always\s*@\(posedge o_user_clk or negedge i_ownership_reset_n\)\s*begin.*?\n\s*end)\b", endpoint)
    store_forward = exactly(r"(assign\s+o_stream_recovery_required\s*=.*?;)", store)
    extraction = {"ownership_reset": ownership, "store_output_expression": store_forward, "forwarding": {}}
    generated = []
    for kind, body in (("fixed", current_supervisor), ("legacy", old_supervisor)):
        for initial in (0, 1):
            name = f"startup_supervisor_{kind}_{initial}"
            text = re.sub(r"\bmodule\s+c2h_link_supervisor\b", "module " + name, body, count=1)
            text, count = re.subn(r"(reg\s*\[1:0\]\s*incident_hold_pipe\s*=\s*)[^;]+",
                                  rf"\g<1>2'b{initial}{initial}", text)
            if count != 1:
                raise RuntimeError("incident initialization variation did not match")
            path = run / (name + ".v"); path.write_text(text, newline="\n"); generated.append(path)
    for kind, top, supervisor_kind in (("fixed", current_top, "fixed"),
                                       ("legacy", old_top, "legacy"),
                                       ("supervisor_only", old_top, "fixed")):
        watcher = exactly(r"(c2h_link_supervisor\s+u_memory_owner_watch\s*\(.*?\);)", top)
        dfi = exactly(r"(always\s*@\(posedge dfi_clk or posedge memory_fault_user\)\s*begin.*?\n\s*end)\b", top)
        after = top[top.index(watcher) + len(watcher):]
        returned = exactly(r"(always\s*@\(posedge user_clk or negedge user_rst_n\)\s*begin\s*if\(!user_rst_n\)product_fault_user<=0;.*?\n\s*end)\b", after)
        product_reset = exactly(r"(reset_release_sync\s+u_product_dfi_reset\s*\(.*?\);)", top)
        memory_arg = exactly(r"\.i_memory_fault\(([^()]+)\)", top)
        qualifier = re.findall(r"wire\s+memory_fault_dfi_active\s*=\s*[^;]+;", top)
        if kind == "fixed" and (memory_arg != "memory_fault_dfi_active" or len(qualifier) != 1):
            raise RuntimeError("candidate top does not contain the reviewed cold-only DFI qualification")
        extraction["forwarding"][kind] = {"watcher": watcher, "dfi": dfi, "returned": returned,
                                            "product_reset": product_reset, "memory_argument": memory_arg,
                                            "qualifier": qualifier}
        branches = []
        for initial in (0, 1):
            branches.append(watcher.replace("c2h_link_supervisor", f"startup_supervisor_{supervisor_kind}_{initial}", 1))
        wrapper = f"""`timescale 1ns/1ps
module startup_forward_{kind} #(parameter integer INITIAL_ONE=1)(
 input wire sys_clk,user_clk,dfi_clk,product_cold_reset_n,ddr_app_ready,ddr_phy_rst_n,
 output wire memory_fault_user,memory_owner_ready,active_memory_fault,product_dfi_reset_n,user_rst_n,
 output wire [1:0] observed_fault_dfi,observed_product_fault);
 reg [1:0] memory_fault_dfi=INITIAL_ONE ? 2'b11 : 2'b00;
 reg [1:0] product_fault_user;
 reg [1:0] ownership_reset_sync;
 wire o_user_clk=user_clk,i_ownership_reset_n=product_cold_reset_n;
 assign user_rst_n=ownership_reset_sync[1];
 {ownership}
 {product_reset}
 generate if(INITIAL_ONE)begin:g_initial_one
 {branches[1]}
 end else begin:g_initial_zero
 {branches[0]}
 end endgenerate
 {dfi}
 {' '.join(qualifier)}
 wire i_memory_fault={memory_arg};
 wire store_stream_recovery_required=0,arbiter_recovery_required=0,o_mask_axi_fault=0;
 wire o_stream_recovery_required;
 {store_forward}
 wire store_recovery=o_stream_recovery_required;
 wire reset_source_fault=0,reset_sink_fault=0,jpeg_cdc_source_fault=0,bridge_fault=0;
 wire record_ordered_fault=0,record_metadata_fault=0,record_source_fault=0;
 {returned}
 assign active_memory_fault=i_memory_fault;
 assign observed_fault_dfi=memory_fault_dfi;
 assign observed_product_fault=product_fault_user;
endmodule
"""
        path = run / (f"startup_forward_{kind}.v"); path.write_text(wrapper, newline="\n"); generated.append(path)
    legacy_path = run / "startup_native_legacy.v"
    legacy_path.write_text(re.sub(r"\bmodule\s+c2h_native_rx_transport\b", "module startup_native_legacy", old_native, count=1), newline="\n")
    generated.append(legacy_path)
    inputs_map = {
        "i_clk": "clk", "i_rst_n": "rst_n", "i_link_up": "link_up", "i_bme": "bme",
        "i_external_fault": "external_fault", "i_cq_data": "cq_data", "i_cq_keep": "cq_keep",
        "i_cq_user": "cq_user", "i_cq_last": "cq_last", "i_cq_valid": "cq_valid",
        "i_cc_ready": "1'b1", "i_record_valid": "record_valid", "i_record_length": "32'd16",
        "i_record_identity": "128'h155a112233445566778899aabbccdd00", "i_rc_valid": "rc_valid",
        "i_axil_awready": "1'b1", "i_axil_wready": "1'b1", "i_axil_arready": "1'b1",
    }
    outputs_map = {"o_cq_ready": "cq_ready", "o_record_ready": "record_ready", "o_quarantine": "quarantine",
                   "o_buffer_armed": "armed", "o_record_cancel": "cancel", "o_observe_state": "",
                   "o_observe_submit": ""}
    probe_parts = []
    for kind, source, module in (("legacy", old_native, "startup_native_legacy"),
                                  ("fixed", current_native, "c2h_native_rx_transport")):
        entries = []
        for direction, width, name in ports(source):
            zero = "1'b0"
            if width:
                hi, lo = map(int, re.findall(r"\d+", width)); zero = f"{hi-lo+1}'d0"
            value = inputs_map.get(name, zero) if direction == "input" else outputs_map.get(name, "")
            entries.append(f".{name}({value})")
        probe_parts.append(f"""{module} dut({', '.join(entries)});
 assign state=dut.state;assign native_fault=dut.fault;assign result_code=dut.result_code;
 assign bound=dut.bound;assign shadow_capacity=dut.shadow_capacity;assign local_bytes=dut.local_bytes;
 assign identity=dut.identity;assign permitted=dut.permitted;
""")
    probe = """`timescale 1ns/1ps
module startup_native_probe #(parameter integer LEGACY=0)(
 input wire clk,rst_n,link_up,bme,external_fault,
 input wire [127:0] cq_data,input wire [3:0] cq_keep,input wire [87:0] cq_user,
 input wire cq_last,cq_valid,record_valid,rc_valid,
 output wire cq_ready,record_ready,quarantine,armed,cancel,
 output wire [3:0] state,output wire native_fault,bound,permitted,
 output wire [31:0] result_code,shadow_capacity,local_bytes,output wire [127:0] identity);
 generate if(LEGACY)begin:g_legacy
""" + probe_parts[0] + "end else begin:g_fixed\n" + probe_parts[1] + "end endgenerate\nendmodule\n"
    probe_path = run / "startup_native_probe.v"; probe_path.write_text(probe, newline="\n"); generated.append(probe_path)
    (run / "EXTRACTED_SOURCE.json").write_text(json.dumps(extraction, indent=2) + "\n")
    sources = [rtl / name for name in ("reset_release_sync.v", "c2h_link_supervisor.v", "c2h_bar_cq.v",
                                       "c2h_native_packetizer.v", "c2h_native_rx_transport.v")]
    bench = HERE / "tb_native_startup.sv"
    manifest = PROJECT / "SOURCE_MANIFEST.json"
    includes = [PROJECT / row for row in json.loads(manifest.read_text())["include_dirs"]]
    headers = [directory / name for directory in includes for name in
               ("pcie_protocol_v1.vh", "c2h_transport_limits.vh") if (directory / name).exists()]
    identity_inputs = sources + [rtl / "anlogic2026.v", rtl / "c2h_pcie_endpoint.v", rtl / "ddr3_jpeg_store.v",
                                 bench, Path(__file__)] + headers
    identity = [{"path": str(path), "sha256": sha(path)} for path in identity_inputs]
    result = {"status": "IN_PROGRESS", "inputs": identity, "baseline": baseline,
              "scope": "REAL_NATIVE_BAR_PACKETIZER_WITH_EXACT_TOP_FORWARDING_NO_DDR_PHY_OR_PAYLOAD",
              "modelsim_bin": str(args.modelsim_bin), "synthesis": "NOT_RUN", "physical": "NOT_RUN",
              "timing": "NOT_RUN", "board": "NOT_RUN"}

    def execute(exe, words):
        completed = subprocess.run([str(args.modelsim_bin / exe)] + list(map(str, words)), cwd=run,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-10000:])

    try:
        execute("vmap.exe", ["-c"]); execute("vlib.exe", ["work"]); execute("vmap.exe", ["work", "work"])
        include_args = ["+incdir+" + str(path) for path in includes]
        execute("vlog.exe", ["-quiet", "-l", "rtl.log"] + include_args + sources + generated)
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log", bench])
        execute("vsim.exe", ["-c", "work.tb_native_startup", "-l", "run.log",
                             "-do", "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "run.log").read_text()
        if "RESULT: PASS native_startup_all" not in body:
            raise RuntimeError(body[-10000:])
        for name in ("rtl.log", "bench.log", "run.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError("unclassified diagnostic in " + name)
        for row in identity:
            if sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("source changed during native test: " + row["path"])
        result["status"] = "PASS"
        result["metrics"] = [line.strip("# ") for line in body.splitlines()
                             if "RESULT:" in line or "CASE PASS" in line]
        result["generated"] = [{"path": str(path), "sha256": sha(path)} for path in generated]
        print("\n".join(result["metrics"]))
    except Exception as error:
        result["status"] = "FAIL"; result["error"] = str(error); raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Results:", run / "RESULTS.json")


if __name__ == "__main__":
    main()
