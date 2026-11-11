"""Compile opaque source sets for the public JPEG leaf and encoder ports."""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
PUBLIC_JPEG = PROJECT.parent / "camera_rate_r3/verification_reference/jpeg_throughput_public"


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--manifest", type=Path, required=True)
    args, remainder = parser.parse_known_args()
    manifest = args.manifest.resolve()
    if not manifest.is_relative_to(PROJECT / "tmp"):
        parser.error("use the prepared manifest inside the fusion tmp directory")
    expected = json.loads(manifest.read_bytes())["compiler_helper_sha256"]
    actual = sha256((PUBLIC_JPEG / "compile_inputs.py").read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError("The frozen compiler helper has changed")
    sys.path.insert(0, str(PUBLIC_JPEG))
    import compile_inputs

    compile_inputs.PROJECT = PROJECT
    compile_inputs.MANIFEST = manifest
    sys.argv[1:] = remainder
    compile_inputs.main()


if __name__ == "__main__":
    main()
