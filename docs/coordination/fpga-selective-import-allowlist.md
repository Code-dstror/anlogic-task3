# FPGA selective import allowlist

## 1. Purpose and immutable source

This document freezes the file-level boundary for a future FPGA delivery into
the Linux transport history.  It is an import gate, not an import operation.

- Source branch: `origin/feature/fpga-pipeline`
- Source commit: `457439ed79e4d21a213fcfbda4c493b01f88326b`
- Important source commits:
  - `53ffd3add64e0685e7fa2c196b2248ac4cac517d`
  - `5b751eb9e6ba081b2e4b9f381d90491b19098cbf`
  - `457439ed79e4d21a213fcfbda4c493b01f88326b`
- Target baseline: `e4d3c82d679868e4aa2a770e0185b9a503dd9c1c`

The two histories have no common ancestor.  Do not merge unrelated histories
and do not directly cherry-pick an entire FPGA commit.  A later integration
imports only the files in this allowlist from the fixed source commit.

## 2. Vendor authorization boundary

The project lead has confirmed with the competition organizer that relevant
Anlogic TD/IP content in the competition materials may be placed in the
team's Private Git repository.  That authorization is limited to team Private
Git collaboration; it does not imply permission for public redistribution.
Before a public repository, public release package, or external source-code
delivery, review the authorization again and exclude vendor content unless a
new explicit authorization has been obtained.

Keep `SOURCE_ORIGIN.md` and `SHA256SUMS.txt` with each vendor snapshot.
The PCIe/SGDMA snapshot has 25 upstream files that are byte-for-byte
identical; the Soft FIFO 3.0 snapshot has 6.  The vendor-hashes gate is PASS
for 31 files, and the vendor-origins gate is PASS for 31 files.  This records
the team's received competition authorization scope and engineering gates; it
is not legal advice.

## 3. Direct-import allowlist

Each row is a file that exists in source commit `457439e`; Blob ID and Size
are the source tree's Git blob object ID and byte size.  `Direct` means the
file may be selected from that commit, subject to the procedure gate below.

| Source path | Blob ID | Size | Role | Source handling |
| --- | --- | ---: | --- | --- |
| `fpga_prj/anlogic2026.al` | `86c577d1900e3d4181dd6cd413b802dda39d3cd4` | 11694 | Anlogic project | Direct; retain source blob |
| `fpga_prj/scripts/build_pcie_c2h_project.tcl` | `71bc9ee73a763801f2cdf190c07a0145b144ceff` | 1950 | project build TCL | Direct; retain source blob |
| `fpga_prj/scripts/export_pcie_c2h_postroute.tcl` | `7970d257b8890606eefb020e06178962d05ebdf0` | 1583 | post-route export TCL | Direct; retain source blob |
| `fpga_prj/scripts/sync_pcie_c2h_project.tcl` | `c5be1cce2fe3311ff881e752c3c5d7cee61719dc` | 4297 | project sync TCL | Direct; retain source blob |
| `fpga_rtl/constraints/pcie_c2h_test_top.adc` | `84fc6a50d572fb65ed9ab42727a98fb658802e4d` | 382 | Anlogic constraints | Direct; retain source blob |
| `fpga_rtl/constraints/pcie_c2h_test_top.sdc` | `71d01527273901823485b8f8a1de4c4712be756c` | 1230 | timing constraints | Direct; retain source blob |
| `fpga_rtl/include/pcie_feature_defines.vh` | `d34d3489aa0e2fae83081014358d1af1cb64cb88` | 268 | feature definitions | Direct; retain source blob |
| `fpga_rtl/include/pcie_protocol_v1.vh` | `0ddeea5b0c89bfe968127fa339fb9874363faf6d` | 2165 | generated Verilog protocol header | Direct generated artifact; do not edit; regenerate/check |
| `fpga_rtl/ip/pcie_axis_async_fifo_config.md` | `796b50afb0d6ddae0480aad05c0b36f3a26cafab` | 912 | FIFO IP configuration | Direct; retain source blob |
| `fpga_rtl/pcie/axis_frame_fifo_ip.v` | `dd50b8afc8b37e66a91dff382d1b8a20d082936b` | 3793 | FIFO wrapper RTL | Direct; retain source blob |
| `fpga_rtl/pcie/axis_frame_fifo_ip_spec.md` | `db3da75fb1938e0e2032667133dcfa027fa83b71` | 1227 | FIFO wrapper specification | Direct; retain source blob |
| `fpga_rtl/pcie/c2h_frame_tx.v` | `6563e99fd5191e70241c6bcb453735d99fe8958d` | 13381 | C2H transmit RTL | Direct; retain source blob |
| `fpga_rtl/pcie/c2h_frame_tx_spec.md` | `ca78860e54c2db898928f3a99b888082a9a0f629` | 1418 | C2H transmit specification | Direct; retain source blob |
| `fpga_rtl/pcie/c2h_inband_test_source.v` | `e9b70e2fd22ead0aea7e375ac9720f8be234b201` | 3014 | in-band test-source RTL | Direct; retain source blob |
| `fpga_rtl/pcie/c2h_inband_test_source_spec.md` | `66a813ee7f757c65130edf3acc31264f06466888` | 608 | in-band test-source specification | Direct; retain source blob |
| `fpga_rtl/pcie/c2h_test_source.v` | `4f9af10653c22942f387a0609f43a60c2d190153` | 6277 | C2H test-source RTL | Direct; retain source blob |
| `fpga_rtl/pcie/c2h_test_source_spec.md` | `ec726141530620bc6c9a19328fc0fb321583649e` | 981 | C2H test-source specification | Direct; retain source blob |
| `fpga_rtl/pcie/h2c_stream_checker.v` | `61dcc27525008cd94f7bcd67bf4730bf44753af6` | 3418 | H2C stream-checker RTL | Direct; retain source blob |
| `fpga_rtl/pcie/h2c_stream_checker_spec.md` | `f39c0878fed9f41a6fc5b7bf3d781ccfa45a6398` | 874 | H2C stream-checker specification | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_app_regs.v` | `943fed61a9f65092a6fcb460048b59680c3e3c8a` | 12606 | PCIe application-register RTL | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_app_regs_spec.md` | `0fb87f849321cfb3f827ac1f61020f33a94d7df2` | 1068 | application-register specification | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_c2h_test_top.v` | `c9d5d7b96e19a4c8cb58e560c783d59683b8c077` | 8473 | PCIe C2H top RTL | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_c2h_test_top_spec.md` | `a017da1412512f9589a6b4935f6a386941f0c095` | 1548 | PCIe C2H top specification | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_inband_header_adapter.v` | `4d071f5f4574bd95b15fa1b5dbfd51bb8e752db2` | 7420 | in-band header-adapter RTL | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_inband_header_adapter_spec.md` | `c8cdb29bfb72956c4d827b707cfd9acf6ea2dd9e` | 1509 | header-adapter specification | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_sgdma_endpoint.v` | `424c04b98bc99563c3a0c829c1702262ea93726c` | 7438 | SGDMA endpoint RTL | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_sgdma_endpoint_spec.md` | `308757a4e0afa7a3e5a6f5549f0d73914730e735` | 1159 | SGDMA endpoint specification | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_video_transport.v` | `0b8ce5bbcec523bb14a34fba61482f6aa154c6f2` | 9900 | video-transport RTL | Direct; retain source blob |
| `fpga_rtl/pcie/pcie_video_transport_spec.md` | `6ed27b1be34cf624240da67df60552f7f58eb156` | 1521 | video-transport specification | Direct; retain source blob |
| `fpga_rtl/tb/run_modelsim.ps1` | `e54461e52f08af34e6ce214db7fce5b6576c81b5` | 2681 | ModelSim runner | Direct; retain source blob |
| `fpga_rtl/tb/run_postroute_modelsim.ps1` | `e03b147c081b00fa6bfefb9757eac6239732cb5e` | 3834 | post-route ModelSim runner | Direct; retain source blob |
| `fpga_rtl/tb/run_sgdma_transactions_modelsim.ps1` | `6a2b64cf606cc430c7543fa9a8e5b96369bc2dc2` | 1521 | SGDMA ModelSim runner | Direct; retain source blob |
| `fpga_rtl/tb/run_vendor_fifo_modelsim.ps1` | `8797b6cc83849dc735b834fa430ec17b49e18d3d` | 2089 | vendor FIFO ModelSim runner | Direct; retain source blob |
| `fpga_rtl/tb/run_vendor_pcie_modelsim.ps1` | `aee900c0a008330404333515ac9dd655b125cb1f` | 4651 | vendor PCIe ModelSim runner | Direct; retain source blob |
| `fpga_rtl/tb/run_video_transport_modelsim.ps1` | `3c43305d463424a674b95be6c7e4fbbf879ce0d2` | 2021 | video transport ModelSim runner | Direct; retain source blob |
| `fpga_rtl/tb/stubs/pcie_sgdma_endpoint.v` | `589b8a7a536b73de03ea4f8cda5f4acba80c5331` | 3525 | SGDMA endpoint simulation stub | Direct; retain source blob |
| `fpga_rtl/tb/tb_axis_frame_fifo_ip.v` | `1314e4a14defa7217a40c66299863d90df07ab8a` | 2802 | FIFO testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_c2h_transport.v` | `4743a798f1f4313fee0648e7b11d8cdffe2fb4f5` | 10220 | C2H transport testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_h2c_stream_checker.v` | `72ec024e4ceadf192b3753871e25f1774bae3ebc` | 3001 | H2C checker testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_pcie_app_regs.v` | `d1c430301506d1120cd2e8f5754e33739e848ec1` | 5636 | application-register testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_pcie_c2h_postroute.v` | `1300594e028590a8c876e20ea06d15b318d17666` | 1159 | post-route testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_pcie_inband_transport.v` | `27bee75057a21d90a0cea4f054f6bb2b8b7a4fca` | 10519 | in-band transport testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_pcie_video_transport.v` | `edf0eccda9b84b5c011a0ac8591040d097ab6ace` | 15982 | video-transport testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_sgdma_transactions.v` | `fcd657303f1f84d1163f9ca2f04c90cacf4cd197` | 15162 | SGDMA transaction testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_sgdma_transactions_spec.md` | `b526878b23df3b465d8a41d1f0846fd4c7e9a66b` | 2171 | SGDMA transaction test specification | Direct; retain source blob |
| `fpga_rtl/tb/tb_vendor_pcie_probe.v` | `22e61eadd4a6378cf62579f177e3e5a858326139` | 3705 | vendor PCIe probe testbench | Direct; retain source blob |
| `fpga_rtl/tb/tb_vendor_pcie_probe_spec.md` | `bd8c7f9b81eaf355f34de2aa0744957e47b63c40` | 2144 | vendor PCIe probe specification | Direct; retain source blob |
| `fpga_rtl/tb/tool_paths.ps1` | `a7f314e76c8218f3a53c8f40318a545e612459b7` | 3987 | tool-discovery script | Direct; retain source blob |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/SHA256SUMS.txt` | `d94fd4c24c5c539bcd19742b7163c154ca688288` | 2463 | PCIe/SGDMA integrity manifest | Direct; retain exact snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/SOURCE_ORIGIN.md` | `666bc760077d4e605cb14de7620777ec73ef77ba` | 1269 | PCIe/SGDMA provenance | Direct; retain exact snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE.adc` | `0692bd2738a890e624300065a552e8784d9c0dfe` | 410 | PCIe vendor constraint | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE.dat` | `64e926aaf30523963ccac5810412ac239e731da7` | 8960 | PCIe vendor data | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE.ipc` | `690ff139787bafe0da9b26488b93a598c1ed9046` | 11798 | PCIe IP registration | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE.sdc` | `bcea42229e2c9876acf84cc68d12133706072a37` | 1149 | PCIe vendor timing constraint | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE.txt` | `ff944fde472cf9e9c3ef5a0a48280b394092ab67` | 1394 | PCIe vendor data | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE.v` | `3ee1615294a1f475ed0791ac427933bf18590c97` | 190282 | PCIe vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE_ph1_dbi_init_mux.v` | `a726a31e28f1a62ad60a64c31e9ee652df7532cb` | 12050 | PCIe vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE_ph1_pcie_basic_top.v` | `690a55c5a7b93e0465a57aa2f3fcf5c837f80ea8` | 117389 | PCIe vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE_ph1_pcie_cfg_rom.v` | `7e9fec4752c766646499d8cebf268b028e2a959d` | 1489 | PCIe vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE_ph1_pcie_clock_ctrl.v` | `8775d0e54e367ea3f8b658216ca0cf9061ff4321` | 19154 | PCIe vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/PH1_LOGIC_PCIE_ph1_pcie_core_pll.v` | `273ab550780379f5fe99ad5b3bf63c9255c2cfc9` | 3141 | PCIe vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/al_pcie_ip.dat` | `64e926aaf30523963ccac5810412ac239e731da7` | 8960 | PCIe vendor data alias | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/al_pcie_ip.txt` | `ff944fde472cf9e9c3ef5a0a48280b394092ab67` | 1394 | PCIe vendor data alias | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/sgdma_pll.ipc` | `1f07fb9dd5fb590c649651ecdf5c99f208bd943b` | 2135 | SGDMA PLL registration | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/sgdma_pll.v` | `9caf6a9068080ffe6fc02b0617aed885660ae4f9` | 3437 | SGDMA PLL vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/bridge/case_ep/al_pcie_if_ep.v` | `349b42c46370b1eedfbb7429da3a97d18f1a3d88` | 85509 | SGDMA vendor bridge RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/bridge/rx_if/pcie_rx_bypass2rc.v` | `3f39e2d62f54c47d87fc2763241dcccb3b07f395` | 29515 | SGDMA vendor receive RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/bridge/rx_if/pcie_rx_trgt2cq.v` | `6f048136aaad19a96f170b256d66a233c996f486` | 33326 | SGDMA vendor receive RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/bridge/sideband_if/pcie_sideband_dbi2mgmt.v` | `4f15639487c0d2514d302de3ecceaa8bf7c5d3b8` | 9015 | SGDMA vendor sideband RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/bridge/sideband_if/pcie_sideband_msi.v` | `aaba0c36b2e7768728fbb34693fafa8724709163` | 15159 | SGDMA vendor sideband RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/bridge/tx_if/axi4_st_mux.v` | `ded0e49f4a4b668f055cc1470e337c6347b4f675` | 7801 | SGDMA vendor transmit RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/bridge/tx_if/pcie_tx_client02rq_new.v` | `e189afafe41666fcaa8291e1a5ab657a38b917db` | 26039 | SGDMA vendor transmit RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/bridge/tx_if/pcie_tx_client12cc.v` | `4cb4b6200ad831ae81d3d5402aab0274415bc924` | 20974 | SGDMA vendor transmit RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/sgdma_subsys.v` | `1d54323822dda619974c7991a6c85dc0a946bbe4` | 73188 | SGDMA vendor subsystem RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/src_enc/sgdma_ip_all.enc.v` | `2e69b14c6f792de960db1e1d085139438e148619` | 1287183 | encrypted SGDMA vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Component.xml` | `233d4c2b295719a2a209dfc24e04b02324324767` | 45229 | Soft FIFO vendor component metadata | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Dependency.tcl` | `d007283cc3edd7993e0cd3975b4ab3d5e0420e8e` | 14992 | Soft FIFO vendor dependency TCL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Layout.tcl` | `202fb5053649e9f953bd4ff90835dba2115fe786` | 10414 | Soft FIFO vendor layout TCL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/SHA256SUMS.txt` | `3477571efd1d34335fabd957ecdb6a2053235bda` | 538 | Soft FIFO integrity manifest | Direct; retain exact snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/SOURCE_ORIGIN.md` | `52988c30f7e5c58d9913462cd6c6dfaf9204eca8` | 948 | Soft FIFO provenance | Direct; retain exact snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Soft_FIFO/Other/plugin_mid.tcl` | `808c6ec2c5a0712518a463d2da6a50dc827c95d9` | 1880 | Soft FIFO vendor plugin TCL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Soft_FIFO/Other/soft_fifo_v3_0_changelog.txt` | `27086f021d5f403b05b3aa08bd01f5bcdeff8839` | 265 | Soft FIFO vendor changelog | Direct; byte-exact vendor snapshot; verify hash/origin |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Soft_FIFO/RTL/soft_fifo.v` | `01f0dd43de4fc0335a7f2b0b093ddad17b8c57bb` | 183789 | Soft FIFO vendor RTL | Direct; byte-exact vendor snapshot; verify hash/origin |
| `doc/pcie_protocol_v1.json` | `80b2cfc3a7290b5c87a367255eee14499f0c337d` | 1292 | authoritative protocol generator source | Direct; authoritative generator source |
| `doc/pcie_protocol_v1.h` | `c7a1b67bb679688994eda31d70aaab7cc668cc5d` | 2165 | generated C protocol header | Direct generated artifact; do not edit; regenerate/check |
| `doc/pcie_video_transport_integration.md` | `ff885f882b8826f6ef6ad81c6ccfaa0ef6fa4e3b` | 8421 | video transport integration notes | Direct; retain source blob |
| `doc/pcie_c2h_implementation_status_20260914.md` | `33d990a474baefbb6c6e5828f052eea03e1efa7b` | 6925 | C2H implementation status | Direct; retain source blob |
| `doc/pcie_functional_simulation_attempt.md` | `0597f6be8784071cedfe484d275f0d9493c46440` | 8821 | functional simulation record | Direct; retain source blob |
| `doc/FPGA_RK3576_PCIe接口与数据传输协议总结.md` | `162df7c6b64628e5603bed13eb630aff4222d7bf` | 26431 | FPGA/RK3576 PCIe protocol summary | Direct; retain source blob |
| `tools/generate_pcie_protocol.py` | `b545f5b55c89a3092f4ee4446d27c20dd6b535ed` | 3595 | protocol header generator | Direct; retain source blob |
| `tools/verify_vendor_hashes.ps1` | `0382f4f0415d7d3385c2aee97cf6e4507ece125a` | 4784 | vendor integrity verifier | Direct; retain source blob |
| `docs/coordination/pcie-v1-single-logical-jpeg-stream.md` | `35e10d3f251dd2ef802580d0e6bdba5c3848ab07` | 9663 | single-logical-JPEG-stream decision | Direct; retain source blob |

`doc/pcie_protocol_v1.json` is the authoritative generation source for both
`doc/pcie_protocol_v1.h` and `fpga_rtl/include/pcie_protocol_v1.vh`; the
generator is `tools/generate_pcie_protocol.py`.  The generated files are kept
in the delivery for C and Verilog consumers, but must not be edited manually.
Every later import validation must regenerate them or perform an equivalent
consistency check.

## 4. Manual-integration allowlist

The following source content must never directly overwrite target files.  It
may only be integrated manually in a later, separately reviewed change.

- `.gitattributes`: integrate only rules needed to preserve vendor binary/byte
  content.
- `.gitignore`: merge only TD, ModelSim, temporary, simulation, and FPGA-build
  generated-artifact rules.
- [`docs/coordination/fpga-confirmation-checklist.md`](./fpga-confirmation-checklist.md): retain the `e4d3c82`
  Linux file as the authoritative structure.  Port only FPGA-owner answers,
  evidence, status references, and the single-logical-stream link from
  `457439e`; do not overwrite the whole file.  Locate material by heading,
  Question ID, and answer block, never by a fixed line number alone.
- `README.md`: do not directly import the FPGA source branch's root README or
  overwrite the shared root README.  Its invocation of
  `.codex/skills/anlogic-td-fpga/scripts/run_td.py` must not be carried over as
  the shared repository's only rebuild entry point.  A later integration must
  provide one repository-local rebuild entry that does not depend on `.codex`:
  either a reviewed lightweight TD-call wrapper, or an FPGA-specific README
  that records the exact TD batch/TCL command.  Only one is required; do not
  duplicate both.  This allowlist sets that gate and does not create a wrapper
  or FPGA README in the current document task.
- `AGENTS.md`: do not overwrite the shared root AGENTS.  Future FPGA-specific
  rules belong in the applicable FPGA subdirectory.

## 5. Explicit denylist

The denylist is a future import gate; it does not require deleting existing
history from the FPGA source branch.  Do not import any of the following:

- `.codex/**`, `doc/2026安路.pdf`, `fpga_rtl/.gitkeep`, `local_refs/**`,
  `official_package/**`, `tmp/**`, `work/**`, `sim/work/**`, `*_Runs/**`,
  `fpga_prj/log/**`, or `fpga_prj/reports/**`.
- bitstream, `bin`, `mcs`, `sof`, SDF, netlists, simulation libraries,
  waveforms, `log`, `report`, `qor`, `timing`, `area`, `db`, `dump`, or
  `journal` artifacts.
- `__pycache__`, `pyc`, virtual environments, or a direct overwrite of root
  `README.md` or root `AGENTS.md`.
- Any `457439e` file not listed in the Direct-import allowlist.

## 6. Path and ownership decisions

- Keep `fpga_rtl/` and `fpga_prj/` paths for this selective import so verified
  TCL, project, and relative paths do not change unnecessarily.
- Do not move the project into `fpga/` merely because the Linux branch contains
  `fpga/.gitkeep`; directory restructuring is a separate future task.
- Root `README.md` and `AGENTS.md` retain their shared-repository meaning.
- `doc/pcie_protocol_v1.json` is the current authoritative generator source
  for FPGA transport constants.
- [`interface/pcie-jpeg-protocol-v0.1.md`](../../interface/pcie-jpeg-protocol-v0.1.md)
  remains a cross-workstream DRAFT.  It
  must not silently overwrite the JSON, and must not be described as the same
  authoritative source.  Their formal freeze/generation relationship requires
  a separate future protocol decision.

## 7. Integration procedure gate

The following are future steps only; none are performed by this document task.

1. Create a new integration branch from `e4d3c82` or its reviewed successor.
2. Verify the source commit is still `457439e`.
3. Import only the Direct-import allowlist.
4. Handle the Manual-integration allowlist separately and manually.
5. Before the integration commit is complete, close this blocking rebuild-entry
   gate:
   - From fixed source commit `457439e`, verify the actual project entry and
     TCL script names; do not invent a TD executable name, command-line
     arguments, TCL filename, or environment variable.
   - Provide the one `.codex`-independent repository-local TD rebuild entry
     required in section 4: either the reviewed lightweight wrapper or the
     FPGA-specific README with the verified TD batch/TCL command.
   - Document required external tools and their verified or observed versions:
     TD, ModelSim, and Python when the protocol generator requires it.  Those
     tools remain external dependencies and do not enter Git.
   - Document tool discovery, any necessary environment variables or
     configurable paths, and the exact invocation starting from the shared
     repository root.  A missing tool must produce a clear error and must not
     silently succeed.
   - Verify that the entry does not read denylisted `.codex`, `local_refs`, or
     machine-absolute paths.  In an environment with the corresponding tools,
     run the rebuild or applicable minimum validation and preserve its command
     and result.  If a tool cannot run in the available environment, record it
     as Untested with the missing condition; do not claim reproducible
     validation passed.
6. Verify no denylist file is present.
7. Verify vendor hashes and origins.
8. Verify generated protocol files are consistent.
9. Run available FPGA simulation/static checks and the complete Linux unittest suite.
10. Run Custom `/review`.
11. Fix findings, review again, commit, and use a normal push.
12. Do not use force push.

## 8. Current non-claims

- No board is available, and RK3576 is not Tested.
- Real camera input, all three preprocessing stages, and the JPEG encoder are
  not complete.
- At fixed source commit `457439ed79e4d21a213fcfbda4c493b01f88326b`, the
  test payload was not a standard JPEG.
- Post-import commit `418bf4d` on `feature/linux-transport` introduced mode 3:
  a fixed 331-byte, 1×1 grayscale JPEG fixture.
- SGDMA/PCIe simulation does not establish board enumeration, DMA, or
  completion-length verification.
- DDR slot, IRQ, reset/epoch, and automatic recovery remain TBD/Deferred.
- This allowlist approves only the file-import boundary; it removes no hardware
  implementation gate.
