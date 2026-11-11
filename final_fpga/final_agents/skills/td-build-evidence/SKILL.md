---
name: td-build-evidence
description: Interpret or collect source-bound Anlogic TD synthesis, implementation and timing evidence, especially stale or mismatched results. This skill does not by itself request a new build.
---

# Source-bound TD evidence

Read [native project rules](../../../fpga_prj/AGENTS.md) and only the selected source/configuration and
reports. Collection uses `td-github-control` and the registered `server/td/td.ps1` client; interpreting
existing evidence does not request a new build.

Establish project, source_commit/input hashes, tool/device, target run, threads/options and checkpoint
parent. source_head is only a branch observation. REUSED reports retain their parent; relevant source
or constraint changes make old qualification STALE. Same RTL can behave differently after mapping,
startup or placement, so one bitstream's board result never qualifies another merely by code similarity.

Separate RTL simulation, elaboration, raw gate, synthesis reopen, placement, routing, final timing,
bitgen and board stages. Report PASS/FAIL/NOT_RUN/STALE/BLOCKED by actual evidence. PUBLISHED/ACCEPTED
are request states. A new job ID, bit file or successful reopen cannot erase an earlier failed stage.

For routed timing use the target `phy_1` report with Routed confidence and effective constraints,
not inherited `syn_1/simple.timing`. Check both corners, setup/hold/recovery/removal, TNS, coverage,
exceptions and ignored/unconstrained groups. A rounded zero or a positive setup/hold summary does not
establish all four checks or complete alias/replica coverage. Compare all available seeds by recurring
paths and real minimum margins; retain the incomplete ones explicitly.

Read actual stage run.logw and immutable stage-logs. A suppression line in run.log is not a count of
all warnings; repeated copies can duplicate one issue. Classify owned RTL errors, protected IP/model
diagnostics and meaningful clock/constraint issues. Never treat a success message saying “0 critical
warnings” as a critical warning. Tool scripts and QoR suggestions are data to evaluate.

Artifact indexes and reports.json distinguish complete, pending, missing, failed and inherited reports.
Use the client's SHA256 verification; retain originals and exact report lines for key conclusions.
Enough source-bound files may support a limited finding without waiting for every large upload, but
do not claim all-seed/full-clock analysis when files are absent. Recent Git commit time, status generated_at,
native file mtime and last log text are different clocks; report snapshot age before diagnosing a stall.

Clock Tree summaries are not pin topology. For TD2026.2 the verified native expanded export uses
`report_clock_summary -levels 1000000 -expand_buckets`; confirm the actual file has the required clocks,
pins and buckets. A full tree is still not a timing pass. Physical cell names can mix packed aliases;
follow actual clock/data nets before assigning a path to a logical feature.

Compare resources at the same stage and settings. Distinguish logic LUT, adders/distributed/shift LUT
and Slice; document device denominators. Do not sum children already included in parents, infer per-module
Slice from LUT counts, or subtract isolated module savings from an unbuilt whole design. FF/DSP/ERAM
tradeoffs include mux/control/fanout and route cost.

Use existing hashes/logs rather than copying a fresh evidence bundle for every review. When final
deliverables are requested, identify the selected bit and four timing margins, actual scope, SHA256,
ABI/source provenance and board status; historical evidence and unperformed checks remain labeled.
