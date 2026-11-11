"""Seal this independent candidate; frozen IP must match the fixed R1 parent."""
import argparse
import copy
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "5bdca7029b4aa9c6005ca67d89d045a92d4fc4a5"
PROJECT = ROOT / "fpga_prj/rfcamera_raw_r2.al"
NEW_RTL = ()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    parent = json.loads((ROOT / "verification_reference/r1_manifest.json").read_bytes())
    parent_seal = json.loads((ROOT / "verification_reference/r1_source_seal.json").read_bytes())
    al = ET.fromstring(PROJECT.read_text(encoding="utf-8").replace("P&R", "P&amp;R"))
    registrations = []
    for node in al.findall("Source_Files//File"):
        full = (PROJECT.parent / node.attrib["Path"]).resolve()
        if not full.is_relative_to(ROOT.resolve()):
            raise ValueError("Source escapes isolated project: " + str(full))
        registrations.append(full.relative_to(ROOT).as_posix())
    expected = set(parent["registrations"]) | set(NEW_RTL)
    if al.attrib["Path"] != "." or len(registrations) != len(set(registrations)) or set(registrations) != expected:
        raise ValueError("Native AL path/registration closure differs")
    if al.findtext("Name") != "rfcamera_raw_r2":
        raise ValueError("Wrong native project identity")
    manifest = copy.deepcopy(parent)
    for path in NEW_RTL:
        manifest["files"].append(dict(path=path, register=True, sha256=None))
    changed = []
    for row in manifest["files"]:
        value = digest(ROOT / row["path"])
        previous = parent_seal["production_inputs"].get(row["path"])
        if value != previous:
            if row["path"].startswith("src_fpga/ip/"):
                raise ValueError("Frozen IP changed: " + row["path"])
            changed.append(row["path"])
        row["sha256"] = value
    manifest.update(name="rfcamera_raw_r2", baseline_commit=BASE, registrations=registrations,
        closure_basis=dict(baseline_commit=BASE, scope="Independent copies of R1 production inputs; new qualification only"),
        stages=dict(scope="Source-only manifest; separate candidate evidence records actual stages."))
    closure = {row["path"]: row["sha256"] for row in manifest["files"]}
    identity = dict(candidate=manifest["name"], baseline_commit=BASE,
        production_inputs=closure, production_changed=sorted(changed),
        frozen_ip_count=sum(p.startswith("src_fpga/ip/") for p in closure),
        native_project_sha256=digest(PROJECT),
        design_sha256=hashlib.sha256(json.dumps(closure, sort_keys=True).encode()).hexdigest())
    for path, obj in ((ROOT / "SOURCE_MANIFEST.json", manifest), (ROOT / "docs/SOURCE_SEAL.json", identity)):
        if args.check:
            if obj != json.loads(path.read_bytes()):
                raise ValueError("Seal stale: " + str(path))
        else:
            path.write_text(json.dumps(obj, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in identity.items() if k != "production_inputs"}))


if __name__ == "__main__":
    main()
