"""Materialize a source-only RAW product overlay on the published N2 policy."""

import argparse
from difflib import unified_diff
from hashlib import sha256
import json
from pathlib import Path
import subprocess

from dual_host import pcie_protocol_v1 as p
from dual_host import stereo_control_v1 as stereo
from raw_video_constants import (
    PCIE_RAW_VIDEO_ACTIVE_PRODUCT, PCIE_RAW_VIDEO_PRODUCT_JPEG,
    PCIE_RAW_VIDEO_PRODUCT_RAW, PCIE_RAW_VIDEO_REQUEST_PRODUCT,
)
from work.anlogic2026.RK3576.linux.video.r5_video import dual_r3_driver


REPO = Path(__file__).resolve().parents[4]
BASE = "e081883222a7cd342d6d1ffcc5836a443334fe11"
MATCHED_SOURCE = Path("deliverables/DUAL_SDR_seed51_首轮故障分析与修复规划_20261101"
                      "/field_originals/matched_driver_sources")
PYTHON_POLICY = Path("linux/dma_c2h_candidate/c2h_legacy_policy.py")
PUBLISHED_POLICY = Path("work/anlogic2026/RK3576/snapshots/dual_sdr/peer") / PYTHON_POLICY
PUBLISHED_POLICY_SHA256 = "c561609a270bd57e4be341b1e7425544002e5e4ef162f600f5743ddcb8b83779"
# The compiled source records from the matched stereo-N2 6.1.99 KO receipt.
COMPILED_N2_SHA256 = {
    "Makefile": "26d41a41a97c6caa8c14b83501d1e5c72dde60a6dc6dc8e4f73218186c9d9a9c",
    "ph1a_c2h.c": "41e75255d67803a54d97d46972eb1108f85e6b0b9f2d0f6b6a78037764f4d45e",
    "c2h_legacy_policy.h": "db887f2c5b81398d1eb2d88c8c88aa7a8d2febe59bb264333c0f4a98471412f5",
    "c2h_hw_abi.h": "94c1ec43870c8afede09e66c391a2f447c3eb09060b8ba4ac746e63052a33267",
    "c2h_uapi.h": "163479e9b6832f303da6be288891bf424a48d0435c493c8588162de4b9b670fe",
    "c2h_lifecycle.h": "20ba8a963e5942d640ef221b263ee6044901088ed2d42c412350c122c30ced8f",
}
GUARDED_STATUS = (p.PCIE_STATUS_C2H_RUNNING | p.PCIE_STATUS_TX_BUSY
                  | p.PCIE_STATUS_SOURCE_BUSY | p.PCIE_STATUS_SESSION_ARMED)


def digest(data):
    return sha256(data).hexdigest()


def replace_once(source, anchor, replacement):
    if source.count(anchor) != 1:
        raise ValueError(f"N2 policy anchor changed: {anchor.strip()}")
    return source.replace(anchor, replacement, 1)


def derive_sources(repo=REPO):
    python_before = (repo / PUBLISHED_POLICY).read_bytes()
    if digest(python_before) != PUBLISHED_POLICY_SHA256:
        raise ValueError("published N2 Python policy differs")

    # The matched target build archived its compiled C and headers. The
    # receipt identifies the unchanged Makefile by its e081 blob digest.
    n2 = {name: (repo / MATCHED_SOURCE / name).read_bytes()
          for name in COMPILED_N2_SHA256 if name != "Makefile"}
    n2["Makefile"] = subprocess.check_output(
        ["git", "show", f"{BASE}:linux/dma_c2h_candidate/Makefile"], cwd=repo)
    if any(digest(n2[name]) != expected for name, expected in COMPILED_N2_SHA256.items()):
        raise ValueError("derived N2 files differ from the matched target KO source receipt")
    candidate = dict(n2)
    header = n2["c2h_legacy_policy.h"].decode("ascii")
    for predicate, offsets in (
        ("readable", (PCIE_RAW_VIDEO_REQUEST_PRODUCT, PCIE_RAW_VIDEO_ACTIVE_PRODUCT)),
        ("writable", (PCIE_RAW_VIDEO_REQUEST_PRODUCT,)),
        ("record_write", (PCIE_RAW_VIDEO_REQUEST_PRODUCT,)),
    ):
        anchor = f"static inline bool c2h_legacy_{predicate}(u32 offset)\n{{\n\tswitch (offset) {{\n"
        cases = "".join(f"\tcase 0x{offset:x}U:\n" for offset in offsets)
        header = replace_once(header, anchor, anchor + cases)
    candidate["c2h_legacy_policy.h"] = header.encode("ascii")

    # C2H_LEGACY validates the entire batch under the owner mutex. The original
    # record-write branch below this guard covers d->running and active DMA.
    guard = f"""\t\t\tif (op->write && op->offset == 0x{PCIE_RAW_VIDEO_REQUEST_PRODUCT:x}U) {{
\t\t\t\tif (op->value != {PCIE_RAW_VIDEO_PRODUCT_JPEG}U && op->value != {PCIE_RAW_VIDEO_PRODUCT_RAW}U) {{
\t\t\t\t\tret = -EPERM;
\t\t\t\t\tgoto out;
\t\t\t\t}}
\t\t\t\tif ((reg_read(d, C2H_LEGACY_BASE + C2H_LEGACY_CONTROL) & C2H_LEGACY_APP_ENABLE) ||
\t\t\t\t    (reg_read(d, C2H_LEGACY_BASE + 0x{p.PCIE_REG_STATUS:x}U) & 0x{GUARDED_STATUS:x}U) ||
\t\t\t\t    (reg_read(d, C2H_LEGACY_BASE + 0x{p.PCIE_REG_STEREO_STATUS:x}U) & (1U << {stereo.STEREO_STATUS_BITS_LOCKED}))) {{
\t\t\t\t\tret = -EBUSY;
\t\t\t\t\tgoto out;
\t\t\t\t}}
\t\t\t}}
"""
    anchor = "\t\t\tif (op->write && c2h_legacy_record_write(op->offset) &&\n"
    source = replace_once(n2["ph1a_c2h.c"].decode("utf-8"), anchor, guard + anchor)
    candidate["ph1a_c2h.c"] = source.encode("utf-8")

    python_after = python_before + (
        "\n# Cold RAW product overlay. The kernel validates writes and ownership.\n"
        f"READABLE = READABLE | frozenset((0x{PCIE_RAW_VIDEO_REQUEST_PRODUCT:x}, "
        f"0x{PCIE_RAW_VIDEO_ACTIVE_PRODUCT:x}))\n"
        f"WRITABLE = WRITABLE | frozenset((0x{PCIE_RAW_VIDEO_REQUEST_PRODUCT:x},))\n"
    ).encode("ascii")
    return n2, candidate, python_after


def prepare_sources(destination, repo=REPO):
    n2, candidate, python_policy = derive_sources(repo)
    destination.mkdir(parents=True, exist_ok=False)
    (destination / "source").mkdir()
    patch = []
    for name, content in candidate.items():
        (destination / "source" / name).write_bytes(content)
        patch.extend(unified_diff(n2[name].decode().splitlines(keepends=True),
                                  content.decode().splitlines(keepends=True),
                                  fromfile=f"a/{name}", tofile=f"b/{name}"))
    patch = "".join(patch).encode("utf-8")
    (destination / "raw-product.patch").write_bytes(patch)
    policy_path = destination / "python" / PYTHON_POLICY
    policy_path.parent.mkdir(parents=True)
    policy_path.write_bytes(python_policy)
    ko_sha, ko_bytes, ko_build_id = dual_r3_driver.module_identity("stereo-n2")
    report = {
        "status": "RAW_SOURCE_CANDIDATE", "module_build": "NOT_RUN", "board": "NOT_RUN",
        "base_commit": BASE, "n2_matched_source": MATCHED_SOURCE.as_posix(),
        "published_n2_ko": {"sha256": ko_sha, "bytes": ko_bytes, "build_id": ko_build_id},
        "published_kernel": {"release": dual_r3_driver.KERNEL_RELEASE,
                             "build_id": dual_r3_driver.KERNEL_BUILD_ID,
                             "config_sha256": dual_r3_driver.CONFIG_SHA256},
        "kernel_sources": {name: {"n2_sha256": digest(n2[name]), "raw_sha256": digest(content)}
                           for name, content in candidate.items()},
        "python_policy": {"n2_sha256": PUBLISHED_POLICY_SHA256, "raw_sha256": digest(python_policy)},
        "patch_sha256": digest(patch),
    }
    (destination / "SOURCE.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare_sources(args.output), indent=2))


if __name__ == "__main__":
    main()
