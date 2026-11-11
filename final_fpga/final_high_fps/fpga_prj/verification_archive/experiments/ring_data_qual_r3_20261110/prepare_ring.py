"""Freeze the DFI ring experiment and its public simulation interface."""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import sys


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REPO = PROJECT.parents[1]
PIX_EXPERIMENT = HERE.parent / "reset_data_qual_r2_20261110"
sys.path.insert(0, str(PIX_EXPERIMENT))
from prepare_inputs import BASE_COMMIT, frozen_file, frozen_rtl, write_exact


RUN_ROOT = PROJECT / "tmp/ring_data_qual_r3_20261110"
LEAF = "jpeg_frame_ring.v"
DDR = "ddr3_jpeg_store.v"
BOUNDARY = "jpeg_ring_reset_boundary.v"
COMMON = ("reset_release_sync.v", "reset_release_sync_data.v", "jpeg_ring_cold_bank.v", "td_sdp_ram.v")
MODELS = {
    "sim_release/common/al_phy_glbl.v": "c194f5335b54a6d707a8b633b8f4d3a171e52006337600f7433379b11fb3b2ff",
    "sim_release/ph1/ph1_logic_dram.v": "0b4ab2c3ac73aad28e16ab6a0a6af57a62ae89db2c3e58ac85605cc9e98b88cd",
}
GSR = "sim_release/ph1/ph1_phy_gsr.v"
GSR_SHA256 = "7c8d97c4593ef132de32c2d13cae01cc77424f5f0e40137312574d47a1a964ed"


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"Unexpected occurrence count for {old}")
    return source.replace(old, new)


def ring_candidate(source):
    source = replace_once(
        source, "    parameter integer CAMERA_COUNT = 2\n",
        "    parameter integer CAMERA_COUNT = 2,\n"
        "    parameter integer SEPARATE_DATA_RESET = 0\n",
    )
    source = replace_once(
        source, "    output wire [27:0] o_rsp_mask_tail_base\n",
        "    output wire [27:0] o_rsp_mask_tail_base,\n"
        "    // Optional qualification from the same DFI rising release chain.\n"
        "    input wire i_data_reset_n\n",
    )
    source = replace_once(
        source, "    wire source_fire=i_jpeg_tvalid && o_jpeg_tready;\n",
        "    wire data_reset_n=SEPARATE_DATA_RESET!=0 ? i_data_reset_n : i_rst_n;\n"
        "    wire source_fire=i_jpeg_tvalid && o_jpeg_tready;\n",
    )
    for port in ("o_start_ready", "o_jpeg_tready", "o_result_ready", "o_write_quiescent"):
        source = replace_once(source, f"    assign {port}=i_rst_n", f"    assign {port}=data_reset_n")
    source = replace_once(
        source, "        !o_write_result_valid&&fifo_sr_done&&fifo_rr_done&&staged==0",
        "        !o_write_result_valid&&staged==0",
    )
    return replace_once(
        source, "                         ws==W_IDLE && allocation>=0 && fifo_sr_done && fifo_rr_done && !fifo_valid",
        "                         ws==W_IDLE && allocation>=0 && !fifo_valid",
    )


def ddr_candidate(source):
    source = replace_once(
        source, "    wire record_owner_reset_n;\n",
        "    wire record_owner_reset_n, record_owner_data_reset_n;\n",
    )
    source = replace_once(
        source, "    reset_release_sync #(.FALLING_RELEASE(1)) u_record_owner_reset(.i_clk(o_dfi_clk),\n"
        "        .i_async_rst_n(i_record_ownership_rst_n),.o_rst_n(record_owner_reset_n));\n",
        "    reset_release_sync_data #(.DATA_RESET_COPIES(0),.FALLING_RELEASE(1)) u_record_owner_reset(\n"
        "        .i_clk(o_dfi_clk),.i_async_rst_n(i_record_ownership_rst_n),\n"
        "        .o_rst_n(record_owner_reset_n),.o_data_rst_n(record_owner_data_reset_n));\n",
    )
    source = replace_once(
        source, "        .CAMERA_COUNT(JPEG_CAMERA_COUNT)) u_store (\n",
        "        .CAMERA_COUNT(JPEG_CAMERA_COUNT),.SEPARATE_DATA_RESET(1)) u_store (\n",
    )
    return replace_once(
        source, "        .i_clk(o_dfi_clk), .i_rst_n(record_owner_reset_n), .i_ddr_ready(o_app_ready&&!i_memory_fault),\n",
        "        .i_clk(o_dfi_clk), .i_rst_n(record_owner_reset_n), .i_data_reset_n(record_owner_data_reset_n),\n"
        "        .i_ddr_ready(o_app_ready&&!i_memory_fault),\n",
    )


def declarations(source):
    header = source.split("module jpeg_frame_ring", 1)[1].split("\n);", 1)[0]
    parameters, ports = header.split(") (", 1)
    parameter_names = re.findall(r"\bparameter\s+(?:integer|\[\d+:\d+\])\s+(\w+)\s*=", parameters)
    port_names = []
    for line in ports.splitlines():
        statement = line.split("//", 1)[0].strip().rstrip(",")
        if not statement:
            continue
        match = re.fullmatch(r"(?:input|output)\s+(?:reg|wire)\s*(?:\[\d+:\d+\])?\s*(.+)", statement)
        if match is None:
            raise ValueError(f"Unexpected port declaration: {statement}")
        names = [name.strip() for name in match[1].split(",")]
        if not all(re.fullmatch(r"\w+", name) for name in names):
            raise ValueError(f"Unexpected port names: {statement}")
        port_names.extend(names)
    header = header.replace("output reg ", "output wire ").replace("input wire i_rst_n,", "input wire i_cold_rst_n,")
    return "module jpeg_ring_reset_boundary" + header + "\n);\n", parameter_names, port_names


def boundary_source(header, parameters, ports, candidate):
    connections = [f".{name}({name})" for name in parameters]
    port_connections = [f".{name}({'owner_reset_n' if name == 'i_rst_n' else name})" for name in ports]
    if candidate:
        connections.append(".SEPARATE_DATA_RESET(1)")
        port_connections.append(".i_data_reset_n(owner_data_reset_n)")
        reset = (
            "    wire owner_data_reset_n;\n"
            "    reset_release_sync_data #(.DATA_RESET_COPIES(0),.FALLING_RELEASE(1)) u_record_owner_reset (\n"
            "        .i_clk(i_clk),.i_async_rst_n(i_cold_rst_n),\n"
            "        .o_rst_n(owner_reset_n),.o_data_rst_n(owner_data_reset_n));\n"
        )
    else:
        reset = (
            "    reset_release_sync #(.FALLING_RELEASE(1)) u_record_owner_reset (\n"
            "        .i_clk(i_clk),.i_async_rst_n(i_cold_rst_n),.o_rst_n(owner_reset_n));\n"
        )
    return (
        "`timescale 1ns/1ps\n" + header + "    wire owner_reset_n;\n" + reset +
        "    jpeg_frame_ring #(\n        " + ",\n        ".join(connections) + "\n    ) u_store (\n        " +
        ",\n        ".join(port_connections) + "\n    );\nendmodule\n"
    ).encode("utf-8")


def model_entry(td_root, name, expected):
    if sha256((td_root / name).read_bytes()).hexdigest() != expected:
        raise ValueError(f"Unexpected TD simulation model: {name}")
    return {"path": name, "sha256": expected}


def prepare(td_root):
    sources = frozen_rtl((LEAF, DDR, *COMMON))
    root = RUN_ROOT / "inputs"
    header, parameters, ports = declarations(sources[LEAF].decode("utf-8"))
    common = []
    for name in COMMON:
        target = root / "common" / name
        write_exact(target, sources[name])
        common.append({"path": target.relative_to(PROJECT).as_posix(), "sha256": sha256(sources[name]).hexdigest()})
    variants = {}
    for arm in ("baseline", "candidate"):
        candidate = arm == "candidate"
        leaf = ring_candidate(sources[LEAF].decode("utf-8")).encode("utf-8") if candidate else sources[LEAF]
        ddr = ddr_candidate(sources[DDR].decode("utf-8")).encode("utf-8") if candidate else sources[DDR]
        write_exact(root / arm / DDR, ddr)
        variants[arm] = list(common)
        for name, data in ((LEAF, leaf), (BOUNDARY, boundary_source(header, parameters, ports, candidate))):
            target = root / arm / name
            write_exact(target, data)
            variants[arm].append({"path": target.relative_to(PROJECT).as_posix(), "sha256": sha256(data).hexdigest()})
    manifest = {
        "schema": 1,
        "project_root": PROJECT.relative_to(REPO).as_posix(),
        "baseline_commit": BASE_COMMIT,
        "dut": "jpeg_ring_reset_boundary",
        "td_version": "6.2.3.210850",
        "compile_mode": "Verilog",
        "models_library": "ph1",
        "model_sources": [model_entry(td_root, name, expected) for name, expected in MODELS.items()],
        "td_work_sources": [model_entry(td_root, GSR, GSR_SHA256)],
        "rom_initializers": [],
        "globals": ["work.PH1_PHY_GSR", "ph1.glbl"],
        "legal_profile": {
            "CAMERA_COUNT": 2,
            "SLOT_BYTES": 16777216,
            "WRITE_RESULT_ENABLE": 1,
            "WRITE_TAG_ENABLE": 1,
            "MASK_ENABLE": 0,
        },
        "variants": variants,
    }
    write_exact(HERE / "OPAQUE_SOURCES.json", (json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
    write_exact(HERE / "PORTS.vh", ("// Public declaration only. Compile the opaque boundary instead.\n" + header).encode("utf-8"))
    return root


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--td-root", type=Path, required=True)
    args = parser.parse_args()
    print(prepare(args.td_root.resolve()))
