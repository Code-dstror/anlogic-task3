# Anlogic TD 6.2.1 — Timing Analysis & Reports Reference

How to drive TD's static timing analysis, read its reports, and decide whether a design has
closed timing.

Primary source: `SWUG201_Timing_Tools_User_Guide.txt` (SWUG201 v1.1, 2025.01, 115 pp).
Cross-checked against real TD report files produced by the tool:
`tdtest\demo_Runs\phy_1\final_timing.rpt`, `tdtest\final.qor`,
`tdtest\demo_Runs\phy_1\place.qor`, `tdtest\demo_Runs\phy_1\demo_pr.timing`.
TCL syntax cross-checked against `SWUG105_TCL_Command_User_Guide.txt` § 4.7–4.8 and against
the live 740-command list.

> **Extraction warning.** SWUG201 is a GUI-heavy document. Its **tables extracted well** (the
> Clock Summary / Global Status / path-info tables below are verbatim reconstructions of
> interleaved two-column extractions and were then validated against real `.timing` report
> output). Its **screenshots are gone**, so GUI navigation is described but dialog-field
> layouts cannot be reproduced pixel-accurately. Where a field name below appears in a real
> report it is marked ✅; field names that only exist in the GUI are marked (GUI).

---

## 1. The five timing tools

| Tool | Opened from | Answers |
|---|---|---|
| **Timing Wizard** | `Tools → Timing Wizard`, or `FPGA Flow → User Constraints → SDC Constraint` (`Ctrl+Alt+T`) | "what constraints does this design have?" — create/edit SDC constraints, then Apply/Save |
| **Timing Report** | `Tools → Timing Analyzer → Timing Report` | "what are the worst paths and by how much?" |
| **Logic Level Report** | `Tools → Timing Analyzer → Logic Level Report` | "are my combinational depths sane?" |
| **Check-Timing Report** | `Tools → Timing Analyzer → Check Timing` | "is my SDC healthy — anything unconstrained/conflicting?" |
| **Clock Tree Report** | `Design Summary → Timing Summary → Clock Tree Report`, or `Tools → Timing Analyzer → Clock Tree Report` | "what does the clock network look like, and what is the max skew?" |
| **Clock Intersection Report** | `Design Summary → Timing Summary → Clock Intersection Report`, or `Tools → Timing Analyzer → Clock Intersection Report` | "which clock domains talk to each other, and are those crossings constrained?" |

**Availability gates (the same gates the ADC/SDC editors have):**

| Tool | Earliest usable point |
|---|---|
| Timing Wizard | after `Syn Opt → Optimize RTL` + `Open Run` |
| Timing Report / Check-Timing | after any of Generate Gate / Optimize Placement / Optimize Route (report content depends on stage) |
| Logic Level Report | after `Optimize RTL` |
| Clock Tree Report | after `Optimize Gate`, `Optimize Placement`, or `Optimize Route` + `Open Run`. **After Optimize Gate / Placement the report has topology only — no max-skew data.** |
| Clock Intersection Report | after `Optimize Gate` + `Open Run` |

---

## 2. Timing Report structure

### 2.1 Report navigation tree

The Timing Report window has a left-hand `Report Navigation` pane with **8 groups**. A group
whose paths contain a **negative setup or hold slack gets a yellow exclamation icon**.

| Group | Contents |
|---|---|
| `Timing General` | report header: TD version, creation time, device, **STA coverage** ✅ |
| `Timing Setting` | the Timing Option settings used, and the SDC files read ✅ |
| `Timing Status` | **Clock Summary** (per-clock) and **Global Status** (design-wide WNS/TNS) ✅ |
| `Intra-Clock Paths` | launch clock == capture clock; grouped by clock pair, then Max/Min Paths |
| `Inter-Clock Paths` | launch clock != capture clock; same grouping as Intra-Clock |
| `IP Timing Report` | per-IP internal timing: IP hierarchy path → auto-assigned IP instance index → report type (`Input Timing (intra/inter-clock)`, `Output Timing (...)`, `Timing Exception`, …) |
| `Timing Exception Report` | paths covered by `set_max_delay` / `set_min_delay` / `set_multicycle_path` |
| `Ignored Report` | paths removed by `set_false_path` / `set_clock_groups` |

The navigation pane has a filter box — type a group name (e.g. `Max Paths`) to filter.

`Max Paths` = max-delay analysis = **Setup / Recovery**.
`Min Paths` = min-delay analysis = **Hold / Removal**.

### 2.2 Report Option semantics

| Option | Value | Meaning |
|---|---|---|
| `Path Delay Type` | `Max_Min` (fixed) | both max-delay (setup/recovery) and min-delay (hold/removal) are reported |
| `Multi Corner` | `Slow_Fast` (fixed) | both corners analysed |
| `EndPoint per path group` | default 10 | endpoints per path group (maps to `-ep_num`) |
| `Paths per EndPoint` | default 1 | paths per endpoint (maps to `-path_num`) |
| `Include Ignored` | default on | also report false-pathed / clock-group-ignored paths (maps to `-include_ignored`) |
| `Violation Only` | default off | only negative-slack paths; **greys out `Include Ignored`** (maps to `-viol_only`) |
| `Export Timing Report` | — | export as `.txt`, `.rpt`, or `.timing` |
| `Target → From / Through / To` | — | restrict to a path. From/To accept `get_ports`/`get_pins`/`get_regs`/`get_clocks`/`get_cells`; **Through accepts only `get_pins`/`get_nets`**. At least one of From/To must be set. |
| `Target → Logic Level` | default off | off = pick the worst-*slack* path; on = pick the path with the greatest *logic level* |
| `Command` | — | shows the TCL that the GUI would run; copy-pasteable |

**Report naming:** `Flow-stage tag + timing_report + index`. Stage tags:
`Optimize Gate → synthesis`, `Optimize Placement → placed`, `Optimize Route → routed`.
So `synthesis_timing_report_1`, `placed_timing_report_2`, `routed_timing_report_1`, …

### 2.3 Worst-corner analysis model

STA always evaluates the worst case so that a passing result holds across conditions.

**Setup / recovery** (worst case):

| Corner | Source clock path | Data path | Destination clock path |
|---|---|---|---|
| Slow | Slow.Max | Slow.Max | Slow.Min |
| Fast | Fast.Max | Fast.Max | Fast.Min |

**Hold / removal** (worst case):

| Corner | Source clock path | Data path | Destination clock path |
|---|---|---|---|
| Slow | Slow.Min | Slow.Min | Slow.Max |
| Fast | Fast.Min | Fast.Min | Fast.Max |

Real report confirmation (✅ from `final_timing.rpt`):

```
Check Status
-------------
Corner   | Max      Min
------------------------------------
Slow     | yes      yes
Fast     | yes      yes
```

---

## 3. Reading the report header — STA coverage & Confidence

Real header from a routed PH1A60GEG324 design (✅):

```
Created by          : Tang Dynasty v6.2.168116
                    : Copyright (c) 2012-2025 Anlogic Inc.
Generated           : Fri Sep 11 21:27:42 2026

Top Model           : top
Device              : PH1A60GEG324
Speed               : 3
STA coverage        : 100.00%
Constraint File     : C:/Work/td-example/demo/demo.sdc;
Confidence          : Routed
Check Corner        : Both (Slow and Fast)
CRPR Enabled        : Yes
Report Scheme       : 10 end point(s) per path group, 1 path(s) per end point
```

| Field | Meaning |
|---|---|
| `Top Model`, `Device`, `Speed` | the elaborated top and the imported device/package/speed |
| **`STA coverage`** | **the fraction of the design's timing paths that were actually analysed.** 100 % means every path was covered by some clock constraint. A value below 100 % means some paths have no clock reaching them and are **invisible to STA** — they are neither passing nor failing. Treat < 100 % as a red flag: find the uncovered logic (usually a gated/derived clock that was never declared, or an unconstrained input) and declare the missing clock. |
| **`Confidence`** | **how physically accurate the delay numbers are, i.e. which flow stage produced them.** Values in ascending trust: `Estimated` (pre-place, gate-level wire-load estimates), `Placed` (post-placement, real cell locations but estimated routing), `Routed` (post-route, real interconnect delays). The GUI's stage tags map as `Optimize Gate → Estimated/synthesis`, `Optimize Placement → Placed`, `Optimize Route → Routed`. **Only a `Routed` report can be used to declare timing closure**; `Estimated` and `Placed` reports are for steering the flow, not for sign-off. |
| `Constraint File` | the SDC file(s) in effect |
| `Check Corner` | `Both (Slow and Fast)` is the default (no `-check_corner`); can be narrowed to one corner |
| `CRPR Enabled` | Clock Reconvergence Pessimism Removal. `Yes` means common-path pessimism is being removed. |
| `Report Scheme` | `-ep_num` / `-path_num` in effect |

---

## 4. Timing Status — SWNS / STNS / HWNS / HTNS and WNS / TNS

### 4.1 Global Status (design-wide) ✅

Real report snippet:

```
Timing Status
--------------------
	SWNS: 15.447ns, STNS: 0.000ns
	HWNS: 0.170ns, HTNS: 0.000ns
	Period Check WNS: 0.000ns
```

| Field | Full name | Meaning |
|---|---|---|
| `WNS` | Worst Negative Slack | the most negative slack over **all** paths of that check type. If ≥ 0 the design meets that check. |
| `TNS` | Total Negative Slack | the **sum** of all negative slacks. 0 means no violations at all. |
| `SWNS(ns)` | Setup WNS | worst setup slack (per clock, or global) — **negative (shown red) ⇒ that clock domain has setup violations** |
| `STNS(ns)` | Setup TNS | sum of all negative setup slacks; **0 if every path has slack ≥ 0** |
| `HWNS(ns)` | Hold WNS | worst hold slack; negative ⇒ hold violations |
| `HTNS(ns)` | Hold TNS | sum of all negative hold slacks; 0 if none |
| `Period Check WNS` | — | worst slack of the clock-period (min-period) check, i.e. whether the clock tree itself can run at the constrained frequency |

### 4.2 Clock Summary (per clock) ✅

Real report snippet:

```
Clock Summary
--------------------

       Clock-Id:       C-Freq       Fanout   Clock-Name
--------------------------------------------------------------------------------
           clk0:       50.000           54   sys_clk
--------------------------------------------------------------------------------

       Name    Type    Rise(ns) Fall(ns) C-Period(ns) C-Freq(MHz) R-Period(ns) R-Freq(MHz) \
       SWNS(ns) STNS(ns) HWNS(ns) HTNS(ns) Skew(ns) Fanout Max-Level CC-From CC-To
       clk0  Inferred GCLK  0.000  10.000   20.000  50.000   4.553  219.635 \
       15.447  0.000  0.170  0.000   0.055   54   5   no   no
```

| Column | Meaning |
|---|---|
| `Name` / `Clock-Id` | clock name |
| `Type` | `Inferred` (software-inserted clock buffer), `User` (user-instantiated clock buffer), `Local` (routed on local interconnect). Real values look like `Inferred GCLK` |
| `C-Freq(MHz)` | **C**onstraint frequency — the frequency implied by the SDC period |
| `C-Period(ns)` | **C**onstraint period — the SDC period |
| `R-Period(ns)` | **R**eport min period — the smallest period the design can actually run at, as computed by STA |
| `R-Freq(MHz)` | **R**eport fmax — the maximum frequency the design can actually run at |
| `SWNS` / `STNS` / `HWNS` / `HTNS` | see §4.1, but **scoped to this clock domain** |
| `Skew(ns)` | clock skew |
| `Fanout` | number of loads driven by the clock |
| `Max-Level` | maximum logic level in this clock domain |
| `Rise(ns)` / `Fall(ns)` | clock rising / falling edge times |
| `CC-From` | has path(s) **from** a cross-domain clock (this clock is the launch clock of a CDC path) |
| `CC-To` | has path(s) **to** a cross-domain clock (this clock is the capture clock of a CDC path) |

**Three notes the tool itself prints under the Clock Summary — memorise these:**

```
*   Clock R-Period data only takes intra-clock timing. SWNS/STNS/HWNS/HTNS take both
    intra-clock and inter-clock timing.
*   If there is mismatch between R-Period and SWNS, check inter-clock timing of this clock
    as capture clock.
*   SWNS/STNS/HWNS/HTNS of timing exception (SMCP/SMD) only counted in global Timing Status,
    not counted in Clock Summary.
```

Consequences:

1. `R-Period` **ignores** inter-clock paths; SWNS/STNS/HWNS/HTNS **include** them. A clock can
   show a "good" `R-Period` and a bad `SWNS`.
2. If `R-Period` and `SWNS` disagree, look at the **Inter-Clock Paths** group with this clock as
   the **capture** clock.
3. **`SWNS`/`STNS`/`HWNS`/`HTNS` exclude timing exceptions** (multicycle / max-min delay). A
   design can have clean Clock Summary numbers and still be failing on exception-constrained
   paths. `Global Status` (`WNS`/`TNS`) is the field that includes exceptions — **always check
   both**. The design-wide `WNS`/`TNS` covers *all* paths including `MCP`/`SMD` exceptions;
   Clock Summary is per-clock and exception-free.

Mnemonic: **C** = constraint (what you asked for), **R** = report (what you got).
`R-Freq > C-Freq` ⇒ slack to spare. `R-Freq < C-Freq` ⇒ the design is too slow for its
constraint.

### 4.3 Path-group statistics ✅

Per path group (Intra-Clock or Inter-Clock), each `Max`/`Min` entry shows:

```
Path Group     :     sys_clk -> sys_clk
Type           :     Self
From Clock     :     sys_clk
To Clock       :     sys_clk
Min Period     :     4.553ns
Fmax           :     219.635MHz

Statistics:
Max   : SWNS  15.447ns, STNS  0.000ns,   0 Viol Endpoints,   99 Total Endpoints,  335 Paths Analyzed
Min   : HWNS   0.170ns, HTNS  0.000ns,   0 Viol Endpoints,   99 Total Endpoints,  335 Paths Analyzed
```

`Type: Self` = intra-clock; other types are inter-clock.
**`Paths Analyzed` and `Total Endpoints` are your coverage evidence** — if `Paths Analyzed` is 0
for a domain you believe has logic, that logic is unconstrained (see `STA coverage`).

### 4.4 Per-path columns

| Column | Meaning |
|---|---|
| `Name` | path index |
| `Start_Point` | chip input pin or a sequential cell's clock pin |
| `End_Point` | chip output pin or any non-clock input pin of a sequential cell |
| `Launch_Clock` | data-launching clock |
| `Capture_Clock` | data-capturing clock |
| `Check_Type` | `Setup`, `Recovery`, `Hold`, `Removal` |
| `Check_Corner` | `fast` or `slow` |
| `Slack` | timing margin; **negative = violation (shown red)** |
| `Logic_Level` | number of logic levels on the data path |
| `Max_Fanout` | maximum clock fanout on the path |
| `Requirement` | required-time budget |
| `Clock-Skew` | difference in clock arrival at the two registers |
| `Data-Path-Delay` | total data path delay (cell delay + net delay) |
| `Cell_perc` | cell (node) delay as a percentage of total delay |
| `Net_perc` | routing delay as a percentage of total delay |

Expanding a path shows five collapsible sections:

| Section | Contents |
|---|---|
| `Summary` | Slack, Begin Point, End Point, Budget, Data Path delay, Clock Skew, Logic Level |
| `Launch Clock` | delay from clock source to the start register's clock pin: source-to-definition-point delay, GCLK delay, SCLK delay, input pin delay, IO PAD buffer delay, net delay |
| `Data` | delays from the start register's output to the end register: LUT delays of intermediate nodes, net delays |
| `Capture Clock` | delay from clock source to the end register's clock pin, same decomposition as Launch Clock |
| `Other` | required setup/hold time at the endpoint, clock uncertainty (tool-added **and** user-constrained), and CRPR (Clock Reconvergence Pessimism Removal) |

Per-node delay-table columns (for the detail tables inside Data/Launch/Capture):

| Column | Meaning |
|---|---|
| `Delay Type` | delay type of the node/row |
| `Location` | cell coordinate |
| `Incr` | incremental delay at this node |
| `Path` | cumulative delay up to this node |
| `Level` | logic level |
| `Netlist Infor` | the corresponding netlist object |

**Path-name separator syntax:** `/` = hierarchy, `|` = parallel, `.` = membership.

---

## 5. Timing Exception Report & Ignored Report

### 5.1 Timing Exception Report

Shows what `set_multicycle_path`, `set_max_delay`, `set_min_delay` actually did. Tree:
`Constraint*` (number) → `Active` / `Shadowed` / `Ignored` Paths → `Max` / `Min` Paths.

If a constraint has no shadowed paths, only `Active Paths` is shown.

| Column | Meaning |
|---|---|
| `Constraint` | the SDC command text |
| `Total Path` | total paths under that constraint |
| `Active` | paths where the constraint is actually in force |
| `Shadowed` | paths masked by a **higher-priority** SDC command |
| `Ignored` | paths within the constraint that a false path removes from analysis |

Real example from `demo_exception.timing` in the reference run: the report lists the
constraint, a "higher priority SDC command" column, and a `set_false_path` column — i.e. it
names *which* command shadowed or ignored each subset.

### 5.2 Ignored Report

Shows what `set_false_path` and `set_clock_groups` removed. Two top-level categories:

* `Async/Exclusive Groups` → paths ignored by `set_clock_groups`. Sorted by
  launch-clock → capture-clock pairs. Only `Start-Point`, `End-Point`, `Launch-Clock`,
  `Capture-Clock`, `Check-Type` and the data-path info are reported (no slack — the path is not
  analysed).
* `False Path` → paths ignored by `set_false_path`. Split by **source**: `Flow` (user SDC) and
  `IP` (SDC shipped with an IP). Under `Flow`, paths are grouped by `Constraint*` with the same
  Max/Min and Active/Shadowed/Ignored statistics as above.

---

## 6. Check-Timing Report

The SDC health check. Answers: unconstrained endpoints, conflicting constraints, missing
clocks, bad references.

* GUI: `Tools → Timing Analyzer → Check Timing`; each report window is named
  `check_timing_report_x` (x = open order, from 1). Multiple windows may be open.
* TCL: `check_timing [-file <file_path_name>] [-verbose]`
  * `-file` — write the report to a text file
  * `-verbose` — show full detail

```tcl
check_timing -verbose
check_timing -file ./check_timing.rpt
```

**Run this immediately after reading your SDC and again after `legalize_phy_inst`.** A clean
`check_timing` plus `STA coverage : 100.00%` is the evidence that your constraint set is
complete. Anything else means the timing report is not telling you the whole story.

---

## 7. Logic Level Report

Answers "is my combinational depth reasonable?"

* GUI options: `Report Name` (default `logic_level_report_x`), `Default` (statistics over all
  paths of each clock) or `Worst` (only the N endpoints with the worst setup slack; N default
  1, range 1–10000), `Export Timing Report`, `Command`.
* TCL: `report_logic_level [-h/-help] -file <file_path_name> [-worst_n <int>] [-no_header]`
  * **`-file` is mandatory** — the output is too large for the console
  * `-worst_n <int>` — only the N worst-setup-slack paths
  * `-no_header` — drop the version/device header

```tcl
report_logic_level -file ./gate.logiclvl
report_logic_level -file ./gate.lvl -worst_n 20
```

Report layout: rows = clock names; columns = logic level `0 .. 30+`; cell value = the number of
paths at that level. Example from the doc: `clk_156` has 89 paths at level 0, 35 at level 1, 10
at level 2, 2 at level 3, 4 at level 4, 0 at level ≥ 5.

Blue numbers are clickable and list up to 10 paths with `slack`, `Logic_Level`, `Max_Fanout`,
`Start-Point`, `End-Point`, `Launch-Clock`, `Capture-Clock` — same fields as the Timing Report.

**How to act on it:** a max level well above the `Max-Level` column in Clock Summary, or a long
tail into the 20–30 range, means deep combinational logic and a fragile fmax. Remedies:
`logic_level_opt on` (place), `opt_timing high` (place), `map_mode logic_level_prior` /
`map_strategy 2..5` (gate), `min_ripple_len` tuning, or RTL pipelining.

---

## 8. Clock Tree Report

Shows the clock network topology and the max skew.

**Availability:** Clicking through `Open Run` after Optimize Gate, Optimize Placement or
Optimize Route. **After Optimize Gate / Optimize Placement the report contains only the
topology — no max-skew values.**

Tree structure: level 1 = clock-tree name (with the number of clocks in parentheses);
level 2 = each clock (frequency and type in parentheses); level 3 = `TOPOLOGY` and `MAX_SKEW`.

### 8.1 TOPOLOGY

Describes the clock network level by level, driven-pin by driven-pin. Terminal sequential-cell
clock pins are folded into two levels:

* Level 1 — clock path type:
  * `GLOBAL_NETWORK` — routed on the global clock network
  * `LOCAL_NETWORK` — routed on local interconnect
  * `NONCLOCK` — the terminal pin is not a clock function
* Level 2 — the logic cell the clock enters (`MSLICE`, `LSLICE`, `ERAM`, `PLL`, …)

The GUI annotates nodes: e.g. "clock enters IOB from `.ipad`, exits `.di`, reaches PLL
`.refclk`; PLL has `.clkc[0]` and `.clkc[1]` outputs" (LOCAL NETWORK), and "clock leaves PLL
`.clkc[0]`, passes `bufg` into the PLL feedback network, drives PLL/ERAM/LSLICE — GLOBAL
NETWORK".

### 8.2 MAX_SKEW

`MAX SKEW` = (longest source→terminal delay) − (shortest source→terminal delay), split into
`MAX RISE SKEW` and `MAX FALL SKEW`. Pin sets are labelled:

| Label | Meaning |
|---|---|
| `FASTEST` | pins with the shortest source→terminal delay |
| `SLOWEST` | pins with the longest source→terminal delay |
| `MUTUAL` | pins whose longest and shortest delays are equal |

**Caveat printed by the tool:** `MAX_RISE_SKEW` / `MAX_FALL_SKEW` values in parentheses will not
exactly equal `SLOWEST − FASTEST` because of CRPR (common-path pessimism removal).

### 8.3 Clock Tree Options / Property

* `Clock Tree Options → Visibility`: toggle `Show Topology` / `Show Max Skew`; `Filter Clock By`
  narrows to a clock type; `Apply` to commit, `Reset` to restore both the Visibility and Colors
  panes.
* `Clock Tree Options → Colors`: double-click a color cell to recolour a node class.
* Find box: search by `Clock`, `Pin`, `Net`, or `Clock Group`.
* `Property` pane (top right, follows the selected node):

| Property | Meaning |
|---|---|
| `name` | node name |
| `driver` | driving node |
| `arc_type` | node attribute |
| `net` | connected net |
| `inst` | cell instance name |
| `Inst_loc` | cell coordinate |
| `Delay(slow corner)` | node delay at the slow corner |
| `Delay(fast corner)` | node delay at the fast corner |

**How to act on it:** large max skew on a source-synchronous or multi-bank clock means the
clock is using local interconnect. Consider `set_clock_route_enforce {<net>}` to force it onto
the dedicated global clock network (see `timing-constraints.md` § 4.8). Conversely, a design
with more clocks than global-clock resources needs `set_clock_route {<net>}` on *every* clock
that must not use the global network.

---

## 9. Clock Intersection Report

Answers "which clock domains interact, and is every crossing constrained?"

**Availability:** after Optimize Gate + `Open Run`.

Layout: bottom = `Clock Intersection` data table (source clock → destination clock path
information); top = N×N grid visualisation.

Data table controls: a search box (default matching rule `Case Insensitive, Regular …`), plus
`Show Max Data`, `Show Min Data`, `Slow Corner`, `Fast Corner` toggles. Toolbar on the grid view
supports zoom/reset.

Uses:

* **Unexpected intersection** (two domains you believed asynchronous show up with real paths)
  ⇒ your `set_clock_groups` / `set_false_path` is missing or mis-scoped. Cross-check against
  `CC-From` / `CC-To` in Clock Summary.
* **Missing intersection** (a domain pair that should interact shows nothing) ⇒ paths are
  already false-pathed, or the two clocks were never both declared.
* Cross-reference the TCL equivalent, `report_clock_intersection`, in scripted flows.

---

## 10. TCL command reference for timing reports

All syntax verbatim from SWUG105 § 4.7–4.8; every command verified present in the live
740-command list.

### 10.1 `report_timing_summary` — whole-design timing report

```
report_timing_summary [-h/-help] [-file <file_path_name>] [-ep_num <int>] [-path_num <int>] \
                      [-include_ignored] [-viol_only] [-no_header]
```

| Option | Meaning |
|---|---|
| `-file <f>` | write to a text file (any extension) |
| `-ep_num <int>` | endpoints shown per path group; default **10** |
| `-path_num <int>` | paths shown per endpoint; default **1** |
| `-include_ignored` | also report paths excluded by `set_false_path` / `set_clock_groups` |
| `-viol_only` | only negative-slack paths |
| `-no_header` | drop the version/device header |

```tcl
report_timing_summary -file route.timing
report_timing_summary -file viol.rpt -viol_only -ep_num 50
report_timing_summary -file place_timing_smry.rpt
```

In the GUI this is what `Export Timing Report` produces; `.txt`, `.rpt` and `.timing` are all
accepted extensions.

### 10.2 `report_timing_path` — targeted path report

```
report_timing_path [-h/-help] [-file <file_path_name>] [-ep_num <int>] [-path_num <int>] \
                   [-from <startpoint>] [-through <thrupoint>] [-to <endpoint>] [-no_header]
```

| Option | Accepted collections |
|---|---|
| `-from <startpoint>` | `get_pins` / `get_regs` / `get_ports` / `get_cells` / `get_clocks` |
| `-through <thrupoint>` | `get_pins` / `get_nets` / `get_cells` — **note the difference from the GUI**, which allows only pins/nets |
| `-to <endpoint>` | `get_pins` / `get_regs` / `get_ports` / `get_cells` / `get_clocks` |

```tcl
report_timing_path -file a2b.timing -from [get_regs {datgen_din[0]}]
report_timing_path -file clk_to_out.rpt -from [get_clocks clk_0] -to [get_ports {dout[*]}]
report_timing_path -file thru.rpt -through [get_nets {dpram_top0/lfsr_done}]
```

Related: `print_timing_paths`, `print_timing_paths2`, `report_timing`, `report_hyper_path`,
`report_hyper_paths`, `report_path_skew`, `rpt_skew`, `report_abnormal_timing_target`,
`get_path_delay`, `highlight_by_slack`, `print_timing_graph`, `print_timing_arcs`.

### 10.3 `report_qor` — QOR metric table + automated advice

```
report_qor -step <gate/place/route> [-file <file_path_name>]
```

`-step` is **mandatory**. Prints the QOR table for the stage and performs automated QOR analysis
with optimisation suggestions.

Where the reports land (matches GUI behaviour):

```
<project_name>_Runs/syn_*/gate.qor
<project_name>_Runs/phy_*/place.qor
<project_name>_Runs/phy_*/route.qor
```

`optimize_gate` / `pack` / `place` / `route` **call `report_qor` automatically**. In non-project
mode the QOR report lands in the current directory.

```tcl
report_qor -step gate  -file gate.qor
report_qor -step place -file place.qor
report_qor -step route -file route.qor
```

Real `route.qor` content (✅):

```
-----------------------------------------------------------
| QoR metrics               |         value               |
-----------------------------------------------------------
| Timing                    |                             |
|     Setup WNS             |        15447                |
|     Setup TNS             |            0                |
|     Num of violated S-EP  |            0                |
|     Hold WNS              |          170                |
|     Hold TNS              |            0                |
|     Num of violated H-EP  |            0                |
-----------------------------------------------------------
| Routing Resource          |                             |
|     Wire length           |        11248                |
-----------------------------------------------------------
| Utilization               |                             |
|     #slices               |           82                |
|     slices percentage     |        0.21%                |
|     #RAMs                 |            0                |
|     #DSPs                 |            0                |
|     #DRAMHARDCON          |            0                |
-----------------------------------------------------------
Report route stage QoR done.
```

**Units gotcha:** the QOR numbers are in **picoseconds**, not nanoseconds. `Setup WNS = 15447`
is 15.447 ns — which is exactly the `SWNS: 15.447ns` in the matching `.timing` report. Positive
= passing margin (in this report's convention), `Num of violated S/H-EP` = number of violated
setup/hold endpoints and must be **0**.

### 10.4 `report_clock_intersection`

```
report_clock_intersection [-h/-help] [-file <file_path_name>]
```

"Prints the clock-interaction report, showing the health of cross-clock-domain timing
constraints and timing-analysis risk." (打印时钟交互报告，显示跨时钟域路径的时序约束健康程度，
以及时序分析风险。)

```tcl
report_clock_intersection -file clk_inter.rpt
```

### 10.5 `report_clock_summary`

```
report_clock_summary [-h/-help] [-file <file_path_name>] [-clocks <clock_list>]
```

Prints the **clock-tree structure**. `-clocks` narrows to one or more clocks (braced list with
spaces, or a `get_clocks` collection).

```tcl
report_clock_summary -file clk_smry.rpt
report_clock_summary -file pll_smry.rpt -clocks [get_clocks {pll_1 pll_2 pll_3}]
```

### 10.6 `report_timing_exception`

```
report_timing_exception [-h/-help] [-file <file_path_name>] [-ep_num <int>] [-path_num <int>] \
                        [-viol_only] [-no_header]
```

Prints the paths affected by `set_max_delay` / `set_multicycle_path`, **including paths that a
`set_false_path` has overridden**. This is the report that reveals constraints which are being
silently shadowed.

```tcl
report_timing_exception -file exception.timing
report_timing_exception -file mcp_viol.rpt -viol_only
```

### 10.7 `report_timing_ignored`

```
report_timing_ignored [-h/-help] [-file <file_path_name>] [-ep_num <int>] [-path_num <int>] \
                      [-no_header]
```

Prints the paths removed by `set_false_path` / `set_clock_groups`. No `-viol_only` (ignored
paths have no slack). **Always review this file once** — it is the list of paths you have
declared "don't care"; a mis-typed filter here creates hidden, unverified logic.

```tcl
report_timing_ignored -file ignored.timing
```

### 10.8 `update_timing`

```
update_timing [-mode <basic/manhattan/final>] [-check_corner <fast/slow>]
```

Refreshes the timing DB. **Required after `import_db`, and after any netlist change**, before
doing STA.

| `-mode` | Stage it corresponds to |
|---|---|
| `basic` | gate (post-synthesis) |
| `manhattan` | place (post-placement, Manhattan wire estimates) |
| `final` | route (post-route, real delays) |

`-check_corner fast` or `slow` restricts the analysis corner; **omitting it analyses both fast
and slow corners** (the normal choice).

```tcl
update_timing -mode basic
update_timing -mode manhattan
update_timing -mode final
update_timing -mode final -check_corner slow
```

The `-mode` choice must match your stage, or the report's `Confidence` value will not reflect
reality. Canonical scripted sequence (verbatim from SWUG105 § 3.2.2):

```tcl
place
report_qor -step place -file place.qor
update_timing -mode manhattan
report_timing_summary -file place_timing_smry.rpt

route
export_db ./route.db
report_qor -step route -file route.qor
report_area -file route.area
update_timing -mode final
report_timing_summary -file route_timing_smry.rpt
```

### 10.9 `check_timing`

```
check_timing [-file <file_path_name>] [-verbose]
```

See §6.

### 10.10 Related design-analysis commands

| Command | Purpose |
|---|---|
| `report_area [-file <f>] [-verbose] [-io_info]` | area report; `-io_info` adds detailed IO info |
| `report_logic_level [-h] -file <f> [-worst_n <int>] [-no_header]` | see §7 |
| `report_hfn <rtl\|gate\|place\|route> [-net <n>] [-limit <int>] [-min <int>] [-max <int>] [-file <f>] [-timing]` | high-fanout nets; default prints the top 20 by fanout. `-net` and `-limit`/`-min` are mutually exclusive |
| `report_analysis <mode> [-timing] [-congesiton] [-file <f>] [-max_path_num <n>]` | combined timing/congestion analysis note: the option is spelled `-congesiton` in the doc — `[RECONSTRUCTED]`, verify with `report_analysis -help` before relying on it |
| `report_cells <cell_name> [-help] [-connection] [-pin_loc] [-mode <basic/manhattan/final>] [-timing] [-hold]` | per-cell report |
| `report_nets <net_name> [-help] [-connection] [-mode <basic/manhattan/final>] [-timing] [-hold] [-of_pins <pin>]` | per-net report |
| `report_route_status`, `report_placement_status`, `report_design_status`, `report_design_cell_num`, `report_ram_utilization`, `report_clock_utilization`, `report_congestion`, `report_wirelength`, `report_hierarchy_stats`, `print_grid_utilization` | status/utilization reports |
| `flow_status`, `export_flow_status`, `export_flow_script` | flow state inspection |

```tcl
report_area -file ./place.area -io_info
report_hfn place -net {rst} -timing
report_hfn route -min 100 -timing
report_cells {o_dat_reg[1]} -connection -mode manhattan -timing -hold
report_nets {datgen_din[0]} -connection -mode manhattan -timing -hold
report_analysis final -congestion -file ./congestion_analysis.rpt
```

---

## 11. Did the design close timing? — decision procedure

Work through this every time, in order.

### Step 1 — is the analysis trustworthy?

```
[ ] Confidence        : Routed          <- Estimated/Placed reports cannot be sign-off
[ ] STA coverage      : 100.00%
[ ] Check Corner      : Both (Slow and Fast)
[ ] CRPR Enabled      : Yes
[ ] Report Scheme     : matches what you asked for (-ep_num / -path_num)
```

If `Confidence` is not `Routed`, route the design first and re-report.
If `STA coverage` < 100 %, `check_timing -verbose` and find the unconstrained logic
(a clock you never declared is the usual cause). **Do not** declare closure on a partial
coverage report.

### Step 2 — read the numbers

| Where | Field | Pass condition |
|---|---|---|
| `Timing Status` | `SWNS`, `HWNS` | ≥ 0 |
| `Timing Status` | `STNS`, `HTNS` | **= 0** |
| `Timing Status` | `Period Check WNS` | ≥ 0 |
| `Global Status` | `Setup WNS`, `Hold WNS` | ≥ 0 |
| `Global Status` | `Setup TNS`, `Hold TNS` | **= 0** |
| `Global Status` | violated S-EP / H-EP | **= 0** |
| `route.qor` | `Num of violated S-EP` / `H-EP` | **= 0** |
| Clock Summary | `R-Freq` ≥ `C-Freq` for every clock | yes |

**TNS = 0 and violated-endpoint count = 0 are the real closure criteria.** A design with
`WNS = +0.01 ns` but `TNS = −40 ns` is *not* closed — it has dozens of marginal paths.
Clock Summary alone is insufficient (see the three tool notes in §4.2): exceptions are excluded
there, so also check `Global Status` and `report_timing_exception`.

### Step 3 — when it did NOT close, in this order

1. **Re-check the constraints, not the design.**
   * `check_timing -verbose` — unconstrained/conflicting SDC.
   * `report_timing_exception -file exc.rpt` — constraints shadowed by higher-priority commands
     (a `Shadowed` count means a constraint is doing nothing).
   * `report_timing_ignored -file ign.rpt` — too much false-pathed? A wrong glob in a
     `set_false_path` hides real paths and shows a fake pass.
   * Over-strict constraints: a clock period tighter than the part can run, `set_clock_uncertainty`
     larger than jitter requires, `set_input_delay`/`set_output_delay` copied from another board.
   * A missing `set_clock_groups -asynchronous` makes the tool try to meet an impossible
     cross-domain relationship.
2. **Is it setup (max) or hold (min)?**
   * `SWNS`/`STNS` negative ⇒ setup. Fix with placement/routing effort, logic-depth reduction,
     retiming of the RTL, or a looser (but still correct) period.
   * `HWNS`/`HTNS` negative ⇒ hold. Turn on hold fixing (see below); large hold violations
     usually mean a genuinely broken constraint or a short-path/clock-skew problem, not just
     "needs effort".
3. **Turn on the appropriate knobs** (all via `set_param`; full inventory in
   `flow-and-commands.md`):

   | Symptom | Knobs (all verified-registered; see `flow-and-commands.md` §4.1b) |
   |---|---|
   | Setup failing, general | `set_param place effort high`; `set_param place opt_timing high` / `ultra`; `set_param place post_place_opt high`; `set_param route post_route_opt high` |
   | Logic level too deep | `set_param place logic_level_opt on`; `set_param gate map_mode logic_level_prior`; `set_param gate map_strategy 2..5`; `set_param rtl min_ripple_len <n>` |
   | Hold failing | `set_param route fix_hold on` (or `High`, **PH2 only**); `set_param route hold_fix_iteration <n>`; re-run `fix_hold` standalone after `import_db route.db` |
   | Macro-related critical paths | `set_param place macro_performance <dsp_crit_path\|ram_crit_path\|dsp_ram_crit_path\|…>` |
   | High-fanout net on the critical path | `set_param place hfn_opt_effort high`; `set_param place max_fanout <n>` |
   | Congestion causing failures | `set_param place pr_strategy <n>`; `set_param route effort routability` |
   | Routing takes too long / never converges | `set_param route timing off` drops timing and routes for connectivity only; `timing normal` (the default) **stops as soon as setup converges**; `timing greedy` maximises margin at high cost |
   | Nothing converges | Enable seeds (`set_param flow enable_seed on` + `set_seed_param`); raise the place/route effort knobs above; use the `Timing*` strategy packages as a **guide for which individual params to set** |
   | Can't afford the runtime | `RuntimeOptimize` strategy is explicitly **not** for closure — "时序大概率不能收敛，仅用作布线尝试" |

   > **Do not put these in the table — they are NOT registered and will silently do nothing:**
   > `place shifter_opt`, `place crit_path_opt`, `place timing_driven_mode`,
   > `place aggressive_opt`, `place enhanced_beeline_opt`, `rtl resource_sharing`,
   > `rtl shifter_style`, `rtl retiming`, `place pack_mode`, `gate mapper_lut_delay`,
   > `gate merge_tiny_lut`. For "shifter paths are critical", use
   > `set_param rtl infer_shifter on` (registered) or `gate map_mode logic_level_prior`.
   >
   > `pr_strategy` numeric **ranges are not enforced** — `get_param`/`set_param` accept 999 and
   > 18 without complaint. Treat any documented range as advisory and validate by measuring
   > WNS, not by trusting the tool to reject a bad value.
   >
   > Applicability: `place opt_timing` and `place logic_level_opt` are **PH1/PH2 only**;
   > `route fix_hold High` and `place pack_mode` are **PH2 only**. Do not recommend them for
   > EF2/EF3/EF4/EG4/SF1/SF2.
4. **Post-route targeted re-optimisation** without re-running the flow:

   ```tcl
   import_db route.db
   phys_opt -post_route -effort high     ;# -effort low/medium/high/ultra, default medium
   fix_hold                              ;# standalone post-route hold fix
   update_timing -mode final
   report_timing_summary -file after_physopt.timing
   ```

   Note `phys_opt` requires `-post_route` (mandatory option).
5. **Multi-seed / multi-run.** `enable_seed on` + `set_seed_param -num <n> -jobs <n>` explores
   layout/routing seeds; `save_best_bits` then copies the best-timing bitstream into
   `<project>_Runs/best_result`. See `flow-and-commands.md`.
6. **Last resort: the design itself.** Deep logic needs pipelining; a too-fast clock needs a
   different device or a PLL change; a hold violation on an asynchronous interface needs the
   correct `set_false_path`/`set_clock_groups` rather than more optimisation.

### Step 4 — sign-off evidence to keep

```
route_timing_smry.rpt     <- report_timing_summary -file, Confidence: Routed, STA coverage 100%
route.qor                 <- report_qor -step route, violated EP = 0
exc.rpt                   <- report_timing_exception (no unexpected Shadowed)
ign.rpt                   <- report_timing_ignored (reviewed)
check_timing.rpt          <- check_timing -verbose (clean)
```

---

## 12. Gaps and uncertainties

* **`Confidence` values.** The exact token set is confirmed only from a real report:
  `Routed` ✅. `Estimated` and `Placed` are the stage-corresponding values implied by the
  GUI's `synthesis` / `placed` / `routed` report-name tags and by the `update_timing -mode
  basic/manhattan/final` mapping. SWUG201 itself never prints the word "Confidence" — that
  field is only in the generated report header. Treat `Estimated`/`Placed` as
  `[RECONSTRUCTED]` names but the *concept* (three stages, ascend in trust) as documented.
* **`STA coverage`** is named in SWUG201 § 3.1.3.1 ("STA coverage 即静态时序分析覆盖率") but the
  document never states the coverage formula or what a sub-100 % value implies. The
  interpretation in §3 (fraction of paths analysed; < 100 % means invisible paths) is
  `[RECONSTRUCTED]` from the field name plus the tool's path-count reporting. Verify against a
  real design with a deliberately undeclared clock before relying on it.
* **QOR units.** SWUG201/SWUG105 do not state that QOR timing metrics are in picoseconds. This
  was established by matching `route.qor`'s `Setup WNS 15447` against `final_timing.rpt`'s
  `SWNS: 15.447ns` on the same design — treat as verified for the route stage, and check the
  matching `.timing` file if a QOR number looks off by 1000×.
* **`report_analysis -congesiton`** — the option is misspelled in SWUG105. It is reproduced
  verbatim above rather than "corrected". Run `report_analysis -help` to get the live spelling.
* **SWUG201's GUI chapter (§2, Timing Wizard) describes the same SDC commands as
  `timing-constraints.md`.** Constraint semantics are not repeated here; see that file.
* **`-viol_only` on `report_timing_ignored` does not exist** (ignored paths have no slack), and
  `-include_ignored` does not exist on `report_timing_path` — the option sets differ per command
  in the source and are transcribed exactly as documented.
* **Timing Report's `Report Navigation` group count is stated as 8** in SWUG201 § 3.1.3. The
  list above enumerates 8 (General, Setting, Status, Intra-Clock, Inter-Clock, IP, Exception,
  Ignored) which matches.
