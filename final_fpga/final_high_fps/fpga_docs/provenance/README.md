# camera_fusion_r1 独立融合候选

当前本地已采用JPEG熵核等价面积优化，以及PIX/DFI数据资格与ASR分离，生产封印为`df8064e9`。
独立黑盒、三项组合的真实产品链及整体read_design/原生层次通过；新源整机综合/物理资格尚未运行。
[本轮优化进度](../optimization_r2_20261110/PROGRESS.md) · [初次融合验证](../QUALIFICATION.md) · [功能与参数矩阵](../MODE_MATRIX.md)

22:40后按用户要求收尾，优化源`43dbc3f1`已推送并获ACCEPTED：一次SYN4运行，80个PHY4等待共享检查点。
[80种子构建回执](../SERVER_OPT_BUILD_20261110.md)

远端保留的`eade457d`回退基线已完成SYN4：原始63921 Slice（99.38%）、重开63334（98.47%）、265ERAM/149DSP。
20个PHY4仍绑定该固定源；已取回5份Placed报告，Slice96.43%–96.67%，setup为负，不等于Routed结果。
见[固定服务器批次](../SERVER_BUILD_20261110.md)和[布局参考](../optimization_r2_20261110/PLACED_BASELINE.md)。

同一生产工程支持 HD 单目、HD 双目、双曝光 HDR，以及单目 4K15/20 JPEG 或 RAW10。
沿用高帧率工程的速率、共享几何、DDR 槽生命周期和 JPEG 流水。HDR 加入平衡与旧兼容
融合、四档 Tone、渐进高光保护以及 RGB Q8 白平衡。手动白平衡也适用于 4K SDR JPEG，
与灰度、高斯及 HE 使用同一帧级配置。UART DJ/v4 同页记录 CFG 状态和两眼物理 FS。

原生工程是 [rfcamera_fusion_r1.al](../../fpga_prj/al/rfcamera_fusion_r1.al)。原生运行目录为
`fpga_prj/rfcamera_fusion_r1_Runs/`，由 TD 创建。输入见 [SOURCE_MANIFEST.json](SOURCE_MANIFEST.json)
和 [SOURCE_SEAL.json](../SOURCE_SEAL.json)。合并的版本、冲突与取舍见 [合入记录](../INTEGRATION.md)。

## 本机入口

在仓库根运行。`$fusionPython` 和 `$fusionTdRoot` 取根 `ENVIRONMENT.local.md` 核实的 CPython 3.12 与
TD Release 2026.2 / 6.2.3.210850 路径，日志写入新工程的 `tmp` 子目录。

```powershell
$fusion = (Resolve-Path refactor/camera_fusion_r1).Path
$native = Join-Path $fusion fpga_prj
$logs = Join-Path $fusion tmp/native
New-Item -ItemType Directory -Path $logs -Force | Out-Null
& $fusionPython -B "$fusion/tools/seal_inputs.py" --check
& $fusionPython -B tools/run_td.py "$native/scripts/check_read_design.tcl" --td-root $fusionTdRoot --workdir $native --log "$logs/read_design.log"
& $fusionPython -B tools/run_td.py "$native/scripts/open_camera_shared.tcl" --td-root $fusionTdRoot --workdir $native --log "$logs/reopen.log"
& $fusionPython -B tools/run_td.py "$native/scripts/check_shared_hdr_owner.tcl" --td-root $fusionTdRoot --workdir $native --log "$logs/hierarchy.log"
```

静态同步使用 `seal_inputs.py` 重算当前输入。TD 如仅将工程 `Path` 保存为本机绝对路径，
可在关工程后用 `seal_inputs.py --normalize-project-path --check` 还原为 `.` 并核对封印。
再用根 `tools/check_td_project_portability.ps1 -ProjectFiles` 核查该 `.al`。
日志路径每轮独立，已存在其他阶段输出时另取专用验证工程目录。

## JPEG 熵核局部面积对照

以固定源 `eade457d` 为基线，局部载体使用 TD 6.2.3.210850、PH1A90SEG324-2、
PIX 8.000 ns、SYN16、面积优先和 partition。每臂 170 秒进程看门狗，独立 AL/Runs。
独立功能短测使用 ModelSim SE-64 2020.4、同一 TD 模型、流式银行与 RST 参数，
JPEG 条带为 1920×16 和 3840×32，单仿真进程限 56 秒。
[方案](../optimization_r2_20261110/AREA_PLAN.md)
· [面积与时序原件](../optimization_r2_20261110/AREA_RESULTS.md)
· [独立功能对照](../optimization_r2_20261110/BLACKBOX.md)

## 运行与兼容

- [RK SDK](../../fpga_src/rk_sdk/README.md)、[4K 冷选](../UHD_RK_CONTROL.md)、[画质配置](../RK_QUALITY_CONTROLS.md)。新融合 4K 需配套本 SDK，以识别新增能力位。
- [UART DJ/v4](../UART_FIELD_V4.md)。新解码器可读旧 DJ/v1–v3。
- [CFG 独立短测公开合同](../../fpga_prj/verification_archive/verification_reference/QUALITY_CONFIG_PUBLIC.md)。使用本工程自己的测试和源哈希。

整机综合、P&R、物理 STA、bitgen 和板级均为 **NOT_RUN**。局部载体与父工程测量分别记录其范围。
