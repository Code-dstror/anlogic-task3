# HDR reader prefetch black-box test

The test uses the [HDR read contract](../../../docs/hdr_rate_seed56_20261110/HDR_READ_PUBLIC.md) and
its [RAW10 and merge arithmetic contract](../../../docs/seed12_round2_20261109/HDR_READER_PUBLIC.md).
It compiles the real reader carrier, decoder, TD 2026.2 memory models and two-client DDR arbiter
without inspecting their source or internal signals. A deterministic RAW10 stimulus covers dark
clipping, blend knees and both sides of the strict motion threshold. The integer oracle checks
every accepted RAW14 lane, motion mask, marker and index. It independently verifies reader
address coverage and scores each client and master AR/R handshake.

Run from the repository root in PowerShell 7. Use a new run name for each attempt.

```powershell
& './refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_prefetch_20261110/run_blackbox.ps1' `
    -ModelSimBin 'D:/App/modelsim/win64' -TdRoot 'D:/App/TD_Release_2026.2.210.850' `
    -RunName 'candidate_b2bc668e_r1' -Variant candidate `
    -CandidateSha256 'b2bc668efc5e1de8dc02ce4d8bfa16cdc8dcc43bd2cefb6595c04a751338bed3'
```

The runner checks each selected cursor SHA-256, builds each variant in a separate library,
and records input hashes before and after the run, exact commands and raw logs under
`tmp/hdr_rate_seed56_20261110/blackbox/<run name>`. Each tool call has a 55 s wall-clock timeout
and each scenario has a 1 ms simulation watchdog. Use `-Variant` and `-Scenario` to select
a focused rerun. The registered Python executable was inaccessible to the sandbox, so this
runner uses PowerShell directly with ModelSim SE-64 2020.4 and the explicit TD model root.

## Validation runs

| Variant | Cursor SHA-256 | Evidence | Functional result |
| --- | --- | --- | --- |
| Baseline | `af790e6e66602350cfcde32df2ad8cd9622fa13f5cbbedacfc7cdd1051197f4f` | [ab_r1 report](../../../../../tmp/hdr_rate_seed56_20261110/blackbox/ab_r1/report.json) | 8/8 PASS |
| Current candidate | `b2bc668efc5e1de8dc02ce4d8bfa16cdc8dcc43bd2cefb6595c04a751338bed3` | [candidate_b2bc668e_r1 report](../../../../../tmp/hdr_rate_seed56_20261110/blackbox/candidate_b2bc668e_r1/report.json) | 8/8 PASS |
| Historical candidate | `a8f7a96c365d56b73997defe1454d23eb280516f38b8e8335824b4fe559db447` | [ab_r1 report](../../../../../tmp/hdr_rate_seed56_20261110/blackbox/ab_r1/report.json) | 8/8 PASS |

The baseline cursor still matches its recorded SHA-256. All 23 shared contract, test,
dependency and tool hashes match between runs, and no input changed during the current
run. The current and historical candidates have identical bench markers and public AR/R
traces in all eight scenarios.

## Baseline and current candidate

The first legal 68×63 job reached successful RESULT on both variants. The clock period was
7.502 ns, master AR to first R acceptance was 32 edges for every burst, and the RAW consumer
was always ready. Both variants accepted 42 ARs and 670 R beats, and produced 1,071 groups
with 268 motion groups and digest `3ad94771e30dea09`. The address checks include the 4 KiB
boundary and the 11-byte tail of each exposure.

| Measured edges | Baseline | Candidate |
| --- | ---: | ---: |
| START acceptance to RESULT acceptance | 3,515 | 2,421 |
| Sum between master RLAST and next master AR, excluding endpoints | 1,451 | 356 |
| Maximum of those 41 intervals | 45 | 46 |
| Reader-facing RVALID held by RREADY low | 1,280 | 0 |
| Master-facing RVALID held by RREADY low | 0 | 0 |

The fast responder case reached 512 LONG and 504 SHORT groups in both builds, held RAW over
indices 510 and 1,022, injected AR and R pauses, and exercised RESULT backpressure. In the
candidate, public reader-R and RAW transfers coincided on 163 edges across all three
output-index regions.

Both cancel cases drained and reported one negative result. An AR was offered and stalled on
both sides of the arbiter at cancel, and its 16 responses drained before RESULT. In the
held-RAW case the candidate had 175 accepted reader R beats and 176 accepted master R beats
at cancel. It retired all 176 reader R beats and accepted the ordered six-group RAW prefix
before negative RESULT. Both cases then succeeded on camera 1, bank 1 without reset, with
digest `81fda08ab2343fde`.

The legal SLVERR response drained and returned a negative result with the arbiter diagnostic
latched and recovery deasserted. The wrong RID and missing RLAST each produced a quarantine
with recovery required and no RESULT in the 48-edge observation window. A coordinated reset
allowed a fresh legal job after each. One competing client transferred four beats with its
own ID, data and LAST while reader traffic was active.

These measurements cover the one-clock reader/arbiter simulation and its prescribed
memory-response profiles. Full-HD sustained service, synthesis, P&R, physical timing
and board tests are NOT_RUN for this black-box comparison.
