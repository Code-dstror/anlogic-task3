---
name: td-timing-closure
description: Use for physical setup, hold, recovery, or removal timing closure in this repository's Anlogic TD projects. Do not use for RTL-only simulation or document edits.
---

# Physical timing closure

Start with [project rules](../../../fpga_prj/AGENTS.md), actual TOP/ADC/SDC and the selected sync/build/report
scripts. Use `td-build-evidence` to bind the reports. Default TD2026.2 is selected from local environment
and passed explicitly; read [version changes](../anlogic-td-fpga/references/td2026-2.md) when old options are involved.
Long synthesis/P&R stays on server3 through `td-github-control`; small local mapping experiments do not establish closure.

1. Compare all available completed seeds. Group recurring launch/capture domains, endpoints and constraints.
   Inspect the full clock and data portions, logic levels, fanout, cell versus net delay and both corners.
   Different synthesis threads/options can change mapping; estimated WNS/TNS changes alone do not justify
   cancelling a healthy physical run. Do not depend on adding seeds without addressing common causes.
2. Separate real same-domain setup/hold/recovery/removal from asynchronous first-stage or held-bundle paths.
   Prove the actual CDC/ownership protocol before an exception. Scope clocks and real data nets/replicas;
   packed cell names alone can misidentify the bit or module. Added mailbox/snapshot fields need matching
   constraints. Validate nonempty mapped objects first and physical copies after route.
3. For reset-dominated paths inspect assertion, release edge, stop-clock behavior and every consumer type.
   A falling ASR release can improve removal yet leave only half a cycle for combinational READY/data
   qualification. Separating existing synchronous qualification can help, but retain the same first legal
   sampling edge and asynchronous safety. Do not globally flip reset edges or blanket-cut local paths.
4. For congestion/PHY-8155 use actual overflow locations/nets and clock-bank utilization. Slice percentage
   alone neither proves routability nor identifies the conflict. Do not modify a protected IP or a sensor
   clock merely because its warning appears near a failure. Evaluate one evidence-backed RTL, constraint
   or supported native-option change at a time, considering resource and placement cost.
5. Preserve functions, numeric precision and ABI. Retiming must keep held offers, identity and terminal
   ownership; extending a pipeline without matching control is not a valid timing fix. Verify functional
   changes with the independent black-box short-test workflow in `rtl-stream-contract`. Constraint-only
   edits use focused object/path tests and unchanged-path controls, not unnecessary full-frame simulation.
6. Import/rebind checkpoints using the target versioned flow before timing update. Verify real clocks and
   the complete user/IP SDC set; do not clear an active timer or reuse a pre-change report. Run options live
   in the actual AL/native runs, and claimed reuse must match the stage that really ran.

Keep periods and legitimate checks. Do not broaden false paths, disable checks or relax performance to
obtain a nominal PASS. Keep setup, hold, recovery, removal, TNS and constraint coverage separate; sparse
positive margins deserve review. Preserve original failures and describe mapped/local estimates as such.
Final closure requires fresh routed evidence for the new source; board validation remains independent.
