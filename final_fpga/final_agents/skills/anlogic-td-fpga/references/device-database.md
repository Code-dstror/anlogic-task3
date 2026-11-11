# Anlogic TD 6.2.1 — Device Database Reference

Authoritative device/package/speed/resource lookup for driving the TD toolchain
(`create_project`, `import_device`, `set_device`, simulation library selection).

Tool version: **Tang Dynasty V6.2.168116** (built 2025-06-12), install root
`C:/Tools/Anlogic/TD_6.2.168116\`.

Primary sources:

| Source | What it gives |
|---|---|
| `list_devices` output (live tool) | db-name → family → package → valid speed grades |
| `<root>\arch\device_resource\device_resource.csv` | per-device LUT/DFF/DSP/PLL/ERAM/DRAM/URAM/serdes/PCIE/IO/hard-IP/voltage |
| `<root>\sim_release\<dir>\` | simulation library subdirectories actually present |
| SWUG105 Appendix 1 ("Device db 文件名") | partial db-name table (PH1/PH2 only) |

> **Table-extraction warning.** `list_devices` and `device_resource.csv` are machine-readable
> and were read verbatim, so the mapping and resource tables below are exact, not reconstructed.
> SWUG105's Appendix 1 table extracted poorly from the PDF (it groups packages under a shared
> db name across page breaks) and covers only PH1/PH2 — it is used below **only as a
> cross-check**, and the live `list_devices` output wins wherever they differ.

---

## 1. db-name → family → package → valid speed grade

This is the single most important lookup for driving the tool.

* **family** → the `-family` argument of `create_project`.
* **device (db-name)** → the `db_name` argument of `import_device` (add the `.db` suffix:
  e.g. `ph1_60.db` → `import_device ph1_60.db -package PH1A60GEG324 -speed 3`).
  It is reported by `list_devices` under the `Device` column.
* **package** → the `-package` argument of `import_device` and the `-device` argument of
  `create_project`.
* **speed** → the `-speed` argument. `2/3` means both `2` and `3` are legal; `A` is a literal
  speed-grade token; `NA` means the tool exposes no selectable speed grade (omit `-speed`).

| family | db-name (`-device` of import_device = `<db>.db`) | package | valid speed |
|---|---|---|---|
| `dr1` | `dr1_90` | `DR1M90GEG400` | 2/3 |
| `dr1` | `dr1_90` | `DR1M90GEG484` | 2/3 |
| `dr1` | `dr1_90` | `DR1M90GEG484A` | 3 |
| `dr1` | `dr1_90` | `DR1M90MEG484` | 2/3 |
| `dr1` | `dr1_90` | `DR1V90GEG400` | 2/3 |
| `dr1` | `dr1_90` | `DR1V90GEG484` | 2/3 |
| `dr1` | `dr1_90` | `DR1V90MEG484` | 2/3 |
| `ef2` | `ef2_1` | `EF2L15BG256B` | NA |
| `ef2` | `ef2_1` | `EF2L15LG100B` | NA |
| `ef2` | `ef2_1` | `EF2L15LG144B` | NA |
| `ef2` | `ef2_2` | `EF2L25BG256B` | NA |
| `ef2` | `ef2_2` | `EF2L25XG42B` | NA |
| `ef2` | `ef2_4` | `EF2L45BG256B` | NA |
| `ef2` | `ef2_4` | `EF2L45LG144B` | NA |
| `ef2` | `ef2_4` | `EF2L45UG132B` | NA |
| `ef2` | `ef2_4` | `EF2M45LG100B` | NA |
| `ef2` | `ef2_4` | `EF2M45LG144B` | NA |
| `ef2` | `ef2_4` | `EF2M45LG48B` | NA |
| `ef2` | `ef2_s4` | `EF2M45VG81C` | NA |
| `ef2` | `ef2_s4` | `EF2S45VG81C` | NA |
| `ef3` | `ef3_1` | `EF3L15CG256B` | NA |
| `ef3` | `ef3_10` | `EF3LA0CG484B` | NA |
| `ef3` | `ef3_10` | `EF3LA0CG642B` | NA |
| `ef3` | `ef3_4` | `EF3L40CG324B` | NA |
| `ef3` | `ef3_4` | `EF3L40CG332B` | NA |
| `ef3` | `ef3_45` | `EF3L45CG256B` | NA |
| `ef3` | `ef3_45` | `EF3L45CG256BH` | NA |
| `ef3` | `ef3_5` | `EF3L50CG256B` | NA |
| `ef3` | `ef3_7` | `EF3L70CG256B` | NA |
| `ef3` | `ef3_9` | `EF3L90CG324B` | NA |
| `ef3` | `ef3_9` | `EF3L90CG400B` | NA |
| `ef4` | `ef4_9` | `EF4L90CG324A` | NA |
| `eg4` | `eagle_15` | `EG4A15BG256` | NA |
| `eg4` | `eagle_15` | `EG4X15BG256` | NA |
| `eg4` | `eagle_20` | `EG4A20BG256` | NA |
| `eg4` | `eagle_20` | `EG4A20NG88` | NA |
| `eg4` | `eagle_20` | `EG4X20BG256` | NA |
| `eg4` | `eagle_20` | `EG4X20LG144` | NA |
| `eg4` | `eagle_s20` | `EG4D20EG176` | NA |
| `eg4` | `eagle_s20` | `EG4S20BG256` | NA |
| `eg4` | `eagle_s20` | `EG4S20CG324` | NA |
| `eg4` | `eagle_s20` | `EG4S20NG88` | NA |
| `ph1` | `ph1_100` | `PH1A100GCG324` | 2/3 |
| `ph1` | `ph1_100` | `PH1A100GSG324` | 2/3 |
| `ph1` | `ph1_100` | `PH1A100SFG676` | 2/3 |
| `ph1` | `ph1_100` | `PH1A100SFG676X` | 2/3 |
| `ph1` | `ph1_100p` | `PH1P100GEG324` | 3 |
| `ph1` | `ph1_100p` | `PH1P100SBG484` | 3 |
| `ph1` | `ph1_100p` | `PH1P100SBG676` | 3 |
| `ph1` | `ph1_100p` | `PH1P100SBG677` | 3 |
| `ph1` | `ph1_180` | `PH1A180SFG676` | 2/3 |
| `ph1` | `ph1_35p` | `PH1P35MBG484` | 3 |
| `ph1` | `ph1_35p` | `PH1P35MDG324` | 3 |
| `ph1` | `ph1_35p` | `PH1P35MEG324` | 3 |
| `ph1` | `ph1_35p` | `PH1P35MEG324A` | A |
| `ph1` | `ph1_35p` | `PH1P35MHG324` | 3 |
| `ph1` | `ph1_400` | `PH1A400SFG676` | 2/3 |
| `ph1` | `ph1_400` | `PH1A400SFG900` | 2/3 |
| `ph1` | `ph1_400` | `PH1A400SFX900` | 2/3 |
| `ph1` | `ph1_50p` | `PH1P50GEG324` | 3 |
| `ph1` | `ph1_50p` | `PH1P50MEG324A` | A |
| `ph1` | `ph1_50p` | `PH1P50SBG484` | 3 |
| `ph1` | `ph1_60` | `PH1A60GEG324` | 3 |
| `ph1` | `ph1_60c` | `PH1A60GEG324C` | 3 |
| `ph1` | `ph1_90` | `PH1A90SBG484` | 2/3 |
| `ph1` | `ph1_90` | `PH1A90SEG324` | 2/3 |
| `ph1` | `ph1_90` | `PH1A90SEG325` | 2/3 |
| `ph2` | `ph2_106` | `PH2A106FLG676` | 2/3/1 |
| `ph2` | `ph2_106` | `PH2A106FLG900` | 2/3/1 |
| `sf1` | `sf1_6` | `SF1N60VG81C` | NA |
| `sf1` | `sf1_6` | `SF1S60CG121I` | NA |
| `sf1` | `sf1_6` | `SF1S60VG81C` | NA |
| `sf1` | `sf1_6` | `SF1S60VG81E` | NA |
| `sf2` | `sf2_1` | `SF2S50VG90C` | NA |

**Totals:** 10 families (`dr1`, `ef2`, `ef3`, `ef4`, `eg4`, `ph1`, `ph2`, `sf1`, `sf2` — note
the family name for the EG4/Eagle parts is `eg4`), 25 db-names, 75 package variants.

### 1.1 Speed-grade notes

* `-speed` accepts the **integer** grades listed above (`1`, `2`, `3`). Passing a grade the
  package does not offer fails hard:
  `USR-8316 ERROR: Import device error, invalid speed grade setting "speed -N".`
  Verified live: `import_device ph1_60.db -package PH1A60GEG324 -speed 1` → error;
  `-speed 3` → `ARC-1001 : Device Initialization.` OK.
* `PH1P35MEG324A` and `PH1P50MEG324A` take the literal grade **`A`** (not `2`/`3`).
* `ph2_106` accepts `1`, `2`, `3` — the only family with grade `1`.
* Do **not** infer "if `2/3`, then `-speed 1` also works" — it does not.

### 1.2 Cross-check against SWUG105 Appendix 1

SWUG105 p.89-90 lists these db filenames (PH1/PH2 rows only, and compacted — e.g. it lists
`PH1A400SFG900/PH1A400SFG676/PH1A400SFX900` as sharing `ph1_400.db`):

| SWUG105 db name | SWUG105 packages (all share the db) |
|---|---|
| `ph1_100.db` | `PH1A100SFG676`, `PH1A100SFG676X`, `PH1A100GCG324`, `PH1A100GSG324` |
| `ph1_60.db` | `PH1A60GEG324` |
| `ph1_60c.db` | `PH1A60GEG324C` |
| `ph1_90.db` | `PH1A90SBG484`, `PH1A90SEG324`, `PH1A90SEG325` |
| `ph1_180.db` | `PH1A180SFG676` |
| `ph1_400.db` | `PH1A400SFG900`, `PH1A400SFG676`, `PH1A400SFX900` |
| `ph2_106.db` | `PH2A106FLG676`, `PH2A106FLG900` |

This agrees with `list_devices`. SWUG105 does **not** document the `dr1`, `ef2`, `ef3`, `ef4`,
`eg4`, `sf1`, `sf2` db names, nor the PH1P db names (`ph1_100p`, `ph1_35p`, `ph1_50p`). Use the
table in §1 for those.

---

## 2. Per-device resource table

Source: `<root>\arch\device_resource\device_resource.csv` (read verbatim).
Column units: LUTs, DFFs, DSPs, PLLs, IOs = counts; ERAMs/DRAMs/URAMs = **Kbits**;
`Serdes Lanes` = lane count (`-` = none); `PCIE` = hard PCIe core count.

`SIP` = system-in-package hard cores present in the package; `-` = none.
`MIN/REF/MAX VOLTAGE (V)` = package core-voltage window; `-` = not specified in the CSV.

### 2.1 dr1 (DR1M90 / DR1V90 — MCU+FPGA)

| Device | IOs | LUTs | DFFs | DSPs | PLLs | ERAM (Kb) | DRAM (Kb) | Serdes | PCIE | Hard cores / SIP | Vmin | Vref | Vmax |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DR1M90GEG400 | 126 | 52480 | 104960 | 240 | 8 | 5600 | 1340 | - | 0 | ADC*1, TS*1 | 0.93 | 0.95 | 0.98 |
| DR1M90GEG484 | 201 | 52480 | 104960 | 240 | 8 | 5600 | 1340 | - | 0 | ADC*1, TS*1 | 0.93 | 0.95 | 0.98 |
| DR1M90GEG484A | 201 | 52480 | 104960 | 240 | 8 | 5600 | 1340 | - | 0 | ADC*1, TS*1 | 0.93 | 0.95 | 0.98 |
| DR1M90MEG484 | 175 | 52480 | 104960 | 240 | 8 | 5600 | 1340 | - | 0 | ADC*1, TS*1, MIPI_DPHY RX Only *2 | 0.93 | 0.95 | 0.98 |
| DR1V90GEG400 | 126 | 52480 | 104960 | 240 | 8 | 5600 | 1340 | - | 0 | ADC*1, TS*1 | 0.93 | 0.95 | 0.98 |
| DR1V90GEG484 | 201 | 52480 | 104960 | 240 | 8 | 5600 | 1340 | - | 0 | ADC*1, TS*1 | 0.93 | 0.95 | 0.98 |
| DR1V90MEG484 | 175 | 52480 | 104960 | 240 | 8 | 5600 | 1340 | - | 0 | ADC*1, TS*1, MIPI_DPHY RX Only *2 | 0.93 | 0.95 | 0.98 |

### 2.2 ef2 (EF2L / EF2M / EF2S)

| Device | IOs | LUTs | DFFs | DSPs | PLLs | ERAM (Kb) | DRAM (Kb) | Serdes | PCIE | Hard cores / SIP | Vmin | Vref | Vmax |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EF2L15BG256B | 202 | 1520 | 1520 | 8 | 1 | 534 | 12 | - | 0 | ADC*1, AST*2 / 4Mb Flash*1 | - | - | - |
| EF2L15LG100B | 76 | 1520 | 1520 | 8 | 1 | 534 | 12 | - | 0 | ADC*1, AST*2 / 4Mb Flash*1 | - | - | - |
| EF2L15LG144B | 109 | 1520 | 1520 | 8 | 1 | 534 | 12 | - | 0 | ADC*1, AST*1 / 4Mb Flash*1 | - | - | - |
| EF2L25BG256B | 202 | 2520 | 2520 | 12 | 1 | 593 | 20 | - | 0 | ADC*1, AST*2 / 4Mb Flash*1 | - | - | - |
| EF2L25XG42B | 25 | 2520 | 2520 | 12 | 1 | 593 | 20 | - | 0 | ADC*1 / 4Mb Flash*1 | - | - | - |
| EF2L45BG256B | 202 | 4480 | 4480 | 15 | 1 | 684 | 35 | - | 0 | ADC*1, AST*2 / 4Mb Flash*1 | - | - | - |
| EF2L45LG144B | 109 | 4480 | 4480 | 15 | 1 | 684 | 35 | - | 0 | ADC*1, AST*2 / 4Mb Flash*1 | - | - | - |
| EF2L45UG132B | 100 | 4480 | 4480 | 15 | 1 | 684 | 35 | - | 0 | AST*2 / 4Mb Flash*1 | - | - | - |
| EF2M45LG100B | 76 | 4480 | 4480 | 15 | 1 | 684 | 35 | - | 0 | - | - | - | - |
| EF2M45LG144B | 109 | 4480 | 4480 | 15 | 1 | 684 | 35 | - | 0 | - | - | - | - |
| EF2M45LG48B | 31 | 4480 | 4480 | 15 | 1 | 684 | 35 | - | 0 | ADC*1, AST*2, M3*1 / 4Mb Flash*1 | - | - | - |
| EF2M45VG81C | 53 | 4480 | 4480 | 15 | 1 | 684 | 35 | - | 0 | - | - | - | - |
| EF2S45VG81C | 53 | 4480 | 4480 | 15 | 1 | 684 | 35 | - | 0 | ADC*1 / 4Mb Flash*1, 32Mb PSRAM*2 | - | - | - |

### 2.3 ef3 (EF3L / EF3LA0)

| Device | IOs | LUTs | DFFs | DSPs | PLLs | ERAM (Kb) | DRAM (Kb) | Serdes | PCIE | Hard cores / SIP | Vmin | Vref | Vmax |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EF3L15CG256B | 202 | 1520 | 1520 | 8 | 1 | 108 | 12 | - | 0 | - / 4Mb Flash*1 | - | - | - |
| EF3LA0CG484B | 379 | 11776 | 11776 | 0 | 2 | 612 | 92 | - | 0 | - / 8Mb Flash*1 | - | - | - |
| EF3LA0CG642B | 471 | 11776 | 11776 | 0 | 2 | 612 | 92 | - | 0 | - / 8Mb Flash*1 | - | - | - |
| EF3L40CG324B | 275 | 4800 | 4800 | 8 | 2 | 135 | 38 | - | 0 | - / 8Mb Flash*1 | - | - | - |
| EF3L40CG332B | 275 | 4800 | 4800 | 8 | 2 | 135 | 38 | - | 0 | - / 8Mb Flash*1 | - | - | - |
| EF3L45CG256B | 202 | 4480 | 4480 | 15 | 1 | 108 | 35 | - | 0 | - / 4Mb Flash*1 | - | - | - |
| EF3L45CG256BH | 202 | 4480 | 4480 | 15 | 1 | 108 | 35 | - | 0 | - | - | - | - |
| EF3L50CG256B | 202 | 5304 | 5304 | 0 | 2 | 279 | 42 | - | 0 | - | 1.14 | 1.2 | 1.26 |
| EF3L70CG256B | 202 | 7952 | 7952 | 0 | 2 | 324 | 63 | - | 0 | - | 1.14 | 1.2 | 1.26 |
| EF3L90CG324B | 275 | 9280 | 9280 | 16 | 2 | 270 | 73 | - | 0 | - / 8Mb Flash*1 | - | - | - |
| EF3L90CG400B | 331 | 9280 | 9280 | 16 | 2 | 270 | 73 | - | 0 | - / 8Mb Flash*1 | - | - | - |

### 2.4 ef4 / eg4

| Device | IOs | LUTs | DFFs | DSPs | PLLs | ERAM (Kb) | DRAM (Kb) | Serdes | PCIE | Hard cores / SIP | Vmin | Vref | Vmax |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EF4L90CG324A | 275 | 9280 | 9280 | 16 | 2 | 270 | 73 | - | 0 | - / 8Mb Flash*1 | - | - | - |
| EG4A15BG256 | 191 | 14720 | 14720 | 24 | 4 | 724 | 115 | - | 0 | ADC*1 | 1.14 | 1.2 | 1.26 |
| EG4X15BG256 | 188 | 14720 | 14720 | 24 | 4 | 724 | 115 | - | 0 | ADC*1 | 1.14 | 1.2 | 1.26 |
| EG4A20BG256 | 191 | 19600 | 19600 | 29 | 4 | 1088 | 154 | - | 0 | ADC*1 | 1.14 | 1.2 | 1.26 |
| EG4A20NG88 | 66 | 19600 | 19600 | 29 | 4 | 1088 | 154 | - | 0 | - | - | - | - |
| EG4X20BG256 | 188 | 19600 | 19600 | 29 | 4 | 1088 | 154 | - | 0 | ADC*1 | 1.14 | 1.2 | 1.26 |
| EG4X20LG144 | 102 | 19600 | 19600 | 29 | 4 | 1088 | 154 | - | 0 | - | - | - | - |
| EG4D20EG176 | 130 | 19600 | 19600 | 29 | 4 | 1088 | 154 | - | 0 | ADC*1 / 128Mb DDR1 SDRAM*1 | 1.14 | 1.2 | 1.26 |
| EG4S20BG256 | 188 | 19600 | 19600 | 29 | 4 | 1088 | 154 | - | 0 | ADC*1 / 64Mb SDR SDRAM | 1.14 | 1.2 | 1.26 |
| EG4S20CG324 | 210 | 19600 | 19600 | 29 | 4 | 1088 | 154 | - | 0 | ADC*1 / 64Mb SDR SDRAM | 1.14 | 1.2 | 1.26 |
| EG4S20NG88 | 66 | 19600 | 19600 | 29 | 4 | 1088 | 154 | - | 0 | ADC*1 / 64Mb SDR SDRAM | 1.14 | 1.2 | 1.26 |

### 2.5 ph1 (PH1A / PH1P — the largest set)

| Device | IOs | LUTs | DFFs | DSPs | PLLs | ERAM (Kb) | DRAM (Kb) | Serdes | PCIE | Hard cores / SIP | Vmin | Vref | Vmax |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| PH1A60GEG324 | 211 | 39360 | 78720 | 120 | 12 | 3160 | 780 | - | 0 | PVT*1 | 0.93 | 0.95 | 0.98 |
| PH1A60GEG324C | 211 | 39360 | 78720 | 120 | 12 | 3160 | 780 | - | 0 | PVT*1 | 0.97 | 1.0 | 1.03 |
| PH1A90SBG484 | 260 | 64320 | 128640 | 240 | 12 | 5440 | 1680 | 4 | 1 | TS*1, HPIO Num*90, MIPI_DPHY RX Only *2 | 0.93 | 0.95 | 0.98 |
| PH1A90SEG324 | 148 | 64320 | 128640 | 240 | 12 | 5440 | 1680 | 8 | 1 | TS*1, HPIO Num*50 | 0.93 | 0.95 | 0.98 |
| PH1A90SEG325 | 160 | 64320 | 128640 | 240 | 12 | 5440 | 1680 | 4 | 1 | TS*1, HPIO Num*90, MIPI_DPHY RX Only *2 | 0.93 | 0.95 | 0.98 |
| PH1A100GCG324 | 214 | 71040 | 142080 | 212 | 12 | 5600 | 1700 | - | 1 | PVT*2 | 0.873 | 0.9 | 0.945 |
| PH1A100GSG324 | 214 | 71040 | 142080 | 212 | 12 | 5600 | 1700 | - | 1 | PVT*2 | 0.873 | 0.9 | 0.945 |
| PH1A100SFG676 | 316 | 71040 | 142080 | 212 | 12 | 5600 | 1700 | 8 | 1 | PVT*2 | 0.873 | 0.9 | 0.945 |
| PH1A100SFG676X | 316 | 71040 | 142080 | 212 | 12 | 5600 | 1700 | 8 | 1 | PVT*2 | 0.873 | 0.9 | 0.945 |
| PH1A180SFG676 | 376 | 116800 | 233600 | 600 | 16 | 12920 | 3300 | 8 | 1 | TS*1, HPIO Num*150, MIPI_DPHY RX Only *2 | 0.93 | 0.95 | 0.98 |
| PH1A400SFG676 | 401 | 231680 | 463360 | 840 | 20 | 18280 | 5500 | 8 | 1 | PVT*1, HPIO Num*150 | 0.93 | 0.95 | 0.98 |
| PH1A400SFG900 | 501 | 231680 | 463360 | 840 | 20 | 18280 | 5500 | 16 | 1 | PVT*1, HPIO Num*150 | 0.93 | 0.95 | 0.98 |
| PH1A400SFX900 | 501 | 231680 | 463360 | 840 | 20 | 18280 | 5500 | 16 | 1 | PVT*1, HPIO Num*150 | 0.93 | 0.95 | 0.98 |
| PH1P35MBG484 | 291 | 21216 | 42432 | 40 | 6 | 2160 | 507 | - | 0 | TS*1, MCU, MIPI DPHY*2 | 0.92 | 0.95 | 0.98 |
| PH1P35MDG324 | 160 | 21216 | 42432 | 40 | 6 | 2160 | 507 | - | 0 | TS*1, MCU, MIPI DPHY*2 / Mem 512Mb | 0.92 | 0.95 | 0.98 |
| PH1P35MEG324 | 197 | 21216 | 42432 | 40 | 6 | 2160 | 507 | - | 0 | TVS*1, MCU, MIPI*2 | 0.92 | 0.95 | 0.98 |
| PH1P35MEG324A | 197 | 21216 | 42432 | 40 | 6 | 2160 | 507 | - | 0 | TVS*1, MCU, MIPI*2 | 0.92 | 0.95 | 0.98 |
| PH1P35MHG324 | 160 | 21216 | 42432 | 40 | 6 | 2160 | 507 | - | 0 | TS*1, MCU, MIPI DPHY*2 / Mem 1Gb | 0.92 | 0.95 | 0.98 |
| PH1P50GEG324 | 211 | 34240 | 68480 | 120 | 10 | 3480 | 600 | - | 1 | TS*1, MCU | 0.92 | 0.95 | 0.98 |
| PH1P50MEG324A | 189 | 34240 | 68480 | 120 | 10 | 3480 | 600 | - | 1 | TS*1, MCU, MIPI DPHY*2 | 0.92 | 0.95 | 0.98 |
| PH1P50SBG484 | 251 | 34240 | 68480 | 120 | 10 | 3480 | 600 | 4 | 1 | TS*1, MCU, MIPI DPHY*2 | 0.92 | 0.95 | 0.98 |
| PH1P100GEG324 | 211 | 71680 | 143360 | 220 | 12 | 6000 | 1600 | - | 1 | - | 0.92 | 0.95 | 0.98 |
| PH1P100SBG484 | 286 | 71680 | 143360 | 220 | 12 | 6000 | 1600 | 4 | 1 | - | 0.92 | 0.95 | 0.98 |
| PH1P100SBG676 | 301 | 71680 | 143360 | 220 | 12 | 6000 | 1600 | 8 | 1 | - | 0.92 | 0.95 | 0.98 |
| PH1P100SBG677 | 301 | 71680 | 143360 | 220 | 12 | 6000 | 1600 | 8 | 1 | - | 0.92 | 0.95 | 0.98 |

### 2.6 ph2, sf1, sf2

| Device | IOs | LUTs | DFFs | DSPs | PLLs | ERAM (Kb) | DRAM (Kb) | URAM (Kb) | Serdes | PCIE | Hard cores / SIP | Vmin | Vref | Vmax |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| PH2A106FLG676 | 286 | 246720 | 493440 | 1800 | 5 | 24000 | 5370 | 17280 | 16 | 2 | TVS*3 | 0.825 | 0.85 | 0.875 |
| PH2A106FLG900 | 386 | 246720 | 493440 | 1800 | 5 | 24000 | 5370 | 17280 | 20 | 2 | TVS*3 | 0.825 | 0.85 | 0.875 |
| SF1N60VG81C | 27 | 5824 | 5824 | 10 | 2 | 234 | 46 | 0 | - | 0 | DSI*2, RISCv*1, PSRAM Controller*2 / 8Mb Flash*1, 32Mb PSRAM*2 | 1.14 | 1.2 | 1.26 |
| SF1S60CG121I | 55 | 5824 | 5824 | 10 | 2 | 234 | 46 | 0 | - | 0 | DSI*2, DSC Decoder*1, RISCv*1, PSRAM Controller*2 / 8Mb Flash*1, 32Mb PSRAM*2 | 1.14 | 1.2 | 1.26 |
| SF1S60VG81C | 27 | 5824 | 5824 | 10 | 2 | 234 | 46 | 0 | - | 0 | DSI*2, DSC Decoder*1, RISCv*1, PSRAM Controller*2 / 8Mb Flash*1, 32Mb PSRAM*2 | 1.14 | 1.2 | 1.26 |
| SF1S60VG81E | 27 | 5824 | 5824 | 10 | 2 | 234 | 46 | 0 | - | 0 | - | - | - | - |
| SF2S50VG90C | 31 | 3120 | 6240 | 8 | 1 | 320 | 98 | 0 | - | 0 | SCALER*1, DSC Decoder*1, DSC encoder*1, PSRAM Controller*2 / 4Mb Flash*1, 32Mb PSRAM*2 | 0.87 | 0.9 | 0.92 |

Notes on the `Hard cores` column: `ADC` = on-chip analog-to-digital converter block,
`TS`/`TVS`/`PVT` = temperature/voltage sensor block, `AST` = analog system block,
`M3` / `MCU` / `RISCv` = embedded processor, `HPIO Num*N` = N high-performance IOs,
`MIPI_DPHY` / `MIPI DPHY` / `MIPI` = MIPI D-PHY, `DSI` = display serial interface,
`DSC` = display stream compression, `PSRAM Controller` / `SCALER` = hard controller IP.
The `*N` suffix is the instance count in that package. This decoding is
`[RECONSTRUCTED]` from the abbreviations used across the IPUG/UG library guides; the raw CSV
only lists the tokens.

---

## 3. Simulation library subdirectories (`sim_release\`)

TD ships pre-compiled / pre-generated simulation models under
`<root>\sim_release\`. The directory name is the **family**, not the db-name:

```
<root>\sim_release\
    common\      <- shared, family-independent models (used by every family)
    dr1\
    ef2\
    ef3\
    ef4\
    eg4\         <- the EG4 / Eagle family (create_project -family eg4)
    ph1\         <- PH1A parts
    ph1p\        <- PH1P parts  (NOTE: a SEPARATE directory from ph1)
    ph2\         <- PH2A parts
    sf1\
    sf2\
```

**Which families need which `sim_release` subdirectory:**

| `create_project -family` | db-names | required `sim_release` subdirs |
|---|---|---|
| `dr1` | `dr1_90` | `common`, `dr1` |
| `ef2` | `ef2_1`, `ef2_2`, `ef2_4`, `ef2_s4` | `common`, `ef2` |
| `ef3` | `ef3_1`, `ef3_4`, `ef3_45`, `ef3_5`, `ef3_7`, `ef3_9`, `ef3_10` | `common`, `ef3` |
| `ef4` | `ef4_9` | `common`, `ef4` |
| `eg4` | `eagle_15`, `eagle_20`, `eagle_s20` | `common`, `eg4` |
| `ph1` (PH1A packages) | `ph1_60`, `ph1_60c`, `ph1_90`, `ph1_100`, `ph1_180`, `ph1_400` | `common`, `ph1` |
| `ph1` (PH1P packages) | `ph1_35p`, `ph1_50p`, `ph1_100p` | `common`, **`ph1p`** |
| `ph2` | `ph2_106` | `common`, `ph2` |
| `sf1` | `sf1_6` | `common`, `sf1` |
| `sf2` | `sf2_1` | `common`, `sf2` |

**Critical gotcha:** PH1A and PH1P share the `ph1` family for `create_project` /
`import_device`, but their simulation models live in **two different** directories
(`sim_release\ph1` vs `sim_release\ph1p`). Decide by package prefix:
`PH1A...` → `ph1`, `PH1P...` → `ph1p`.

**File-naming inside each subdir** (verified by directory listing):

| subdir | model file prefix | examples |
|---|---|---|
| `common` | `al_*` | `al_map_lut.v`, `al_map_seq.v`, `al_map_adder.v`, `al_map_mult.v`, `al_map_mux4.v`, `al_map_alu2b.v`, `al_map_basic.v`, `al_phy_glbl.v`, `al_logic_debughub.v` |
| `dr1` | `dr1_*` | `dr1_logic_slice.v`, `dr1_phy_pll.v`, `dr1_phy_gsr.v`, `dr1_phy_eram.v`, `dr1_logic_iobuf.v` |
| `ef2` | `ef2_*` | `ef2_logic_io.v`, `ef2_phy_pll.v`, `ef2_phy_bram.v`, `ef2_phy_adc.v`, `ef2_phy_osc.v` |
| `ef3` | `ef3_*` | same pattern plus `*_v2` variants (`ef3_phy_config_v2.v`, `ef3_phy_osc_v2.v`, `ef3_phy_csb_v2.v`) |
| `ef4` | `ef4_*` | `ef4_logic_io.v`, `ef4_phy_pll.v`, `ef4_phy_intflash.v` |
| `eg4` | `eg_*` (no `4`!) | `eg_logic_io.v`, `eg_phy_pll.v`, `eg_phy_bram.v`, `eg_phy_adc.v`, `eg_phy_ddr_8m_16.v`, `eg_phy_sdram_2m_32.v` |
| `ph1` | `ph1_*` | `ph1_phy_pll.v`, `ph1_phy_serdes_dual.v` (+ `_v2`, `_v3`), `ph1_phy_pcie.sv` (+ `_v2`, `_v3`), `ph1_logic_slice.v` |
| `ph1p` | `ph1p_*` | `ph1p_phy_pll.v` (+ `_v2`), `ph1p_phy_hxt_v1.sv` / `ph1p_phy_hxt_v2.sv`, `ph1p_phy_pcie_v1.sv`, `ph1p_logic_hdio.v` |
| `ph2` | `ph2_*` | `ph2_phy_pll.v`, `ph2_phy_ddrphy.v`, `ph2_phy_cgmac_v1.sv`, `ph2_phy_pcie_v1.sv`, `ph2_logic_bufg*.v` |
| `sf1` | `sf1_*` | `sf1_phy_pll.v`, `sf1_phy_dsi.v`, `sf1_phy_dsc.v`, `sf1_phy_psram.v`, `sf1_logic_mcu.v` |
| `sf2` | `sf2_*` | `sf2_phy_pll.v`, `sf2_phy_video_processor.sv`, `sf2_logic_hsio.v` |

> **Note.** The `eg4` subdir uses the `eg_` prefix while the db-name family is `eg4` — do not
> look for `eg4_logic_*.v`. Also note `common` holds the *mapping* primitives (`al_map_*`) that
> every family needs in addition to its own directory.

The Simulation Libraries Compiler workflow, the compiler's own library-name table
(`common`/`EF2`/`EF3`/`EG`/`PH1`/`PH2`/`SF1` — which omits `EF4`, `DR1`, `PH1P` and `SF2` even
though they exist on disk), and the ModelSim/QuestaSim selection procedure are documented in
`ip-and-libraries.md` Part C.

---

## 4. Driving the tool — exact command forms

```tcl
# --- Project mode -------------------------------------------------------
# family + package(= -device) + speed, taken from the tables above
create_project test ./ -family ph1 -device PH1A100SFG676 -speed 2
# (project_name may follow the directory: create_project test -family ph1 -device PH1A100SFG676 ./)
open_project ./test.al
top_module run_led
close_project

# --- Non-project / stepwise mode ---------------------------------------
# db_name = <Device column of list_devices> + ".db"
import_device ph1_100.db -package PH1A100SFG676 -speed 2

# --- Discovery / verification ------------------------------------------
list_devices                     # the Family|Device|Package|Speed table in §1
query_current_arch               # arch info for the currently imported device
query_current_package -fio           # functional IOs: idx, PE name, x/y/z, type, banks
query_current_package -clock_io      # clock-capable pads: sector, location, name, gclkioN, banks
query_current_package -lvds          # legal LVDS pairs: name <P,N> and location <P,N>
query_current_package -single_ended  # single-ended IO list: name, location
get_device_param <name>          # device parameters of the imported device
set_device_param <name> <value>
dump_device / load_device / export_device / set_device / set_device_info
list_packages
```

`query_current_package` **prints to the console and returns an empty string** — in TCL you
cannot capture it with `set x [query_current_package -fio]`. Redirect stdout or just let it
print into the log.

Sample real output shape (`-fio`) for `PH1A60GEG324`:

```
RUN-1001 : List of IO Banks: 0|11|12|13|32|33.
RUN-1001 : Package ph1a60geg324
RUN-1001 :   Idx  |  PE   |  Location   |    Type    |  IntBank  |  ExtBank
RUN-1001 :    1   |  a1   |  x55y103z3  |  fio (hd)  |    33     |    33
RUN-1001 :    2   |  a10  |   x0y17z0   |  fio (hd)  |    11     |    11
```

Sample real output shape (`-clock_io`): columns `Sector | Location | Name | Config | IntBank |
ExtBank`, with `Config` values `gclkio0`…`gclkio3`.

Sample real output shape (`-lvds`): `# | Type | IntBank | ExtBank | Name <[P],[N]> |
Location <[P],[N]>`, e.g. `1 | LVDS | 11 | 11 | <A10 , A9> | <X0Y17Z0 , X0Y17Z1>`.
Note the LVDS list is *ordered by P-pin name*, and non-bonded pairs appear with `-`.

Import-time console output also reports the configuration pin map, e.g.:

```
ARC-1001 :           OPTION          |          IO          |   SETTING
ARC-1001 :   non_jtag_persist(none)  |        36 IOs        |    gpio
ARC-1001 :            jtag           |  P8/E10/E12/E11/E13  |  dedicate
```

---

## 5. Gaps and uncertainties

* `device_resource.csv` covers all 75 packages and was read verbatim — the resource table is
  complete. It is **not** in the PDF set and is not reproduced by the PDFs.
* SWUG105 Appendix 1 covers only PH1/PH2 db names; the PH1P/DR1/EF/EG/SF db names in §1 come
  from the live `list_devices` output only.
* The `Hard Cores` / `SIP` token decoding in §2 is `[RECONSTRUCTED]` from IPUG/UG library
  guides; the CSV gives only the raw tokens (`ADC*1   TS*1` etc., sometimes space-padded).
* `MIN/REF/MAX VOLTAGE` is `-` for most EF/SF-family packages in the CSV; do not assume a
  voltage window where the CSV is empty.
* `print_device_resource` exists but fails without a loaded design context; its exact column
  layout was not captured. Prefer `device_resource.csv` (static, complete).
* The numeric device-type IDs in `<repo>/references/vendor/安路科技_TD_技术文档/config/config.json` (`"Device": {"0": ...}`) could not be
  mapped to families/packages from any available input. See `debug-and-programming.md` §
  "Operation modes" for what is known.
