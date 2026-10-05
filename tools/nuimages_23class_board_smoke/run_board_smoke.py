"""Single-file-input RK3576 smoke test. Run only on an actual RK3576 board.

This runner does not download, convert, quantize, postprocess, or use PCIe.
It records returned arrays as-is: no ONNX output ordering/layout is assumed.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import logging
from pathlib import Path
import platform
import sys
import time

import numpy as np


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_optional(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except (OSError, UnicodeError):
        return "UNKNOWN_NOT_READABLE"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    bundle = args.bundle.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=False, exist_ok=False)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log = logging.getLogger("board_smoke")
    report: dict[str, object] = {"status": "FAILED", "cases": []}
    runtime = None
    try:
        compatible = Path("/proc/device-tree/compatible").read_bytes()
        machine = platform.machine()
        report["platform"] = {"machine": machine, "compatible": compatible.replace(b"\0", b" ").decode(errors="replace")}
        if machine != "aarch64" or b"rk3576" not in compatible.lower():
            raise RuntimeError("This script requires an actual RK3576 aarch64 board")

        report["python"] = platform.python_version()
        report["numpy"] = np.__version__
        report["driver_version_sysfs"] = read_optional(Path("/sys/kernel/debug/rknpu/version"))
        try:
            report["rknn_lite_package_version"] = importlib.metadata.version("rknn-toolkit-lite2")
        except importlib.metadata.PackageNotFoundError:
            report["rknn_lite_package_version"] = "UNKNOWN"

        manifest = json.loads((bundle / "manifest.json").read_text(encoding="utf-8"))
        model = bundle / "model.rknn"
        if sha256(model) != manifest["model_sha256"]:
            raise ValueError("model.rknn SHA256 mismatch")
        report["model_sha256"] = manifest["model_sha256"]
        report["input_submission"] = "RGB NHWC uint8 1x640x640x3; no host /255"
        report["rknn_tensor_attributes"] = "UNKNOWN_WITH_RKNNLite; query native RKNN API separately"
        for case in manifest["cases"]:
            path = bundle / case["input_file"]
            if sha256(path) != case["input_file_sha256"]:
                raise ValueError(f"input file SHA256 mismatch: {path.name}")
            array = np.load(path, allow_pickle=False)
            if array.shape != (1, 640, 640, 3) or array.dtype != np.uint8 or not array.flags.c_contiguous:
                raise ValueError(f"invalid RGB NHWC uint8 input: {path.name}")
            if hashlib.sha256(array.tobytes()).hexdigest() != case["input_payload_sha256"]:
                raise ValueError(f"input payload SHA256 mismatch: {path.name}")

        from rknnlite.api import RKNNLite  # Import only after real-board identity check.

        runtime = RKNNLite(verbose=True)
        load_ret = runtime.load_rknn(str(model))
        report["load_rknn_return"] = load_ret
        log.info("load_rknn_return=%s", load_ret)
        if load_ret != 0:
            raise RuntimeError("load_rknn failed")
        init_ret = runtime.init_runtime()
        report["init_runtime_return"] = init_ret
        log.info("init_runtime_return=%s", init_ret)
        if init_ret != 0:
            raise RuntimeError("init_runtime failed")
        sdk_method = getattr(runtime, "get_sdk_version", None)
        if callable(sdk_method):
            try:
                report["sdk_version_lite"] = str(sdk_method())
            except Exception as error:
                report["sdk_version_lite"] = f"UNKNOWN_QUERY_FAILED: {error}"
        else:
            report["sdk_version_lite"] = "UNKNOWN_NOT_EXPOSED_BY_LITE"

        for case in manifest["cases"]:
            array = np.load(bundle / case["input_file"], allow_pickle=False)
            start = time.perf_counter_ns()
            outputs = runtime.inference(inputs=[array], data_format=["nhwc"])
            elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000
            if not isinstance(outputs, (list, tuple)):
                raise RuntimeError(f"inference did not return an output sequence for {case['scene']}")
            record = {"scene": case["scene"], "input_payload_sha256": case["input_payload_sha256"],
                      "elapsed_ms": elapsed_ms, "output_count": len(outputs), "outputs": [],
                      "onnx_numerical_comparison": "NOT_RUN: output layout/order not yet confirmed"}
            for index, value in enumerate(outputs):
                tensor = np.asarray(value)
                path = output / f"rknn_{case['scene']}_{index}.npy"
                np.save(path, tensor, allow_pickle=False)
                attrs = {"index": index, "shape": list(tensor.shape), "dtype": str(tensor.dtype),
                         "file": path.name, "file_sha256": sha256(path),
                         "payload_sha256": hashlib.sha256(tensor.tobytes()).hexdigest(),
                         "finite": bool(np.isfinite(tensor).all()) if np.issubdtype(tensor.dtype, np.number) else None,
                         "quantization": "UNKNOWN_WITH_RKNNLite"}
                record["outputs"].append(attrs)
                log.info("scene=%s output=%s attrs=%s", case["scene"], index, json.dumps(attrs))
            report["cases"].append(record)
            log.info("scene=%s elapsed_ms=%.3f output_count=%s", case["scene"], elapsed_ms, len(outputs))
        report["status"] = "RUNTIME_EXECUTED_NOT_DETECTION_VALIDATED"
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
        log.exception("board smoke failed")
    finally:
        if runtime is not None:
            try:
                runtime.release()
            except Exception:
                log.exception("runtime.release failed")
        (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0 if report["status"] == "RUNTIME_EXECUTED_NOT_DETECTION_VALIDATED" else 1


if __name__ == "__main__":
    sys.exit(main())
