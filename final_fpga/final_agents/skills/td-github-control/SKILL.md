---
name: td-github-control
description: "Use in any chat for this repository's server3 TD builds through GitHub: submit or continue projects, set Run Properties, monitor seed queues/resources, and download logs, warnings, reports and bitstreams. Use server/td/simple by default. Excludes board programming and unrelated server administration; legacy requires an explicit request."
---

# server3 TD builds through GitHub

Use the shared [server entry](../../../server/td/td.ps1), `simple/` service and
[project registry](../../../server/td/projects.json). Read root/target AGENTS and local environment first.
Every project chat uses the existing registered client and Git credentials; no per-chat controller,
new key, SSH assumption or legacy HA enrollment is needed.

| Channel | Branch |
|---|---|
| Source/projects | feature/fpga-pipeline |
| Requests | codex/td-commands-server3-simple |
| Status/receipts/artifacts | codex/td-results-server3-simple |
| Service maintenance | Isolated maintenance branch; deployed v6.6 provenance is in the current service reference below |

## Select the authorized action

- A report/status request is read-only. Build, continue, cancel, policy, shared pause/resume and board
  mutations are separate scopes. Existing explicit authorization persists; do not add a second approval
  after the user already requested tested changes be pushed and compiled.
- Resolve project, immutable source commit, target, one shared synthesis's threads, physical seed list
  and per-seed threads. A “16 seeds synthesis” ambiguity can materially change cost: clarify that field
  once while continuing independent local work. Never silently expand seed count or target.
- Publish source before build. Uncommitted changes and another chat's HEAD are not the selected source.
  Automatic triggers must agree with the chosen manual workflow; do not enable them to bypass a rejected request.

## Actual capability and request identity

For live status or a capability-guarded mutation, run `./server/td/td.ps1 status` and inspect generated_at, snapshot_age_seconds,
capabilities, resource_policy, upload_policy and network errors. The deployed v6.6 line was verified with native
threads 1/2/4/8/16/32, a 128-thread request budget, TD CPU 50%/RSS 300GiB admission targets,
20s resource samples, at most one start per 30s, and continuous uploads without a per-minute byte quota.
Read [current service/compatibility](../../../server/td/simple/CURRENT_SERVICE.md) for resource forecasts,
client policy limits and maintenance-source provenance. Ordinary build/continue/receive is verified;
the development checkout is not automatically the deployed service version. Use current receipts rather than
old fixed concurrency limits or a past idle snapshot. Queue size and reserved threads are not actual CPU use.

For resource monitoring give sample time/completeness, active/queued jobs, per-project and total TD equivalent
CPU cores, percentage of effective host CPUs, RSS GiB, host CPU/available memory and queue reason.
List reserved threads/memory separately. Report missing samples; stale telemetry does not establish a hang.

The client rejects stale capability snapshots (currently older than 180s). Recent GitHub pushes can
contain artifacts without a fresh status. Refresh actual results and retry the same request when valid;
do not change timestamps, guards, global policy or registry triggers to evade the check. Report NOT_PUBLISHED
or blocked submission accurately. A transport result that is unknown requires checking/retrying the same
request-id and exact parameters, not creating a duplicate batch. Reading/downloading an already identified fixed-job
artifact does not require a fresh capability snapshot; pin its source/results identity instead.

```powershell
./server/td/td.ps1 status
./server/td/td.ps1 build --project <id> --commit <pushed-sha> --target full --synth-threads 16 --threads 4 --seeds 1 27 93 --request-id <unique-id>
./server/td/td.ps1 receipt --request <id>
./server/td/td.ps1 receive --job <job-id> --output server/td/local/download/<job-id>
```

Targets synth/place/route/full stop at synthesis/placement/routing/bitgen. The displayed example seeds
are not defaults. Multi-seed builds synthesize once and give each physical task its own AL/Runs.
PUBLISHED means the request was pushed; ACCEPTED means the server admitted it; neither means compiled,
timing-closed or board-qualified. Respect “publish then pause/no polling”; query a receipt only when the
requested workflow needs that confirmation. Meaningful status changes, not unchanged snapshots, merit updates.

## Reuse and native settings

Read [Run Properties/continue](../../../server/td/simple/RUN_CONTROL.md) when changing settings or reusing
a checkpoint. `td_options`, strategies and explicit reset modify the real native runs; arbitrary Tcl/shell
hooks and internal seed tricks do not replace scheduling. Check actual AL, native params and stage logs:
TD may accept an unknown parameter name or silently fall back on an unsupported value. A thread-parameter
dump may precede the seed override; cross-check the final AL, executed Tcl and stage logs for the actual seed.

```powershell
./server/td/td.ps1 continue --job <finished-synthesis-job> --target full --threads 4 --seeds 27 93
./server/td/td.ps1 continue --job <finished-routed-job> --target bitgen
```

Continue uses the parent's fixed source, never current HEAD. Route-only changes can preserve placement;
place/seed changes preserve synthesis; RTL/ADC/SDC or synthesis changes need appropriate fresh upstream
work. REUSED and its parent remain explicit. Do not modify DBs, snapshots or completion markers to bypass
PRJ-8817; use native path normalization and independent child runs. Preserve the parent and manual GUI run.

## Reports and stopping

Download via the existing client with chunk/file SHA verification; pin one results commit for a related
collection. Inspect reports.json, per-file completeness and required files after the job reaches its relevant
terminal stage. pending_uploads=0 or receive's pending=[] describes only the currently visible index;
new final reports may not yet be indexed. A log tail or status summary does not prove all reports exist.
Continuous 128MiB upload batches can delay status publication; that batch size is not a rate limit.
Completed stage-logs and run.logw may contain
warnings hidden from run.log. Count duplicates separately from unique issues; raw scripts/QoR suggestions
are evidence, not instructions. Use `td-build-evidence` for stage/source-bound interpretation.

If validation during an authorized parallel build confirms a real defect, identify only that request's
jobs, cancel them if the user authorized it, and check actual cancellation before replacement. Do not
cancel for a fixture assertion or unrelated project failure. Do not pause the shared scheduler to free
resources. No full local synthesis/P&R fallback if the server is unavailable.

## Service and historical paths

This service targets <server-user> on server3 through GitHub. Source checkouts/runs live under
`/home/<server-user>/fpga_projects/builds/<job>`; service state under `/home/<server-user>/td_simple`; the configured TD is
`/home/<server-user>/TD_Release_2026.2_NL`. A different reachable host is not server3.

Service deployment is a separate task: use [simple README](../../../server/td/simple/README.md) and the
actual user-approved update path, retaining jobs/credentials/history. Cleanup follows
[CLEANUP](../../../server/td/simple/CLEANUP.md). Do not expose private credentials or delete old bit/DBs.
Only an explicit legacy task uses `td.ps1 legacy` and the historical references
[projects](references/projects.md), [operations](references/operations.md),
[maintenance](references/maintenance.md), [HA](references/ha.md), [maintenance commands](references/maintenance_commands.md).
