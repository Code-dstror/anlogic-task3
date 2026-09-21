# FPGA camera C1 selective-import allowlist

## 1. 目的、固定对象与非操作边界

本文是 `feature/linux-transport` 的第三份 camera 文件级导入门禁，沿用
[`fpga-camera-selective-import-allowlist.md`](./fpga-camera-selective-import-allowlist.md)
的 `docs/coordination/` 位置、固定对象、精确 blob 与 fail-closed 记录惯例。
它只定义独立 IMX415 首次上板前的 C1 修复候选；本文本身不导入 FPGA
blob、不会修改 TD 工程，也不执行仿真、构建或板卡操作。

- FPGA 历史 baseline：`6b398c144e7a563ea3d9fa6085ac3142813be2a7`
- 精确 source commit（C1）：`3e6cd85192e9131b87f89d861e7cfe77d5c89b27`
- 已审计 FPGA tip：`cd33b48e62068fb516f5060ef28e1e737fc122a0`
- 审计 target branch：`feature/linux-transport`
- 审计 target integration HEAD：`1ece71c0ab251792e264f4525d7b0990b85f72d8`

不允许以 merge、cherry-pick、checkout 或分支整体复制的方式取得这些内容。
后续单独批准的实现只能逐路径使用第 3 节列出的精确 source blob；不得顺带
引入 JPEG、DDR、PCIe、DMA 或 Linux 端到端增量。

**PRE_BOARD_GATE：BLOCKED。** 该 allowlist 仅定义待导入和待重验的最小
修复集合；在该集合真正导入、所列回归重跑、独立 TD 工程重新构建并产生新的
timing 报告，以及实际板卡前置核对完成前，首次上板门禁保持 BLOCKED。

## 2. 来源差异与 target 冲突检查

本 allowlist 只接受以下固定差异查询恰好得到的九条路径：

```bash
git diff --name-status \
  6b398c144e7a563ea3d9fa6085ac3142813be2a7 \
  3e6cd85192e9131b87f89d861e7cfe77d5c89b27 \
  -- <the nine paths in section 3>
```

观察结果为七个 `M` 和两个 `A`：FIFO RTL、RAW10 RTL、SDC、runner 与两个
既有 TB 为 `M`；FIFO spec 和 FIFO reset TB 为 `A`。target 树查询使用：

```bash
git ls-tree -l 1ece71c0ab251792e264f4525d7b0990b85f72d8 -- <each path>
```

结果是七个已存在路径和两个缺失路径。因而第 3 节中的操作类型是 target 状态的
精确描述：`REPLACE` 表示目标已有不同 blob，`ADD` 表示目标缺失，二者都不授权
任何自动操作。

## 3. 精确 direct-import allowlist

全部 source OID 与字节数均在 source commit 树以
`git ls-tree -l 3e6cd85192e9131b87f89d861e7cfe77d5c89b27 -- <path>` 取得，并以
`git cat-file -s <blob>` 逐项复核。OID 不得被换行符转换、人工编辑或替代 blob
替换。

| 操作 | 目标/来源路径 | 完整 source commit | source blob OID | Bytes | 当前 HEAD blob OID | 导入理由与直接依赖 |
| --- | --- | --- | --- | ---: | --- | --- |
| REPLACE | `fpga_rtl/camera/csi/csi2_async_event_fifo.v` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `0a8dc3e42b7a8614efc1f9d09dba2f0e1eee42c0` | 2050 | `1414a7700a6dba45574a07c4ca070d025894f9e8` | 将 wrapper 改为单一公共异步 reset，依赖同批的 `csi2_raw10_rx_stream.v` 适配端口；实例化已存在的 vendor `soft_fifo.v`。 |
| ADD | `fpga_rtl/camera/csi/csi2_async_event_fifo_spec.md` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `d7e2212245f2fa69632ac3db56be6b36532ca9a8` | 2120 | `MISSING` | 记录 FIFO reset assert/release、停钟域与 flush 合同；直接引用同批 FIFO RTL、reset TB 和 runner。 |
| REPLACE | `fpga_rtl/camera/csi/csi2_raw10_rx_stream.v` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `b6898d81f8f37f32fb39e542ee3791cc8d98daa1` | 4300 | `3fd4fe8cd670d1c00780c123a8bc14679a24cb03` | 唯一的 FIFO wrapper 实例点改接 `i_reset_n`；依赖同批 FIFO wrapper、同批 word core 与既有 `csi2_raw10_rx.v`。 |
| REPLACE | `fpga_rtl/camera/csi/csi2_raw10_word_core.v` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `753e4c9deae53f4f225edf2ae0e9167eb92f8b67` | 6163 | `76f6c077e462751524e814003ca508749c5d1342` | 修正 payload/CRC 同 32-bit 字边界计算、EOL 与 CRC 错误恢复；由同批 word-core TB 和既有 receiver runner 直接验证。 |
| REPLACE | `fpga_rtl/constraints/imx415_camera_board_top.sdc` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `0b27f6aedd1f7536f28072152aef3c0d0c0db679` | 1128 | `86dedc85fe8afc156896e5854df84675f8227ade` | 删除 `u_pixel_pll/pll_inst.clkc[1]` 未使用输出的时钟组引用；约束层级对应既有 `imx415_camera_board_top.v`。 |
| REPLACE | `fpga_rtl/tb/run_csi2_fifo_modelsim.ps1` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `0ca622e6d54ecfcb1089313e6b7513706bb44c00` | 2667 | `f0fb6f30e3f75abc523fc2cd985ae56c55603284` | 将新增 reset TB 放入 FIFO 回归；直接编译既有 vendor Soft FIFO、同批 FIFO/stream/core、既有 receiver TB 和同批 reset TB。 |
| REPLACE | `fpga_rtl/tb/tb_camera_watchdog.v` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `b9e093bb1d0411556825ba01eab4070078c812aa` | 9256 | `82b9c9b11a2df18b834f19a9d7ed2f93c22222d2` | 覆盖配置延迟不触发 watchdog、采集中 reset 清状态和恢复；由既有 `run_camera_watchdog_modelsim.ps1` 驱动。 |
| ADD | `fpga_rtl/tb/tb_csi2_async_event_fifo_reset.v` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `241d6a985d848e6d2ef1bfa36a1c67dc05c6f24c` | 3205 | `MISSING` | 验证异步 reset assert、读时钟延迟启动和未读数据 flush；直接依赖同批 FIFO RTL 与 runner。 |
| REPLACE | `fpga_rtl/tb/tb_csi2_raw10_word_core.v` | `3e6cd85192e9131b87f89d861e7cfe77d5c89b27` | `cb31bb101cdf9e80b5f8007eaca37d2170ee6f4d` | 12605 | `cd0f105564cfc4ba3cc958e26aa4dc1ccf44c181` | 为 5/10/15/20-byte CRC 边界、精确 EOL 与坏 CRC 后恢复添加断言；由既有 `run_csi2_receiver_modelsim.ps1` 驱动。 |

该表恰有 **9** 个不同路径：`ADD=2`、`REPLACE=7`。任何后续导入在路径数、
路径文字、操作类型、source OID、字节数或当前 HEAD OID 任一项不匹配时必须
停止并重新审计。

## 4. 依赖闭包与 TD 工程边界

闭包在仓库内完整：

- `csi2_async_event_fifo` 的 repository RTL 实例点是
  `csi2_raw10_rx_stream`；两个端口匹配改动同批导入。FIFO 的 vendor
  `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Soft_FIFO/RTL/soft_fifo.v` 已在
  target 存在。
- `csi2_raw10_rx_stream` 继续连接同批 `csi2_raw10_word_core` 及既有
  `csi2_raw10_rx`。本批 RTL 没有新增 Verilog ``include`` 或 fixture 文件。
- 当前 `fpga_prj/imx415_camera.al` 已列入三个 CSI RTL、既有 `soft_fifo.v`、
  board top 与 `imx415_camera_board_top.sdc`；因此 **无需修改** `.al`、
  build Tcl 或 sync Tcl 来获得这九项的 source-set 闭包。
- 既有 `tb_csi2_receiver_fifo.v`、`run_csi2_receiver_modelsim.ps1`、
  `run_camera_watchdog_modelsim.ps1` 与 `run_camera_csi_rgb_modelsim.ps1`
  已位于 target；新 FIFO reset TB 由同批 FIFO runner 显式编译和运行。
- TD device database、PH1 primitives、ModelSim 的 `vlib/vmap/vlog/vsim` 是
  外部工具依赖，不被误记为 Git 内待导入 blob。

### Target-existing validation dependencies

下表完整记录第 6 节四个计划 runner 在导入完成后使用、但**不属于**第 3 节
九项 allowlist 的 repository 输入。每个对象都在固定 target HEAD
`1ece71c0ab251792e264f4525d7b0990b85f72d8` 存在且受 Git 跟踪；OID 和字节数
以 `git ls-tree -l <target-head> -- <path>` 取得，并以 `git cat-file -s <blob>`
逐项复核。这些都是 `ALREADY_PRESENT/TARGET-EXISTING` 验证依赖，不能复制、
覆盖或纳入本轮九项导入。

| Target-existing 路径 | 使用者 / 用途 | target HEAD blob OID | Bytes |
| --- | --- | --- | ---: |
| `fpga_rtl/tb/run_csi2_receiver_modelsim.ps1` | 第 6 节 CSI receiver 回归启动脚本；编译第 3 节的 word core 与 word-core TB。 | `d22a2f4342d098784185ee637b2114a34e3767ea` | 1125 |
| `fpga_rtl/tb/run_camera_watchdog_modelsim.ps1` | camera watchdog 回归启动脚本；dot-source `tool_paths.ps1`，编译下列 `imx415_camera_axis.v` 与第 3 节 watchdog TB。 | `788dfbd8678b1112ffba66a9efd26c2f81c0b020` | 1888 |
| `fpga_rtl/tb/run_camera_csi_rgb_modelsim.ps1` | CSI→RGB 回归启动脚本；dot-source `tool_paths.ps1`，复制 Gamma 数据并编译以下所有 camera/ISP/TB 输入。 | `a09bacb583d2686ef924ec2d68f38066e31d7562` | 3470 |
| `fpga_rtl/tb/tool_paths.ps1` | 由 watchdog 和 CSI→RGB runner 以 `. (Join-Path $PSScriptRoot "tool_paths.ps1")` dot-source；仅解析外部 ModelSim/TD 安装路径，不再引用其他仓库文件。 | `a7f314e76c8218f3a53c8f40318a545e612459b7` | 3987 |
| `fpga_rtl/camera/imx415_camera_axis.v` | watchdog runner 编译的实际 camera top-level wrapper。 | `6017315fa2435fc1e83dacc801a97ee1e49821ca` | 5540 |
| `fpga_rtl/vendor/anlogic_soft_fifo_3_0/Soft_FIFO/RTL/soft_fifo.v` | 导入后的 CSI FIFO runner 及 CSI→RGB runner 编译的 vendor Soft FIFO RTL。 | `01f0dd43de4fc0335a7f2b0b093ddad17b8c57bb` | 183789 |
| `fpga_rtl/tb/tb_csi2_receiver_fifo.v` | 导入后的 CSI FIFO runner 的既有 receiver/FIFO 回归 TB。 | `ded1e1a447acd80ae430186319268fa81fa20103` | 9287 |
| `fpga_rtl/camera/isp/color/gamma22_10to8.dath` | CSI→RGB runner 用 `Copy-Item` 复制到运行目录；Gamma LUT 的初始化数据。 | `b0a25dbde891933b8f07cda7236e07381fa83755` | 3072 |
| `fpga_rtl/camera/isp/isp_line_ram_40x1024.v` | CSI→RGB runner 编译的 ISP line-RAM wrapper。 | `394dbd975a3d9018272e73952318d840d15189c4` | 1860 |
| `fpga_rtl/camera/isp/raw/raw_blc.v` | CSI→RGB runner 编译的 RAW black-level stage。 | `04bf28d42c81834ba6f6104d9afc6edfa0e20e1c` | 7156 |
| `fpga_rtl/camera/isp/raw/raw_row_window.v` | CSI→RGB runner 编译的 RAW row-window stage。 | `d73b4a9cdffeda11447a2349e2c6d47841344209` | 21734 |
| `fpga_rtl/camera/isp/raw/raw_demosaic.v` | CSI→RGB runner 编译的 RAW demosaic stage。 | `718e9cf188e03f30dc6f6541251054af56ee4cc3` | 20313 |
| `fpga_rtl/camera/isp/raw/raw_isp_top.v` | CSI→RGB runner 编译的 RAW ISP composition。 | `aba79733562e4816898fef51a43a38eaf96e90a9` | 7516 |
| `fpga_rtl/camera/isp/color/gamma_lut_10to8.v` | CSI→RGB runner 编译的 Gamma LUT consumer。 | `0b38dd2aac40a758720155d3ff9064d54717bfa2` | 1897 |
| `fpga_rtl/camera/isp/color/color_pipeline_axis.v` | CSI→RGB runner 编译的 color pipeline。 | `87a2086763c4fc583fd30f43ce19e524db6beabc` | 230136 |
| `fpga_rtl/camera/isp/isp_core_top.v` | CSI→RGB runner 编译的 ISP top。 | `cfb4f889ca72f9db3d015d92f2c8e86bb1a2dc3d` | 10057 |
| `fpga_rtl/camera/camera_raw_crop.v` | CSI→RGB runner 编译的 crop stage。 | `e32551822390f96501e0e921191cabacffd0bf8b` | 4165 |
| `fpga_rtl/camera/rgb_axis_packer.v` | CSI→RGB runner 编译的 RGB AXI packer。 | `274dfc8c1187a3ef2e3752e3170528793e3c1d38` | 5386 |
| `fpga_rtl/camera/camera_rgb_pipeline.v` | CSI→RGB runner 编译的 camera RGB composition。 | `da14dce58b28f20a0550349432c08e44ea9666d1` | 2914 |
| `fpga_rtl/tb/tb_camera_csi_rgb.v` | CSI→RGB runner 编译并以 `vsim` 执行的 integration TB。 | `4d5579419165546dba1c5622f6a1cebe8254a9d2` | 13066 |

解析依据如下：各 runner 先以 `$repo = Resolve-Path (Join-Path
$PSScriptRoot "../..")` 得到仓库根，再以 literal `Join-Path $repo ...`
构造表中路径；没有仓库路径通配符。CSI FIFO runner 的 `run_csi2_fifo_modelsim.ps1`
是第 3 节将被 REPLACE 的 allowlist 项，其 source 版本还会编译第 3 节新增的
`tb_csi2_async_event_fifo_reset.v`；其余四项 allowlist RTL/TB 均在第 3 节，
因此不重复列入本表。

对四个 runner 实际编译的 Verilog 输入及所有列出的 target-existing RTL/TB 执行
“匹配以 Verilog ``include`` 开头行”的 Git grep 后未得到匹配，故没有额外的
repository include-file 闭包。CSI FIFO runner 的 `$TdRoot/sim_release/**`，以及
CSI→RGB runner 由 `Resolve-TdRoot` 解析的 `$td/sim_release/**`（包括
`PH1_PHY_GSR` 和 PH1 FIFO/ERAM 模型），均是外部 TD 安装文件；`tool_paths.ps1`
只从环境变量、PATH 与本机安装目录解析它们，未动态解析新的仓库文件。

### SDC 的精确边界

该 SDC 变更只从第一异步组删除：

```text
u_pixel_pll/pll_inst.clkc[1]
```

当前 board top 将相应 PLL 输出接为 `unused_aux`；`clkc[0]` 仍为
`pixel_clk`。其余 sys/pixel、MIPI-ref/camera-PLL 与 recovered-clock 分组没有
因此被放宽。此修改是未使用 clock-object 引用的修正，**不是 timing closure
证据**。导入后仍必须由当前独立 TD 工程重新解析层级、重新 synth/place/route，
并以新生成的 setup/hold 报告判断时序。

## 5. 明确排除与延后项

- 不直接覆盖 camera build/sync Tcl、`fpga_prj/anlogic2026.al` 或 camera
  bring-up/validation 文档。target 的独立 `imx415_camera.al`、
  `register_camera.tcl` 前置流程、GUI Tcl 重建入口和保守 timing 边界必须保留；
  source 分支的共享工程脚本和正 slack 记录不能作为 target 当前事实。
- 所有 JPEG、DDR、PCIe/DMA 和 Linux 端到端增量均延后，包括其 RTL、约束、
  工程、testbench、reference model 和文档。
- `.codex/`、`.agents/`、所有 `AGENTS.md`、skills、`guidance/`、状态归档、
  ZIP/PDF/图片/日志及 `tmp/`、TD/ModelSim build 输出均不导入。
- vendor camera RTL blob 在固定 `6b398c1..cd33b48` 范围内没有变化。
  `SHA256SUMS.txt` 与 `SOURCE_ORIGIN.md` 只是新增/更新的哈希或来源元数据，
  不在本 allowlist 中。

## 6. 导入后的计划验证（未执行）

以下仅是未来导入完成后的计划，不构成本文已执行或已通过的声明：

```powershell
powershell -ExecutionPolicy Bypass -File fpga_rtl/tb/run_csi2_receiver_modelsim.ps1
powershell -ExecutionPolicy Bypass -File fpga_rtl/tb/run_csi2_fifo_modelsim.ps1
powershell -ExecutionPolicy Bypass -File fpga_rtl/tb/run_camera_watchdog_modelsim.ps1
powershell -ExecutionPolicy Bypass -File fpga_rtl/tb/run_camera_csi_rgb_modelsim.ps1
git diff --check
```

之后按 target 已有独立工程流程，在新的 TD GUI 会话中同步、诊断和重建
`fpga_prj/imx415_camera.al`，审查新生成的 source-set、约束解析、错误标记和
setup/hold timing 报告。不得复用历史 bitstream；不得把 source 分支、其他
工程或历史记录中的正 slack 当作当前 integration HEAD 的证据。

在上述回归、独立 TD 重建、新 timing 报告及实际板卡前置核对完成前，
`PRE_BOARD_GATE` 始终为 **BLOCKED**。
