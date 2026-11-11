"""Record isolated FPGA, native project and RK inputs for camera_fusion_r1."""

import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NAME = "rfcamera_fusion_r1"
PROJECT = ROOT / "fpga_prj" / f"{NAME}.al"
REFERENCE = ROOT / "verification_reference"
RATE_SEAL = "5914a5b22e09c4f9d4fbf1186ee32d1bf8940c592fce6e5a525f8b4cb5abeeb5"
QUALITY_SEAL = "d3532490d5dfd1587d741f727427faa13e5d68c8d16013027c93b27902c4d85b"
QUALITY_COMMIT = "7dde99e738a48ec5b399a9cf965f7fd7a47ca8c2"
COMMON_COMMIT = "1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba"
TONE_DATA = tuple(f"src_fpga/ip/coefficients/tone96_{index}.mif" for index in range(2))
QUALITY_HEADER = "src_fpga/rtl/include/00_rtl/quality_control_v1.vh"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def map_digest(data):
    return digest(json.dumps(data, sort_keys=True).encode())


def isolated_path(path):
    resolved = path.resolve(strict=True)
    if not resolved.is_relative_to(ROOT):
        raise ValueError(f"Input escapes the isolated project: {path}")
    return resolved.relative_to(ROOT).as_posix()


def relative_registration(value):
    if Path(value).is_absolute():
        raise ValueError(f"Absolute native dependency: {value}")
    return isolated_path(PROJECT.parent / value)


def project_xml(normalize):
    # TD uses literal P&R in attribute names. Preserve its native encoding on disk.
    raw = PROJECT.read_bytes()
    tree = ET.fromstring(raw.replace(b'UsedInP&R', b'UsedInP&amp;R'))
    path = tree.attrib["Path"]
    if path != ".":
        if not normalize or Path(path).resolve() != PROJECT.parent:
            raise ValueError(f"Native project Path must be '.', found {path!r}")
        raw, count = re.subn(rb'(<Project\b[^>]*\bPath=")[^"]+("[^>]*>)', rb'\g<1>.\2', raw)
        if count != 1:
            raise ValueError("Unable to normalize the native project root")
    return tree, raw


def auxiliary_inputs():
    files = list((ROOT / "rk_sdk").rglob("*.py"))
    files += list((ROOT / "rk_sdk/raw_driver").glob("*.c"))
    files += list((ROOT / "fpga_prj/scripts").glob("*.tcl"))
    files += [ROOT / path for path in (
        "docs/pcie_protocol_v1.json", "docs/geometry_control_v1.json", "docs/rate_control_v1.json",
        "docs/raw_video_v1.json", "docs/quality_control_v1.json", "docs/LOCAL_CATALOG_IP.json",
        "tools/generate_geometry_control.py", "tools/generate_rate_control.py",
        "tools/generate_raw_video_protocol.py", "tools/generate_quality_control.py",
        "tools/tone_quality_reference.py", "tools/uart_observer.py", "tools/seal_inputs.py",
    )]
    return {isolated_path(path): digest(path.read_bytes()) for path in sorted(files)}


def verify_source_seal(seal, expected):
    if seal["design_sha256"] != expected or map_digest(seal["production_inputs"]) != expected:
        raise ValueError(f"Source seal mismatch for {seal['candidate']}")


def native_run_parameters(tree, name):
    """Describe explicit native settings, never stale copied defaults."""
    run = tree.find(f"./Runs/Run[@Name='{name}']")
    sections = {"GlobalProperty": "flow", "GateProperty": "gate", "RtlProperty": "rtl",
                "PlaceProperty": "place", "RouteProperty": "route", "BitgenProperty": "bitgen"}
    values = {}
    for block in run.find("Strategy"):
        section = sections.get(block.tag)
        if section:
            for item in block:
                values[(section, item.tag)] = item.text
    for item in run.findall("./UserParams/param"):
        fields = item.text.split()
        if len(fields) == 4 and fields[0] == "set_param":
            values[(fields[1], fields[2])] = fields[3]
    return [[section, key, value] for (section, key), value in sorted(values.items())]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--normalize-project-path", action="store_true")
    args = parser.parse_args()

    manifest = json.loads((REFERENCE / "rate_manifest.json").read_bytes())
    rate = json.loads((REFERENCE / "rate_source_seal.json").read_bytes())
    quality = json.loads((REFERENCE / "quality_source_seal.json").read_bytes())
    verify_source_seal(rate, RATE_SEAL)
    verify_source_seal(quality, QUALITY_SEAL)
    tree, native = project_xml(args.normalize_project_path)
    config = tree.find("./FileSets/FileSet[@Name='design_1']/Config")
    registrations = [relative_registration(node.attrib["Path"]) for node in tree.findall("Source_Files//File")]
    includes = [relative_registration(node.attrib["Val"]) for node in config.findall("Option[@Name='IncludeDir']")]
    definitions = [f"{node.attrib['Name']}={node.attrib['Val']}" for node in config.findall("Define")]
    device = f"{tree.findtext('HardWare/Device')}{tree.findtext('HardWare/Speed')}"
    runs = [node.attrib["Name"] for node in tree.findall("Runs/Run")]
    if (tree.findtext("Name") != NAME or tree.findtext("TOP_MODULE/MODULE") != manifest["top"]
            or device != manifest["device"] or tree.findtext("TD_Version") != manifest["td_version"]
            or runs != ["syn_1", "phy_1"] or registrations != manifest["registrations"]
            or includes != manifest["include_dirs"] or definitions != manifest["definitions"]):
        raise ValueError("Native identity, source order, options or Runs differ from the isolated profile")

    baseline = rate["production_inputs"]
    if {entry["path"]: entry["sha256"] for entry in manifest["files"]} != baseline:
        raise ValueError("Rate manifest inputs differ from its fixed seal")
    manifest["files"].append(dict(path=QUALITY_HEADER, register=False, sha256=None))
    for entry in manifest["files"]:
        path = entry["path"]
        file = ROOT / path
        isolated_path(file)
        actual = digest(file.read_bytes())
        if path in TONE_DATA and actual != quality["production_inputs"][path]:
            raise ValueError(f"Tone coefficient input differs from the quality source: {path}")
        if path.startswith("src_fpga/ip/") and path not in TONE_DATA and actual != baseline.get(path):
            raise ValueError(f"Frozen IP changed: {path}")
        entry["sha256"] = actual

    production = {entry["path"]: entry["sha256"] for entry in manifest["files"]}
    inherited = dict(rate_design_sha256=RATE_SEAL, quality_commit=QUALITY_COMMIT,
                     quality_design_sha256=QUALITY_SEAL, common_commit=COMMON_COMMIT)
    auxiliary = auxiliary_inputs()
    manifest.update(name=NAME, closure_basis=inherited, auxiliary_inputs=auxiliary,
                    stages=dict(scope="Source closure. Validation evidence is recorded separately."))
    manifest["diagnostic_defaults"]["DJ"] = 4
    manifest["synthesis_parameters"] = native_run_parameters(tree, "syn_1")
    manifest["physical_parameters"] = native_run_parameters(tree, "phy_1")
    manifest["parameter_metadata_scope"] = "Explicit AL Strategy/UserParams; server request overrides and native effective readback are separate."
    identity = dict(candidate=NAME, inputs=inherited, production_inputs=production,
                    production_changed=sorted(path for path, value in production.items()
                                              if baseline.get(path) != value),
                    frozen_ip_count=sum(path.startswith("src_fpga/ip/") and path not in TONE_DATA
                                        for path in production),
                    tone_coefficient_inputs=list(TONE_DATA), auxiliary_inputs=auxiliary,
                    native_project_sha256=digest(native), design_sha256=map_digest(production))
    outputs = [(ROOT / "SOURCE_MANIFEST.json", manifest), (ROOT / "docs/SOURCE_SEAL.json", identity)]
    if args.check:
        for path, expected in outputs:
            if json.loads(path.read_bytes()) != expected:
                raise ValueError(f"Seal is stale: {path}")
    else:
        for path, body in outputs:
            path.write_text(json.dumps(body, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.normalize_project_path and PROJECT.read_bytes() != native:
        PROJECT.write_bytes(native)
    print(f"{NAME} design_sha256={identity['design_sha256']} inputs={len(production)} "
          f"registered={len(registrations)} frozen_ip={identity['frozen_ip_count']}")


if __name__ == "__main__":
    main()
