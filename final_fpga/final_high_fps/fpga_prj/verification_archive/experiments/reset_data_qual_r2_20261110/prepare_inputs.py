"""Freeze the two private RAW source variants and their public compilation inputs."""

from hashlib import sha256
import json
from pathlib import Path
import subprocess


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REPO = PROJECT.parents[1]
BASE_COMMIT = "eade457d7477110605f90eb5abc08420d8936642"
RUN_ROOT = PROJECT / "tmp/reset_data_qual_r2_20261110"
LEAF = "private_raw_isp_borrow4.v"
COMMON = (
    "reset_release_sync.v",
    "reset_release_sync_data.v",
    "hdr_pair_product_abort_drain4.v",
    "camera_rgb_native_fixed1080_borrow4.v",
)


def frozen_file(path):
    return subprocess.check_output(
        ["git", "show", f"{BASE_COMMIT}:{path.relative_to(REPO).as_posix()}"], cwd=REPO,
    )


def frozen_rtl(names):
    checksums = json.loads(frozen_file(PROJECT / "docs/SOURCE_SEAL.json"))["production_inputs"]
    sources = {}
    for name in names:
        relative = f"src_fpga/rtl/{name}"
        data = frozen_file(PROJECT / relative)
        if sha256(data).hexdigest() != checksums[relative]:
            raise ValueError(f"Frozen RTL does not match the production seal: {relative}")
        sources[name] = data
    return sources


def candidate_source(baseline):
    source = baseline.decode("utf-8")
    old_release = (
        "    wire pixel_reset_n;\n"
        "    reset_release_sync #(.FALLING_RELEASE(1)) u_pixel_reset"
        "(.i_clk(i_pixel_clk),.i_async_rst_n(i_pixel_rst_n),.o_rst_n(pixel_reset_n));\n"
    )
    new_release = (
        "    wire pixel_reset_n, pixel_data_reset_n;\n"
        "    // Keep the falling ASR release and qualify same-domain handshakes\n"
        "    // from the existing rising release stage. The first sample is unchanged.\n"
        "    reset_release_sync_data #(.DATA_RESET_COPIES(0),.FALLING_RELEASE(1)) u_pixel_reset(\n"
        "        .i_clk(i_pixel_clk),.i_async_rst_n(i_pixel_rst_n),\n"
        "        .o_rst_n(pixel_reset_n),.o_data_rst_n(pixel_data_reset_n));\n"
    )
    if source.count(old_release) != 1:
        raise ValueError("Unexpected reset source")
    source = source.replace(old_release, new_release)
    for port in ("s_raw_source_ready", "s_raw_ready", "o_payload_enable"):
        old = f"    assign {port}=pixel_reset_n &&"
        if source.count(old) != 1:
            raise ValueError(f"Unexpected qualification for {port}")
        source = source.replace(old, f"    assign {port}=pixel_data_reset_n &&")
    return source.encode("utf-8")


def write_exact(path, data):
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError(f"Existing frozen input differs: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)


def prepare():
    sources = frozen_rtl((LEAF, *COMMON))
    variants = {"baseline": sources[LEAF], "candidate": candidate_source(sources[LEAF])}
    root = RUN_ROOT / "inputs"
    common_entries = []
    for name in COMMON:
        path = root / "common" / name
        write_exact(path, sources[name])
        common_entries.append({
            "path": path.relative_to(PROJECT).as_posix(),
            "sha256": sha256(sources[name]).hexdigest(),
        })
    variants_entries = {}
    for name, leaf in variants.items():
        path = root / name / LEAF
        write_exact(path, leaf)
        variants_entries[name] = [*common_entries, {
            "path": path.relative_to(PROJECT).as_posix(), "sha256": sha256(leaf).hexdigest(),
        }]
    manifest = {
        "schema": 1,
        "project_root": PROJECT.relative_to(REPO).as_posix(),
        "baseline_commit": BASE_COMMIT,
        "top": "private_raw_isp_borrow4",
        "compile_mode": "Verilog",
        "td_simulation_model_dependencies": [],
        "legal_profile": {
            "EXTERNAL_ISP_ENABLE": 1,
            "ORIGINAL_SYNC_CLEAR_ENABLE": 1,
            "RAW_SAMPLE_BITS": 14,
            "BASE_WIDTH": 16,
            "BASE_HEIGHT": 4,
            "MAX_WIDTH": 32,
            "MAX_HEIGHT": 8,
        },
        "variants": variants_entries,
    }
    write_exact(HERE / "OPAQUE_SOURCES.json", (json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
    declaration = sources[LEAF].decode("utf-8").split("module private_raw_isp_borrow4", 1)[1].split("\n);", 1)[0]
    write_exact(HERE / "PORTS.vh", (
        "// Public declaration only. Compile the opaque module instead.\n"
        "module private_raw_isp_borrow4" + declaration + "\n);\n"
    ).encode("utf-8"))
    return root


if __name__ == "__main__":
    print(prepare())
