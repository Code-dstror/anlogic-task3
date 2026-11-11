# Independent DCP cancellation and UART field short tests

[Public contract](PUBLIC_CONTRACT.md) · [Declaration-only port list](PUBLIC_PORTS.txt)

```powershell
& 'python' -B `
  'refactor/camera_raw_r1/src_fpga/simulation/blackbox_field_timing_20261108/run.py' `
  --modelsim-bin 'D:/App/modelsim/win64' --td-root 'D:/App/TD_Release_2026.2.210.850'
```

Run from the repository root. The ModelSim cases use SE-64 2020.4 and no vendor models.
Each process has a 45 s wall timeout; HDL watchdogs are 1 ms simulated time. Scope and results:

| Case | Evidence |
| --- | --- |
| DCP clear | PASS in 204.056 µs: 2 complete 256×128 rasters checked in RGB/Y/SOF/EOL; 3 cancelled frames with held first beat, consumed body prefix or held tail. Early, late, negative and clear-coincident SOURCE inputs exercised. |
| DCP history/reset | PASS in 263.064 µs: 4 complete rasters; the negative terminal did not publish history. Committed history was eye-local and survived clear; reset under held output was followed by exact cold identity. Uniform grey192 proves this boundary under the airlight clamp. |
| Diagnostic helper and actual UART wire | PASS in 122.545 µs: checked 16,331 DFI and 8,753 PIX domain samples, including RUN edges, modulo wrap and epoch changes. Three CRC-verified DJ v2 packets with fresh masks `03/01/03` and reset masks `03/03/03`; proved frozen SYS overlay despite mid-packet changes and recovery after stopped PIX clock. |
| Python parser | PASS: independently packed mixed DJ v1/v2 in one-byte fragments, validated v2 data and both sensor dictionaries; two good frames recovered after noise, invalid length, wrong CRC and truncation. Counts: CRC errors 2, invalid headers 1, discarded bytes 167. |

The original logs and exact command/per-file hash receipts are under `camera_raw_r1/tmp/blackbox_field_timing_20261108/`:

- `20261108T125756.938602Z_initial/evidence.json`: both DCP cases passed with stable inputs. Aggregate
  input SHA-256 `49b38cb7bdaadcac9b57234beb75257837a5566897a2c868acb03491aaa5cadd`;
  manifest `c2eede07a249072787de7acec3f84acd6370280d35af0770e7b16d0b1cfb9d66`;
  DCP TB `0048a276fd2b27be76244d3d454d1a1b65e8a87a0b5c5128d7acce01445eb32f`;
  DCP source `a3c231735f22d03525e1454db2930872e4b7019d593354f89c4d8dd32fd6da1f`.
  This manifest also preserves unrelated UART/Python fixture failures: starting UART reception during
  the already active first report and applying the DJ v2 field oracle to a DJ v1 event.
- `20261108T125925.263814Z_uart_from_reset/evidence.json`: UART/helper and Python parser both passed
  with stable inputs. Aggregate input SHA-256 `b5dbe61d3df1fd73b06d501c884f1c98bd5eb73e10cc88dde016ebf371762806`;
  manifest `112924c1be4b1c4f237c37424eb8bf2896c961ea91b81e57b315c115e489de9c`;
  UART TB `2d1b10df7ae5dd62d68ae747517c06b94e25c1256a85b8943be8c850f80d379f`;
  decoder test `f549f693c77886dcc67abb19d7f67b7e53c258ef42ad8258de4e2248073bdb3e`.

The diagnostics tests prove counter and wire behavior at the supplied ports, not that a board had a
particular fault or that every physical FS was admitted. No production files were changed by the author.
Both compiles and DCP elaboration reported zero warnings; UART elaboration's `vopt-2685/2718` messages
cover the two unused trace outputs in the TX-only test profile.
Synthesis, P&R, STA, bitgen and board NOT_RUN by these suites.
