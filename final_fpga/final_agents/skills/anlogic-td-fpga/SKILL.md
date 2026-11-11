---
name: anlogic-td-fpga
description: Use when running or diagnosing Anlogic TD batch builds, IP registration, project synchronization, constraints, or physical timing. Follow this repository's fpga_prj/AGENTS.md; ordinary RTL edits do not require this toolchain.
---

# Anlogic TD project workflow

Follow [native rules](../../../fpga_prj/AGENTS.md). Determine the requested operation before running tools:
reading/diagnosing a report is not permission to build, ordinary RTL edits do not need this toolchain,
and document/skill cleanup does not require simulation or a production compile.

## Bind the real project

Read its sync/build/report Tcl, source manifest, TOP/macros, ADC/SDC and IP provenance. Use the target
PH1A90SEG324-2 package/speed and the independent AL/Runs, not a same-named parent or stale GUI copy.
Register each IPC once; do not separately add generated RTL/constraints that it already owns.
Vendor/private generated IP remains byte-for-byte. `<hidden>` protection is not itself a failure.

For current work choose TD2026.2 / 6.2.3.210850 at the installation verified in root
`ENVIRONMENT.local.md`, and explicitly pass `--td-root` to `tools/run_td.py`. The wrapper aligns child
TD_ROOT/TD_HOME/ANLOGIC_TD_ROOT/TD_INSTALL_DIR. Use the same installation's model library for simulation.
Historical TD is only for an explicit reproduction/version/provenance question. See
[2026.2 differences](references/td2026-2.md): PLL/LCLK clocks, logic-level optimization defaults and
deprecated routing/strategy values changed. A local tiny upgrade check does not qualify the main design.

```powershell
python tools/run_td.py <target-script.tcl> --td-root <verified-root> --workdir <project-dir> --log <ignored-run-log>
```

Resolve Python via the local environment rather than assuming that bare `python`, `py` and the app's
bundled interpreter have identical packages. When this needs diagnosis, inspect the target machine's `ENVIRONMENT.local.md` and explicit tool paths.

## Choose the smallest sufficient operation

- Source/interface/project check: native analysis/read_design and existing run reopen, not full synthesis.
- A measured mapping hypothesis: bounded isolated module A/B with identical inputs/options and explicit
  model/interface assumptions; report both mapping and target paths, not only global WNS.
- Long whole-design synthesis/P&R: the registered server workflow, with the user's exact source/threads/
  seeds/target. `td-github-control` handles capabilities, settings, reuse, receipt and artifact download.
- Functional validation: the fresh-context black-box contract in `rtl-stream-contract`; compiler-bound
  input files may be opaque to the author. Native elaboration is not functional simulation.

An unsupported parameter can be accepted or reset by TD without proving it took effect. Select actual
version-supported values and read native AL/params/logs back. Preserve upstream work only when inputs
and relevant options are unchanged; use stage-specific native reset/rebuild, never fabricated markers.
No local long-running fallback if server access is blocked.

## Judge and deliver

Check process result, fresh error markers, expected nonempty DB/report, terminal stage and source identity.
Keep failed attempts, even when a later reopen or same-source retry works. Reopen the same AL/run and
verify native source/configuration alignment and portability. An existing GUI may require reload;
native loadability does not prove its live display has refreshed.

TD legitimately writes an absolute project Path on save. Normalize it to `.` for Git/delivery only,
keep actual dependencies relative, and run `tools/check_td_project_portability.ps1`. Do not delete an
existing AL, entire Runs or unique evidence to make a create_project script repeatable. Do not run two
mutating processes on the same AL/Runs. Isolated probes use their own project and stop budget.

Separate raw gate/reopen/placed/routed resources and all four timing checks, TNS and coverage. Check
actual effective SDC and clock inventory before interpreting delays. Refer to `td-timing-closure`
for physical fixes. Report functional, synthesis, physical, bitgen and board results independently.

For exact tool/IP/board parameters use the [vendor index](../../../references/vendor/README.md) and
the needed versioned manual; do not pre-read every reference. Pins/programming require the selected
board and explicit authorization, not a successful build. Useful conditional references:
[IP registration](references/ip-instantiation.md), [constraints](references/timing-constraints.md),
[timing analysis](references/timing-analysis.md), [programming](references/debug-and-programming.md).
