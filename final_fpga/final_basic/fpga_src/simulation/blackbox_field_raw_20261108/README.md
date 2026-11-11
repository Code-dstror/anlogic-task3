# Independent RAW field short tests

[Public contract](PUBLIC_CONTRACT.md) · [Ports and ARAW format](PUBLIC_PORTS.md) · [Opaque compile list](sources.json)

From the repository root, use the registered Windows Python and ModelSim SE-64 2020.4:

```powershell
& 'python' -B `
  'refactor/camera_raw_r1/src_fpga/simulation/blackbox_field_raw_20261108/run.py' `
  --modelsim-bin 'D:/App/modelsim/win64' --td-root 'D:/App/TD_Release_2026.2.210.850'
```

8/8 PASS with stable inputs. Each process has a 45 s wall timeout and 200 µs simulated watchdog;
the longest actual case used 2.672 s wall time and the largest simulation was 5.050 µs. The test uses
the real store, reader, directory RAM and formatter. A memory BFM models accepted SOURCE/write
completion and returns actual AR/R beats; a host BFM consumes ARAW bytes and returns SAFE only after
the applicable drain. The scalar BEGIN serializes two producers' available requests. The full camera,
DDR write engine, physical DDR, PCIe DMA and software ACK are outside this model.

| Cases | Accepted host records and final retirement |
| --- | --- |
| Startup ×2, swapped first eye and reset phase | 12 correct records per case; 6 per eye, zero rejections. |
| Full pressure ×2, swapped held eye | 6 correct records per case, sequences 1/2/4 per eye; exactly one explicit rejection per eye at sequence 3. Held header and tail, wrong SAFE, delayed SAFE and low release quiet were exercised. |
| Negative SOURCE | Failed first eye produces no success; other eye and next healthy sources produce 3 correct records. |
| STOP near BEGIN | Rejection before BEGIN and after the first pending edge; accepted response while STOP was applied just before/after the response handshake, both with negative finish. Two correct post-STOP records. |
| STOP with stalled AR / stalled RAW beat | Each cancelled first record drains the sampled obligation and returns negative DONE, matching SAFE and actual retirement, followed by two correct records. |

The preserved exact commands, tool/model hashes, per-file input hashes and log hashes are in
`tmp/blackbox_field_raw_20261108/20261108T125926.607074Z_final_public_contract/evidence.json`
under `camera_raw_r1`. Manifest SHA-256 `e62c30a577386988915f81f2fff3eb4857bee8e14f265ae3e12dde922667a8ba`;
aggregate input SHA-256 `28eb07e958b7a92827a4713e2ef33f228e89b1ee6f4554f5b95f78f748b7dd85`;
TB `c345b513894bd7a691174c10962cbaf798427a3b814bdc0a62b5ee285d92c28f`;
`stereo_raw_owner.v` `cd9b16c45bb626816805f0208e50a669b50e28a1d193b49486725737653b6dc3`.
Compile had no errors or warnings. The first elaboration recorded 27 fixture warnings about deliberately
unused public outputs (`vopt-2685/2718`), two ECC injection width warnings from `ram40_sdp_fixed.v`
(`vopt-2241`), and two `INIT_FILE` range warnings in the TD 2026.2.210.850 PH1 ERAM model (`vopt-2697`).
All messages are retained in the transcript.

Earlier run directories preserve fixture failures: `initial` wrong model top, `glbl` illegal profile in
the initial handoff, `legal_profile` missing PH1 GSR top, `legal_profile_gsr` and `descriptor_details`
incomplete job descriptor contract (allocation fields are now checked), and `normative_descriptor`
STOP requested before the first sampled RAW stall. `sampled_data_stop` verifies STOP after the first
actual stalled RAW edge before the complete final run. No production changes were made by the author.

Functional simulation PASS within this model; synthesis, P&R, STA, bitgen and board NOT_RUN by this suite.
