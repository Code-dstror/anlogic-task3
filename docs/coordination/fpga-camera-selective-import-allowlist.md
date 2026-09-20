# FPGA camera selective-import allowlist (batch 2)

## 1. Purpose, fixed commits, and non-operation boundary

This document is the second file-level import gate.  It records a camera-only
candidate delivery from a fixed FPGA commit into `feature/linux-transport`; it
does not import a source blob, alter an FPGA project, or validate hardware.
It inherits the vendor-authorization, denylist, byte-preservation, and
future-integration constraints in
[`fpga-selective-import-allowlist.md`](./fpga-selective-import-allowlist.md);
it does not broaden any of them.

- Old FPGA source baseline: `457439ed79e4d21a213fcfbda4c493b01f88326b`
- New FPGA source commit: `6b398c144e7a563ea3d9fa6085ac3142813be2a7`
- Target branch inspected: `feature/linux-transport`
- Target commit inspected: `3442c65fce86a694c1ba9f767a91c9518f008e2a`

No merge, cherry-pick, checkout, or copy of FPGA content is authorized by
this document. A later, separately reviewed integration may select only the
direct blobs enumerated below, preserving their source bytes.

## 2. Source-diff derivation and fail-closed range gate

The list is derived, rather than guessed, with the following source-object
query:

```bash
git diff --name-status \
  457439ed79e4d21a213fcfbda4c493b01f88326b \
  6b398c144e7a563ea3d9fa6085ac3142813be2a7
```

That diff contains 90 paths: 89 `A` camera-source candidates in the six source
categories below, and one modified root `README.md`. The range gate requires
every source candidate to be `A`, requires the exact category counts, and
rejects every other status or path before an allowlist can be generated:

| Source-candidate category | Required and observed count |
| --- | ---: |
| `fpga_rtl/vendor/anlogic_camera/` | 11 |
| `fpga_rtl/camera/` | 53 |
| `fpga_rtl/tb/` | 16 |
| `fpga_rtl/constraints/` | 2 |
| `fpga_prj/` | 4 |
| `doc/` | 3 |
| **Source-candidate total** | **89** |

Of those 89 new source paths, 88 are direct blobs. The remaining source path,
`doc/imx415_camera_bringup.md`, is a manual adaptation because its source blob
names a `.codex`-dependent rebuild entry that is absent from the target and
this batch. The direct category gate is therefore:

| Direct category | Required and observed count |
| --- | ---: |
| `fpga_rtl/vendor/anlogic_camera/` | 11 |
| `fpga_rtl/camera/` | 53 |
| `fpga_rtl/tb/` | 16 |
| `fpga_rtl/constraints/` | 2 |
| `fpga_prj/` | 4 |
| `doc/` | 2 |
| **Direct total** | **88** |

The target-tree collision check queried all 89 source candidates with
`git cat-file -e HEAD:<path>` at target commit `3442c65`; it found **zero**
existing paths. A future direct import must recheck its 88 direct paths. Any
future run that observes a non-`A` source status, a count other than either
table above, an out-of-scope path, or an existing target path must stop rather
than produce or apply a changed allowlist.

## 3. Direct-import allowlist

Blob IDs and byte sizes are read from the new source commit's tree and blob
objects. This table contains exactly 88 direct blobs. `Yes — exact blob` is
the decision for each row: no content edits, normalization, or path
substitution are authorized during a future import.

| Source path | Blob ID | Bytes | Category | Import reason / dependency role | Direct blob import |
| --- | --- | ---: | --- | --- | --- |
| `doc/imx415_camera_design.md` | `59d14e4ed28773762d3efa16a47a4db03f73e832` | 3457 | camera documentation | Camera RTL and AXI-stream design contract | Yes — exact blob |
| `doc/imx415_camera_validation.md` | `ab381849bdbdd82ff9fd537a4a5f74a4a7705290` | 5574 | camera documentation | Simulation, TD, timing, and hardware-status evidence | Yes — exact blob |
| `fpga_prj/imx415_camera.al` | `e26313d9e34d9a88748f71dddf6521eb1b3541ab` | 14806 | TD project | Independent camera top, source set, and constraint entry | Yes — exact blob |
| `fpga_prj/scripts/build_imx415_camera_project.tcl` | `8749fa99b84c6afa060c380b45a9b7d5b798df26` | 2031 | TD Tcl | Synthesis through bitstream and final timing gate | Yes — exact blob |
| `fpga_prj/scripts/diagnose_imx415_camera.tcl` | `cfee0dfbafd1851bf4c9f12674823be8439ed616` | 848 | TD Tcl | Read/constraint/area diagnostic entry | Yes — exact blob |
| `fpga_prj/scripts/sync_imx415_camera_project.tcl` | `3d7947c7fcd50dee8a3f1e2d1e4017638c21553d` | 2664 | TD Tcl | Registers the camera source and constraint closure | Yes — exact blob |
| `fpga_rtl/camera/camera_raw_crop.v` | `e32551822390f96501e0e921191cabacffd0bf8b` | 4165 | camera RTL | RAW crop stage used by RGB pipeline and integration simulation | Yes — exact blob |
| `fpga_rtl/camera/camera_raw_crop_spec.md` | `cf29f44c09799c379355e045465889a08a421715` | 1534 | camera specification | Crop-stage contract accompanying its RTL | Yes — exact blob |
| `fpga_rtl/camera/camera_reference.py` | `08a17a7ca14022f2cf2ccdd952d8aa3f533807e7` | 882 | Python helper | Self-contained byte/crop reference helper | Yes — exact blob |
| `fpga_rtl/camera/camera_rgb_pipeline.v` | `da14dce58b28f20a0550349432c08e44ea9666d1` | 2914 | camera RTL | Connects crop, ISP, and RGB packer | Yes — exact blob |
| `fpga_rtl/camera/camera_uart_status.v` | `e0f12ec33d9594ecb541f8cd0586a1df0386b380` | 2073 | camera RTL | Board-example UART status observer | Yes — exact blob |
| `fpga_rtl/camera/camera_uart_status_spec.md` | `0b641551c8d7db6105f38b3e1b9a5340fc486676` | 880 | camera specification | UART status packet contract | Yes — exact blob |
| `fpga_rtl/camera/csi/csi2_async_event_fifo.v` | `1414a7700a6dba45574a07c4ca070d025894f9e8` | 1910 | camera RTL | Wraps existing Soft FIFO for receive events | Yes — exact blob |
| `fpga_rtl/camera/csi/csi2_ph1_phy_wrapper.v` | `d9764349b1484d3d7c9db7dcbe1f4fad1c58ef4c` | 6297 | camera RTL | Application wrapper over camera vendor PHY helpers | Yes — exact blob |
| `fpga_rtl/camera/csi/csi2_raw10_rx.v` | `0a3e143df4ad67569270ff717f35af7a9824970d` | 4595 | camera RTL | CSI receiver integration layer | Yes — exact blob |
| `fpga_rtl/camera/csi/csi2_raw10_rx_stream.v` | `3fd4fe8cd670d1c00780c123a8bc14679a24cb03` | 4341 | camera RTL | RX stream, word-core, and FIFO connection | Yes — exact blob |
| `fpga_rtl/camera/csi/csi2_raw10_word_core.v` | `76f6c077e462751524e814003ca508749c5d1342` | 5364 | camera RTL | RAW10 packet/ECC/CRC word processing | Yes — exact blob |
| `fpga_rtl/camera/csi/csi2_rx_contract.md` | `e7546488ede3b2acc2a80fba912388d67f02d5d5` | 2178 | camera specification | CSI receiver behavior and fault contract | Yes — exact blob |
| `fpga_rtl/camera/imx415_camera_axis.v` | `6017315fa2435fc1e83dacc801a97ee1e49821ca` | 5540 | camera RTL | Reusable IMX415-to-RGB AXI-stream boundary | Yes — exact blob |
| `fpga_rtl/camera/imx415_camera_board_top.v` | `84288c508ffe54c87d06f386d3d577af8e07f511` | 2966 | camera RTL | TD project top and board example | Yes — exact blob |
| `fpga_rtl/camera/isp/README.md` | `b7dc331138d3c034bfbf4c952db88433da16acd1` | 1073 | ISP documentation | ISP-local entry pointing to validation evidence | Yes — exact blob |
| `fpga_rtl/camera/isp/color/color_pipeline_axis.v` | `87a2086763c4fc583fd30f43ce19e524db6beabc` | 230136 | ISP RTL | Color conversion pipeline used by ISP top | Yes — exact blob |
| `fpga_rtl/camera/isp/color/color_pipeline_axis_spec.md` | `40f7ceb1635b8d6b119271a773010e82d86d056b` | 763 | ISP specification | Color pipeline interface contract | Yes — exact blob |
| `fpga_rtl/camera/isp/color/gamma22_10to8.dath` | `b0a25dbde891933b8f07cda7236e07381fa83755` | 3072 | initialization data | Gamma ERAM initialization table | Yes — exact blob |
| `fpga_rtl/camera/isp/color/gamma_lut_10to8.v` | `0b38dd2aac40a758720155d3ff9064d54717bfa2` | 1897 | ISP RTL | Gamma lookup and ERAM initialization consumer | Yes — exact blob |
| `fpga_rtl/camera/isp/color/gamma_lut_10to8_spec.md` | `c5d78be8526203699ef977676962854c4a3d8dd1` | 711 | ISP specification | Gamma table and latency contract | Yes — exact blob |
| `fpga_rtl/camera/isp/color/generate_gamma_table.ps1` | `ec1a462607067f44da5a170cfdcc2a840b445826` | 362 | generation helper | Recreates the tracked Gamma initialization table | Yes — exact blob |
| `fpga_rtl/camera/isp/isp_core_top.v` | `cfb4f889ca72f9db3d015d92f2c8e86bb1a2dc3d` | 10057 | ISP RTL | Raw ISP to color-pipeline composition | Yes — exact blob |
| `fpga_rtl/camera/isp/isp_core_top_spec.md` | `d7f0b021b97dee3d14e13da84f3a1922a4921d84` | 1354 | ISP specification | ISP top stream and stage contract | Yes — exact blob |
| `fpga_rtl/camera/isp/isp_line_ram_40x1024.v` | `394dbd975a3d9018272e73952318d840d15189c4` | 1860 | ISP RTL | PH1 ERAM line-store wrapper | Yes — exact blob |
| `fpga_rtl/camera/isp/isp_line_ram_40x1024_spec.md` | `fe689542db29c71e810560d34aef092c849b5e35` | 814 | ISP specification | Line-store geometry and access contract | Yes — exact blob |
| `fpga_rtl/camera/isp/raw/raw_blc.v` | `04bf28d42c81834ba6f6104d9afc6edfa0e20e1c` | 7156 | ISP RTL | RAW black-level stage | Yes — exact blob |
| `fpga_rtl/camera/isp/raw/raw_blc_spec.md` | `ea9d000f4b53597215c17902b6fda99cb51ca9ec` | 710 | ISP specification | Black-level stage contract | Yes — exact blob |
| `fpga_rtl/camera/isp/raw/raw_demosaic.v` | `718e9cf188e03f30dc6f6541251054af56ee4cc3` | 20313 | ISP RTL | RAW Bayer demosaic stage | Yes — exact blob |
| `fpga_rtl/camera/isp/raw/raw_demosaic_spec.md` | `1031b0cc4b67413eb5506f5f83aeb13fce8599e0` | 720 | ISP specification | Demosaic stage contract | Yes — exact blob |
| `fpga_rtl/camera/isp/raw/raw_isp_top.v` | `aba79733562e4816898fef51a43a38eaf96e90a9` | 7516 | ISP RTL | Raw-stage composition | Yes — exact blob |
| `fpga_rtl/camera/isp/raw/raw_isp_top_spec.md` | `4ad7c70c2c478dc97898528201ea75cef23b071c` | 692 | ISP specification | Raw ISP top contract | Yes — exact blob |
| `fpga_rtl/camera/isp/raw/raw_row_window.v` | `d73b4a9cdffeda11447a2349e2c6d47841344209` | 21734 | ISP RTL | RAW line-window generation | Yes — exact blob |
| `fpga_rtl/camera/isp/raw/raw_row_window_spec.md` | `4625eedd98107fe1518cfae8f1417fddec1f9704` | 1091 | ISP specification | Window-stage contract | Yes — exact blob |
| `fpga_rtl/camera/isp/run_camera_isp_modelsim.ps1` | `ebb6eb14b6da14f93cabfa67dadc2aae171fa6f5` | 2619 | ModelSim runner | ISP core/Gamma/full-frame runner | Yes — exact blob |
| `fpga_rtl/camera/isp/tb/tb_camera_isp_4k.v` | `dabc4c6178b191ed7767f19b441648ece08c8d42` | 8385 | ISP testbench | Full-frame ISP check at 1080p or 4K | Yes — exact blob |
| `fpga_rtl/camera/isp/tb/tb_camera_isp_core.v` | `f90e2c593c6e254316f0c0db46f5204114fd25b3` | 17680 | ISP testbench | ISP invariants testbench | Yes — exact blob |
| `fpga_rtl/camera/isp/tb/tb_camera_isp_gamma.v` | `9d32122ee28763d97e5fd107cd195c04c4b7b2b4` | 1026 | ISP testbench | Gamma lookup testbench | Yes — exact blob |
| `fpga_rtl/camera/isp/waveforms/color_pipeline_axis_transfer.json` | `3b56666feb7bf858d86cee1f514b6f91fefdce5e` | 272 | waveform reference | Color transfer expected waveform | Yes — exact blob |
| `fpga_rtl/camera/isp/waveforms/gamma_lut_lookup.json` | `11bcd194a29bad35d19b17984ada030502f8bb58` | 200 | waveform reference | Gamma lookup expected waveform | Yes — exact blob |
| `fpga_rtl/camera/isp/waveforms/isp_core_top_stream.json` | `ad272a3703a4257b7c339c682e462ddc85fa7f51` | 303 | waveform reference | ISP top expected waveform | Yes — exact blob |
| `fpga_rtl/camera/isp/waveforms/isp_line_ram_read.json` | `2a419a09b923e506dfb9291d6d60e293a6247b83` | 315 | waveform reference | Line-store expected waveform | Yes — exact blob |
| `fpga_rtl/camera/isp/waveforms/raw_blc_transfer.json` | `136b882f7dd80665bd45637876dc4624296e4060` | 238 | waveform reference | Black-level expected waveform | Yes — exact blob |
| `fpga_rtl/camera/isp/waveforms/raw_demosaic_window.json` | `4f60e11af7d7784dff7c2325c729adbda00c1473` | 235 | waveform reference | Demosaic expected waveform | Yes — exact blob |
| `fpga_rtl/camera/isp/waveforms/raw_isp_top_frame.json` | `6fd36082bd86432a2183785e880d8c23374c1bc0` | 249 | waveform reference | Raw ISP expected frame | Yes — exact blob |
| `fpga_rtl/camera/isp/waveforms/raw_row_window_line.json` | `1132def4db9980bdc309e5f33f54a4530fa0ddff` | 256 | waveform reference | RAW window expected line | Yes — exact blob |
| `fpga_rtl/camera/rgb_axis_packer.v` | `274dfc8c1187a3ef2e3752e3170528793e3c1d38` | 5386 | camera RTL | RGB-byte to 128-bit AXI-stream packing | Yes — exact blob |
| `fpga_rtl/camera/rgb_axis_packer_spec.md` | `bd9aaeaf886a1e3b9e4a54633637eb961e05f29b` | 3200 | camera specification | RGB packing and TLAST contract | Yes — exact blob |
| `fpga_rtl/camera/sensor/camera_i2c_write.v` | `c109d98d3168e62eae4e316a92dcf974ceec4351` | 3520 | sensor RTL | IMX415 I2C byte-write engine | Yes — exact blob |
| `fpga_rtl/camera/sensor/camera_i2c_write_spec.md` | `2e8f4e7418fd19743de59dfa661a76bcaaacf1b1` | 876 | sensor specification | I2C write transaction contract | Yes — exact blob |
| `fpga_rtl/camera/sensor/imx415_config.v` | `7eb8e9f2906c0d49b39aa8c60e47ac2c6b68c179` | 2667 | sensor RTL | IMX415 configuration controller | Yes — exact blob |
| `fpga_rtl/camera/sensor/imx415_config_spec.md` | `14d8fbd014e154e0d9c94219ea6024a9448bdff7` | 939 | sensor specification | Configuration state-machine contract | Yes — exact blob |
| `fpga_rtl/camera/sensor/imx415_mode_table.v` | `33b8f36ce6bd18e540b511ba4605d3d8f161fc05` | 1655 | sensor RTL | IMX415 mode/profile table | Yes — exact blob |
| `fpga_rtl/camera/sensor/imx415_mode_table_spec.md` | `bf047fc7d1227c0fccc9117e258011c39e764c22` | 755 | sensor specification | Mode-table profile contract | Yes — exact blob |
| `fpga_rtl/constraints/imx415_camera_board_top.adc` | `2907cdb6fb676e066f595f2579663e8909f4301d` | 1483 | TD constraints | Camera board pin and clock constraints | Yes — exact blob |
| `fpga_rtl/constraints/imx415_camera_board_top.sdc` | `86dedc85fe8afc156896e5854df84675f8227ade` | 1157 | TD constraints | Camera board timing constraints | Yes — exact blob |
| `fpga_rtl/tb/run_camera_csi_rgb_modelsim.ps1` | `a09bacb583d2686ef924ec2d68f38066e31d7562` | 3470 | ModelSim runner | CSI FIFO through RGB integration runner | Yes — exact blob |
| `fpga_rtl/tb/run_camera_pipeline_modelsim.ps1` | `a7597c9a29e26d39c3461b02aa71f0c121b8f1f8` | 5104 | ModelSim runner | End-to-end camera pipeline runner | Yes — exact blob |
| `fpga_rtl/tb/run_camera_sensor_modelsim.ps1` | `71ff02c401408cb3c7d21ba4fcf0b745d983c5b4` | 1819 | ModelSim runner | Sensor-control runner | Yes — exact blob |
| `fpga_rtl/tb/run_camera_uart_modelsim.ps1` | `669470e8c2e1ef90e577c5cee6c5a5877eccb13f` | 1511 | ModelSim runner | UART-status runner | Yes — exact blob |
| `fpga_rtl/tb/run_camera_watchdog_modelsim.ps1` | `788dfbd8678b1112ffba66a9efd26c2f81c0b020` | 1888 | ModelSim runner | Silent-source watchdog runner | Yes — exact blob |
| `fpga_rtl/tb/run_csi2_fifo_modelsim.ps1` | `f0fb6f30e3f75abc523fc2cd985ae56c55603284` | 2125 | ModelSim runner | CSI event-FIFO runner | Yes — exact blob |
| `fpga_rtl/tb/run_csi2_receiver_modelsim.ps1` | `d22a2f4342d098784185ee637b2114a34e3767ea` | 1125 | ModelSim runner | RAW10 word-core runner | Yes — exact blob |
| `fpga_rtl/tb/run_rgb_axis_packer_modelsim.ps1` | `53c3aec4b7ee425eca7836edcfdff2aa9d6c3ab3` | 1588 | ModelSim runner | RGB AXI packer runner | Yes — exact blob |
| `fpga_rtl/tb/tb_camera_csi_rgb.v` | `4d5579419165546dba1c5622f6a1cebe8254a9d2` | 13066 | testbench | CSI-to-RGB integration checks | Yes — exact blob |
| `fpga_rtl/tb/tb_camera_rgb_pipeline.v` | `79950534183a3fee84817825ad950e4cd008e7ed` | 11287 | testbench | End-to-end RGB pipeline checks | Yes — exact blob |
| `fpga_rtl/tb/tb_camera_sensor.v` | `16ca33d7a7e66ddccff52e3893b1d3ddcef283ae` | 12293 | testbench | IMX415 sensor/I2C checks | Yes — exact blob |
| `fpga_rtl/tb/tb_camera_uart_status.v` | `c086f43e5464a2b2136f7d33c0aac4dd7b78fe56` | 5358 | testbench | UART packet checks | Yes — exact blob |
| `fpga_rtl/tb/tb_camera_watchdog.v` | `82b9c9b11a2df18b834f19a9d7ed2f93c22222d2` | 7912 | testbench | Silent-source watchdog checks | Yes — exact blob |
| `fpga_rtl/tb/tb_csi2_raw10_word_core.v` | `cd0f105564cfc4ba3cc958e26aa4dc1ccf44c181` | 9773 | testbench | RAW10 packet decoder checks | Yes — exact blob |
| `fpga_rtl/tb/tb_csi2_receiver_fifo.v` | `ded1e1a447acd80ae430186319268fa81fa20103` | 9287 | testbench | CSI async FIFO overflow/recovery checks | Yes — exact blob |
| `fpga_rtl/tb/tb_rgb_axis_packer.v` | `ab350d3c5da94b1d1cc257ce7cd571d5f9e60ca8` | 11797 | testbench | RGB packer byte/mask checks | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/SOURCE_ORIGIN.md` | `07b4176b635171a17c367ca06ff710d713f53bd6` | 1256 | vendor provenance | Source and unchanged-vendor record | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/clocks/ui_pll.v` | `ff49393d73b393b640f4a017e8f815c589bf264f` | 3617 | vendor clock RTL | Camera clock generator used by board top | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/phy/auto_delay_ctl.v` | `0236575f588ba1cc1e59ea7c96824f5a875b37dd` | 6156 | vendor PHY RTL | PHY automatic delay helper | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_byte_align.v` | `481ed8c79b54b10e9c735659dc8ffdb6d6c9ad0b` | 5375 | vendor PHY RTL | PHY byte alignment helper | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_clock_det.v` | `655c4d6ef0fedb1df5cf3a8e142b460361e1f331` | 3490 | vendor PHY RTL | PHY recovered-clock detector | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_hs_data_phy.v` | `f17ee3e38594ad3b271449f0d0e648e4c8fb8b8c` | 2735 | vendor PHY RTL | PHY high-speed data lane helper | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_phy.v` | `1f38991ad13f6adb8f1c6a89e9e7ae8b5aad3a00` | 6409 | vendor PHY RTL | Retained vendor PHY top snapshot; not project-selected | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_word_align.v` | `3ea49668a3d7d3420e2811267c7ddd02961f53e3` | 5718 | vendor PHY RTL | PHY word alignment helper | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v` | `c9b88f73406658877a967ff66ba743d068edd773` | 1909 | vendor PHY RTL | PHY word gear-box helper | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/phy/rx_clk_gen.v` | `340bec85ccc756f8338783f381a6b1974e217c14` | 10463 | vendor PHY RTL | PHY receive-clock generator | Yes — exact blob |
| `fpga_rtl/vendor/anlogic_camera/sensor/ui_imx415_reg.v` | `a129bc78ae5fd93a6dd54ce967f13c2acbef58d2` | 13070 | vendor sensor RTL | Base IMX415 register sequencer | Yes — exact blob |

### Manual adaptation source record (not a direct blob)

| Source path | Blob ID | Bytes | Category | Required manual action | Direct blob import |
| --- | --- | ---: | --- | --- | --- |
| `doc/imx415_camera_bringup.md` | `0e96907b2e78ce4e9fa3a7dd067eaf4e43608ed9` | 3493 | camera documentation | Replace its `.codex/skills/anlogic-td-fpga/scripts/run_td.py` commands with a target-repository local rebuild entry that is actually available and does not depend on `.codex`; then review the adapted text. | **No — manual adaptation required** |

## 4. Vendor snapshot integrity boundary

All 11 `fpga_rtl/vendor/anlogic_camera/` files are a byte-preserving vendor
snapshot. A future importer must retain them exactly, must not repair
whitespace, and must rely on the target's existing
`fpga_rtl/vendor/** -text !eol` `.gitattributes` rule. The SHA256 values below
are computed over the new source commit's blob bytes, not a checkout.

| Vendor path | Blob ID | Bytes | SHA256 |
| --- | --- | ---: | --- |
| `fpga_rtl/vendor/anlogic_camera/SOURCE_ORIGIN.md` | `07b4176b635171a17c367ca06ff710d713f53bd6` | 1256 | `3688a31d90e3c28fa24689aa027f1b3c95c880df65cdad748ec5bf3b11eac795` |
| `fpga_rtl/vendor/anlogic_camera/clocks/ui_pll.v` | `ff49393d73b393b640f4a017e8f815c589bf264f` | 3617 | `78bc9f58ea9bba6d35098528305ae47093ac5c2a46c5f47c27c5a5c8c2bdacb9` |
| `fpga_rtl/vendor/anlogic_camera/phy/auto_delay_ctl.v` | `0236575f588ba1cc1e59ea7c96824f5a875b37dd` | 6156 | `1cb7a1dbb11250cf60797ea4b73b6b09ec9f5382b81043afcc21d00e7b1643f9` |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_byte_align.v` | `481ed8c79b54b10e9c735659dc8ffdb6d6c9ad0b` | 5375 | `419e5b763400db97812dd81c58c8c64179350a842379a19e9cc77e4b62f0c7ec` |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_clock_det.v` | `655c4d6ef0fedb1df5cf3a8e142b460361e1f331` | 3490 | `c2f231ece2ed453d3520accb7753067198bbec272acbdb280331ef5be686682a` |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_hs_data_phy.v` | `f17ee3e38594ad3b271449f0d0e648e4c8fb8b8c` | 2735 | `ae3e15af71213a38b186a56f4f89592d4b895e08ddf8199492e3eddb138c47aa` |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_phy.v` | `1f38991ad13f6adb8f1c6a89e9e7ae8b5aad3a00` | 6409 | `a5e391bc77eb5967ca1e3a4515411bb464a8c641f70b7c59c1e4fa96094a5bcf` |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_word_align.v` | `3ea49668a3d7d3420e2811267c7ddd02961f53e3` | 5718 | `1f4e3b3b136f8fbb14de703ae7623a15c6f8ff78394418449b0d532091ca1b9d` |
| `fpga_rtl/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v` | `c9b88f73406658877a967ff66ba743d068edd773` | 1909 | `aa88fbade5ca2e29e245c7ba2f615a28587aea6d7d5e44fd545638dd63607d5e` |
| `fpga_rtl/vendor/anlogic_camera/phy/rx_clk_gen.v` | `340bec85ccc756f8338783f381a6b1974e217c14` | 10463 | `86de5ed01d390c84839699519c652326d013ed041137889cf01518ff5a3fab28` |
| `fpga_rtl/vendor/anlogic_camera/sensor/ui_imx415_reg.v` | `a129bc78ae5fd93a6dd54ce967f13c2acbef58d2` | 13070 | `4a058e988125a68a129fd00645fd641dd991443ded1d2a840090ec2bdc028af3` |

## 5. Dependency-closure audit

The audit uses the new source tree, then classifies each repository-internal
dependency of the 88 direct blobs as **target-existing** or **this batch**. TD and ModelSim files that
are outside the repository are marked **external tool dependency**, never
assumed to exist in Git. Result: **PASS — no unclassified or missing
repository-internal dependency found for the 88 direct blobs' declared entry
points.** The excluded bring-up source record is not part of this PASS result.

| Dependency class | Observed closure | Classification |
| --- | --- | --- |
| Verilog ``include`` | No ``include`` directive occurs in any of the 88 direct paths. | No include-file closure required. |
| Verilog module/IP closure | Camera top resolves through this batch's CSI, sensor, crop, ISP, packer, UART, and camera-vendor modules. `csi2_async_event_fifo` requires `soft_fifo`; board top requires `sgdma_pll`. | Camera/vendor modules: this batch. `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Soft_FIFO/RTL/soft_fifo.v` and `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/sgdma_pll.v`: target-existing. |
| TD primitive closure | ISP line RAM and Gamma LUT use PH1 ERAM; runners load `PH1_PHY_GSR` and, where applicable, FIFO/RAM simulation models. Build/sync scripts import `ph1_90.db`. | TD installation files, device DB, and PH1 primitives: external tool dependencies. |
| `$readmemh` / `$readmemb` / initialization | No `$readmemh` or `$readmemb` occurs. `gamma_lut_10to8.v` passes `gamma22_10to8.dath` to the vendor ERAM `INIT_FILE` parameter. | `fpga_rtl/camera/isp/color/gamma22_10to8.dath`: this batch; ERAM implementation: external TD primitive. |
| ModelSim runners and testbenches | Eight new runners under `fpga_rtl/tb/`, ISP-local `run_camera_isp_modelsim.ps1`, and their 11 new camera/ISP testbenches are listed in section 3. Runners that call shared discovery source `fpga_rtl/tb/tool_paths.ps1`. | New runners/testbenches: this batch. `tool_paths.ps1`: target-existing. `vlib`, `vmap`, `vlog`, `vsim`: external ModelSim dependencies. |
| Vendor simulation models | Runners name TD `sim_release` PH1 ERAM, reset, global, FIFO, RAMFIFO, and FIFO-control model files. | External TD tool dependency; no vendor simulation-model blob is silently required from the repository. |
| TD project, Tcl, ADC/SDC | `imx415_camera.al` names its camera RTL/vendor sources and both `imx415_camera_board_top` constraints; the sync/build/diagnose Tcl scripts name the same project family. | Project, Tcl, ADC, and SDC: this batch; TD commands and device DB: external TD dependency. |
| Python helper | `camera_reference.py` imports no repository file and uses only Python built-ins. | This batch; Python interpreter: external tool dependency. |
| Documentation-declared entry points | The two direct `doc/` files and direct `fpga_rtl/camera/isp/README.md` name only this batch's project, RTL, validation, Gamma-table, and runner paths (or excluded generated paths). | Direct-document closure is this batch or explicit external tool dependency. The bring-up source blob is excluded as an unclosed manual adaptation. |

The source sync Tcl contains `remove_source
../fpga_rtl/camera/isp/ui_ram_demosaic.v`. That is an explicit removal of an
unused source, not a dependency. The named file is neither present in the
source direct range nor required by this closure. Similarly,
`csi_rx_phy.v` is retained as a vendor snapshot but is not selected by the TD
project; its absence from the project source set is recorded, not inferred.

## 6. Excluded and manual paths

- `README.md` is the sole modified source path in
  `457439e..6b398c1`. It is a manual item, is **not** one of the 88 direct
  blobs, and must never be imported as a complete blob. A later owner may
  manually extract only camera-documentation increments into the shared README
  after review.
- `doc/imx415_camera_bringup.md` is a new source path, but also a manual item,
  not one of the 88 direct blobs. Its source text invokes
  `.codex/skills/anlogic-td-fpga/scripts/run_td.py`, which is absent from
  target `3442c65` and not supplied by this batch. Before any import, adapt it
  to a reviewed, target-repository local rebuild entry that does not depend on
  `.codex`, then re-audit the resulting documentation and entry closure.
- Generated TD runs, reports, bitstreams, ModelSim libraries/logs, temporary
  directories, and waveforms produced by a simulator remain outside this
  direct-import approval.
- A source-object scan of the two direct `doc/` files, direct ISP README, and
  all nine direct ModelSim runners found no other `.codex` entry. The source
  root README and the source bring-up document both have `.codex`-dependent
  rebuild invocations; both are manual items, and this audit creates no
  wrapper or copies neither blob.
- This batch does not include JPEG encoding, PCIe transport, SGDMA/DMA,
  slot ownership, reset/recovery work, or a board integration change.

## 7. Evidence boundary and non-claims

This records the source delivery's stated evidence boundary exactly:

- ModelSim behavior regressions passed.
- TD synthesis, placement, routing, and bitstream generation completed.
- Setup and hold timing did **not** converge (the recorded final slacks are
  negative); the build script correctly treats that as failure.
- Readability/profile gates did **not** all pass.
- IMX415 sensor, PHY, FMC path, and board behavior remain untested.
- No JPEG or PCIe transport is included or validated by this camera batch.

The passing behavior regressions do not establish timing closure, analog PHY
integrity, image quality, real frame rate, board pin correctness, or Linux
transport compatibility.

## 8. Revalidation procedure for a future importer

Before importing any direct blob, rerun the fixed-range checks, verify the
source total is 89 and the direct total is 88, check all 88 direct target paths
for collisions, compare each direct-table OID and size to `6b398c1`, and
recompute the 11 vendor SHA256 values from Git blob bytes. Confirm the target `.gitattributes` still has
`fpga_rtl/vendor/** -text !eol`. Re-run the closure audit against the selected
entry points and report every external TD/ModelSim requirement explicitly.
Do not treat closure as PASS for the bring-up document until its manual,
`.codex`-independent adaptation has been reviewed.

Do not proceed if any check differs. This document authorizes neither an
automatic import nor a workaround for a missing dependency.
