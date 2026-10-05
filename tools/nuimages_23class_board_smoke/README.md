# RK3576 file-input smoke package (not run on a board)

Status: **BOARD NOT_RUN**. This package was prepared on Linux x86_64 without an
RK3576 access route. It is not evidence of model loading, detection quality,
latency, or a production warning threshold.

`model.rknn` is the FP artifact with SHA256
`fbb111c43aa8221203d733faf524d8884f09d1d4f6863a1da1036a699cabfa8e`.
The inputs were created from the three unannotated CAM_FRONT JPGs using
`feature/nuimages-23class-preprocess` at commits `5ef860b949833022c1c246080b6ab6208b7f0356`
and `cbcf9381bd56cfd0e05c56d577f3ddba7fe77c0e`: RGB, NHWC, uint8,
1×640×640×3, pad 0, truncation of scaled dimensions and centered border.
Each RGB canvas SHA matches variant B in the fixed `_02/preflight.json`.
No host `/255` is applied to the RKNN inputs. Converter/runtime normalization
must be confirmed against the board's actual input attributes and the ONNX
reference before treating numerical results as compatible.

Contents:

- `model.rknn` — exact FP RKNN artifact.
- `raw_images/*.jpg` — the three unannotated, SHA256-checked CAM_FRONT source
  images. The board script consumes the prepared inputs, not annotated images.
- `input_<scene>.npy` — three uint8 RGB NHWC batch-one inputs.
- `onnx_<scene>_<index>.npy` — CPU ONNX reference outputs for the same RGB
  canvas after NCHW float32 `/255`; these are not assumed to have the same
  order, shape or layout as RKNN outputs.
- `manifest.json` — source, artifact and per-file SHA256, geometry, ONNX
  output name/shape/dtype, 23-class order, nine pixel anchors at strides
  8/16/32, experimental smoke thresholds, and tool versions.
- `run_board_smoke.py` — board-only file-input inference and raw output capture.
- `query_rknn_attrs.c` — optional native API query for SDK/driver and model
  tensor/quantization attributes, using already available headers/libraries.
- `SHA256SUMS.json` — hashes of all other package files, including raw images.

On an actual RK3576 board, copy this whole directory into a new isolated
directory. Use only the dependencies already present there; do not install or
upgrade anything for this test. First verify `SHA256SUMS.json` and model SHA.
Then, from this directory, run:

```sh
python3 run_board_smoke.py --bundle . --output ./board-output-001 \
  > run.stdout.log 2> run.stderr.log
```

Save the command's exit code, both complete logs, `board-output-001/report.json`,
and every `rknn_*.npy` with their SHA256. The script refuses x86_64/non-RK3576,
records `load_rknn`/`init_runtime` return values, submits uint8 NHWC with
`data_format=['nhwc']`, and saves returned outputs **in returned order**. It
does not decode boxes, apply NMS, or declare detection success.

If `rknn_api.h`, `librknnrt.so`, and a compiler are *already* present on the
board, `query_rknn_attrs.c` can separately query exact SDK/driver versions,
model input/output order, dimensions, format, dtype, quantization type,
zero point and scale through the official `rknn_query` API. Compile against
the board's matching existing SDK paths; do not copy a guessed library or
install one. Preserve this helper's complete stdout/stderr and exit code.
If these prerequisites are absent, mark quantization attributes NOT_RUN.

Only after the RKNN output attribute order/layout is independently confirmed
should each saved RKNN output be mapped to an ONNX reference output. Compare
same-semantic tensors numerically (e.g. maximum/mean absolute error), recording
any required axis permutation and dtype/dequantization rule explicitly. A
matching shape alone is insufficient to establish that mapping; until then,
the numerical comparison remains NOT_RUN. Model load or successful inference
does **not** establish detection effectiveness or warning safety.

Official API basis: the local RKNN Toolkit2 2.3.0 Lite `resnet18/test.py`
example for RK3576 `load_rknn`/`init_runtime`/`inference`, and the local
`rknpu2/examples/rknn_common_test/src/main.cc` for SDK/driver and tensor
attributes via `rknn_query`.
