# Anlogic TD — Reference Index

Codex defaults new tasks to Release 2026.2 / 6.2.3.210850 at
`C:/Tools/Anlogic/TD_2026.2`; select it explicitly with `--td-root`.
Start with [version selection and changes](td2026-2.md).
The digests and measured tables below retain their **6.2.168116** scope; they are
not an inventory of new commands or defaults. New official PDFs are versioned
under `<repo>/references/vendor/安路科技_TD_技术文档/2026.2/`.

Reference files distilled from the official Tang Dynasty TD 6.2.1 documentation, written so a
future agent can drive the toolchain from TCL without re-reading the PDFs.

Historical measurement toolchain: **Tang Dynasty V6.2.168116**, install root
`C:/Tools/Anlogic/TD_6.2.168116`.

Source references now live in `<repo>/references/vendor/安路科技_TD_技术文档/`;
start with `<repo>/references/vendor/README.md` and `catalog.json`. The retained PDFs,
command tables, configuration JSON and shipped flow scripts preserve their original
bytes. Other-device PDFs and the installed GUI help menu were removed from this
PH1A90 workspace. Cross-family comparisons in these older digests remain historical;
consult the matching official manual or TD installation before using them elsewhere.
Do not load all digests to answer one question.

| File | What it answers |
|---|---|
| `td2026-2.md` | Version selection, process environment, changed clocks/parameters/IP status, document editions and lightweight compatibility evidence for Release 2026.2. |
| `device-database.md` | "which family/package/speed do I pass to `create_project`/`import_device`, what resources does the part have, and which `sim_release` directory do I need?" — the complete db-name → family → package → speed-grade table (28 db-names, 74 packages, 10 families; **every row re-verified against the live tool**), the per-device LUT/DFF/DSP/PLL/ERAM/DRAM/URAM/IO resource table, and the family → simulation-library-directory mapping. |
| `device-pins-ph1a60geg324.md` | "which physical pin do I use?" — full pin map for one package: all 211 fabric I/O grouped by bank, the 24 clock-capable pads (use these for clocks), and LVDS pairs, as `LOCATION=`-ready PE names. Regenerate for any package with `scripts/dump_pins.tcl`. |
| `timing-constraints.md` | "how do I write `.adc` and `.sdc` files?" — ADC `set_pin_assignment` syntax with every attribute and valid value, all supported SDC commands with exact argument lists and realistic examples, the object-query commands and their `-hier`/`-nocase`/`-o`/filter syntax, the valid IOSTANDARD set, and `query_current_package -fio/-clock_io/-lvds/-single_ended` for pin selection. |
| `timing-analysis.md` | "how do I read a TD timing report and do I have timing closure?" — SWNS/STNS/HWNS/HTNS vs WNS/TNS, `report_timing_summary`/`report_timing_path`/`report_qor`/`report_clock_summary`/`report_clock_intersection`/`report_timing_exception`/`report_timing_ignored`/`check_timing`/`update_timing -mode`, what `STA coverage` and `Confidence (Estimated/Placed/Routed)` mean, and a step-by-step closure decision procedure with the knobs to turn when it fails. |
| `flow-and-commands.md` | "what do I type, in what order?" — the end-to-end command reference organised by flow stage with exact syntax and copy-pasteable examples, the three script modes, the stage-ordering rules (`read_adc` before `optimize_rtl`, `read_sdc` before `optimize_gate`, re-read SDC after `legalize_phy_inst`), parameter *effects*, and the **measured** `set_param` database. |
| `debug-and-programming.md` | "how do I insert a logic analyzer, program the part, and make flash images?" — the probe/ChipWatcher flow, JTAG debug access (`JTAG_REG_ACCESS`, `JTAG_AXIS_APB_ACCESS`), the BitWizard tool (`bw.exe` / `bw_commands_prompt.exe`), the 15 device operation modes from `config.json` and their Download-dialog mapping, all programming/download TCL commands, the OneCable hardware requirement, and the Encrypt Tool. |
| `ip-and-libraries.md` | "which IP is available on my part, and how do I instantiate a primitive?" — a compact IP index (SERDES, PCIe, DDR, DSP MACRO, High Speed IO, CGMAC, HXT, MIS, …) with per-family availability, the primitive naming convention per family (`PH1_PHY_*`, `EG_PHY_*` — note **not** `EG4_`, `AL_*`, …), where the primitive templates live, PLL/GSR/global-clock primitives with a complete PH1A PLL instantiation, and the Simulation Libraries Compiler family → library mapping. |
| `ip-instantiation.md` | "how do I put an IP into my design without the GUI?" — the `.ipc` XML mechanism (`add_files` accepts it and registers a real `<IP_FILE>` FileSet), the full `.ipc` format with shipped ECC and PLL examples, the per-IP constraint commands (`read_ip_adc`, `read_sdc -ip`), why `<TD_ROOT>\ip\` is *not* directly usable, and which vendor tools are GUI-only. Includes the headless-but-deferred Design Integrator CLI. |
| `simulation.md` | "how do I simulate this, and do I need ModelSim?" — the four simulation stages and which flow step unlocks each, how to get a routed netlist and a non-empty SDF out of TD, the `sim_release` family→directory→global-reset-model table, the verified 9-file minimal library set for a PH1 logic post-route sim, testbench requirements (GSR instantiation), and headless ModelSim command lines. **Answer: TD has no built-in simulator; ModelSim/Questa 2020 is required for vendor primitives.** |
| `simulation-findings.md` | The raw lab notebook behind `simulation.md`: commands run, errors hit, minimality proofs by file omission, and the exact evidence (decoded frames, SDF load lines). Read it when you need to know *why* a claim in `simulation.md` is true, or when a simulation fails in a way `simulation.md` does not cover. |

---

## Read this first

Three cross-cutting facts that change how you should use all seven files:

1. **`set_param` validates nothing.** A typo in a parameter name or value returns success, prints
   nothing, and has no effect. Gate every parameter assignment behind
   `catch { get_param <step> <param> }` — `get_param`'s return code is the only reliable existence
   test. See `flow-and-commands.md` §4.2.

2. **The parameter tables in SWUG105 are wrong in several places.** The authoritative set is
   **50 registered parameters across 7 stages**, obtained by running the tool and calling
   `report_param -detail` (not by reading the PDF). SWUG105's `rtl reg_threshold` is a ghost that
   appears in the guide's own recommended examples; `place pack_mode` is not registered; three
   documented defaults (`route fix_hold`, `rtl infer_fsm`, `route timing`) differ from reality;
   and the `bitgen` step is not empty. See `flow-and-commands.md` §4.

3. **Ask the tool, not the PDFs.** The install is live and scriptable:

   ```powershell
   & 'C:/Tools/Anlogic/TD_6.2.168116\bin\td_commands_prompt.exe' -nogui <script.tcl>
   ```

   The TCL file is a **positional argument** (`-source <file>` does not work, and `-h` is
   misinterpreted as a filename). Useful probes: `report_param -detail`, `get_param <step>
   <param>`, `help` with no arguments (prints the tool's own usage line for every command),
   `info commands` (returns exactly 740), `list_devices`, `query_current_package -fio`.
   Console capture through a pipe is unreliable — have the script write to a file
   (`set f [open out.txt w]; puts $f ...; close $f`) or pass a script file.

---

## Source map

| Reference file | Primary sources |
|---|---|
| `device-database.md` | live `list_devices`; `<root>\arch\device_resource\device_resource.csv`; `<root>\sim_release\`; SWUG105 Appendix 1 |
| `device-pins-ph1a60geg324.md` | live `query_current_package -fio -clock_io -lvds` for PH1A60GEG324 |
| `timing-constraints.md` | SWUG200 (Timing Constraints UG); SWUG105 §4.3–4.4; TD UG §9.1, §9.2 |
| `timing-analysis.md` | SWUG201 (Timing Tools UG); SWUG105 §4.7–4.8; real `.timing`/`.qor` report files |
| `flow-and-commands.md` | SWUG105 (primary); live `td_commands_all.txt` (740 names); `<repo>/references/vendor/安路科技_TD_技术文档/cmd/help_comment_*.json`; `<repo>/references/vendor/安路科技_TD_技术文档/scripts/*.tcl`; `<repo>/references/vendor/安路科技_TD_技术文档/strategies/official_strategy_ph{1,2}.json`; TD UG §9.6, §9.7; live-tool measurement |
| `debug-and-programming.md` | SWUG111, SWUG110, SWUG113, UG009; `<repo>/references/vendor/安路科技_TD_技术文档/config/config.json`, `cpld_flash.json`; live `help` / arity probes |
| `ip-and-libraries.md` | `<repo>/references/vendor/安路科技_TD_技术文档/IPUG/*.pdf` (retained PH1A guides; other-family PDFs omitted); `<repo>/references/vendor/安路科技_TD_技术文档/UG*_Libraries_Guide_for_HDL_Designs.pdf`; SWUG107 Part C; `<root>\template\verilog\Device-Primitive\`; `<root>\sim_release\` |
| `ip-instantiation.md` | live `add_files` probes; `<root>\board_designs\ANLOGIC\*\al_ip\*.ipc`; SWUG105 §4.1.6/§4.1.7; live `design_integrator.exe` CLI probes |

All `SWUG*`/`UG*`/`IPUG*`/`TD_User_Guide*` references resolve to files under `<repo>/references/vendor/安路科技_TD_技术文档/`.
Paths written as `<root>\...` are in the **TD installation**, not in this skill.

## Conventions used in these files

* **Chinese technical terms** are kept where they are the precise term (command output strings,
  option names, verbatim quotations), with English explanatory prose so an agent can act on them.
* **`[RECONSTRUCTED]`** marks anything inferred rather than stated, with the raw garbled source
  quoted where the PDF text extraction was at fault. Tables that extracted badly are flagged in a
  blockquote at the head of their section.
* **`[LIVE-ONLY]`** marks a command that exists in the live 740-command list but has no PDF
  chapter. **`[PHANTOM — DO NOT USE]`** marks something a PDF documents that does **not** exist in
  TD 6.2.1.
* **Effect text vs value lists.** Parameter *effects* come from TD User Guide §9.6 (SWUG105
  delegates to it explicitly). Parameter *defaults and existence* come from live measurement.
  Where these disagree, measurement wins and the conflict is called out.
