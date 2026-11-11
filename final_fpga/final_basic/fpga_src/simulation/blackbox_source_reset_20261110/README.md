# SOURCE 复位与 cleanup 独立短测

测试台依据 [公开合同](../../../docs/parameter_timing_20261110/SOURCE_RESET_PUBLIC.md)、[SOURCE 端口](../../../docs/parameter_timing_20261110/SOURCE_PORTS.txt) 与 [cleanup 端口](../../../docs/parameter_timing_20261110/CLEANUP_PORTS.txt) 建立独立计分。ModelSim 按 [opaque 清单](../../../experiments/timing_source_20261110/OPAQUE_SOURCES.json) 编译真实 `private_rgb_source_borrow4` 与 `hdr_pair_product_abort_drain4`。测试台只接公开端口，实际 context、RGB SOF 和首个 SOURCE notice 握手进入 cleanup。负源用例的下游预处理尾部由可反压夹具提供。

SOURCE 使用 `MAX_WIDTH=1920, MAX_HEIGHT=1080, NR_ENABLE=0, NEUTRAL_STATS_ENABLE=0, DEHAZE_ENABLE=0`，输入为 8×2、每帧四组 RGB。cleanup 使用 `SYNC_CLEAR_ENABLE=1, SEPARATE_DATA_RESET=1, FALLING_INPUT_RESET=1`。计分只在 PIX 正沿的有效握手推进，逐位比对 96 位 RGB、keep、SOF/EOL/LAST、tag/index、576 位 context 与 notice，以及 processed SOURCE 的 frame、lease、job、pair、write tag、member、error。反压时检查呈现及内容保持。每个完整帧必须实际收到 processed SOURCE 且恢复 pool idle。

| 场景 | 刺激与终态 | 基线 | 候选 |
| --- | --- | --- | --- |
| `r4_first` | DFI 先释放。R3 高相位额外停 83 ns，F3 后低相位额外停 67 ns。首 context 在 R4 接收，错 tag SOURCE 单独计入 stale，帧 1 成功退休。无复位切换身份，帧 2 的末组与原 SOURCE 同沿呈现，成功退休。 | PASS | PASS |
| `reassert_r3` | PIX 先释放。在 R3 高相位、F3 前重断言 PIX 复位，PIX 仍高时释放，再执行新的 R1–R4。帧 3 未成交，帧 4 成功退休。 | PASS | PASS |
| `reset_context` | context 已呈现且未接收，PIX 停低、DFI 停高，断言 PIX 复位。旧呈现撤回，帧 6 成功退休。 | PASS | PASS |
| `reset_rgb` | RGB 已呈现且未接收，PIX/DFI 均停高，断言 DFI 复位。旧呈现撤回，帧 8 成功退休。 | PASS | PASS |
| `reset_notice` | notice 已呈现且未接收，PIX/DFI 均停低，断言 DFI 复位。旧呈现撤回，帧 10 成功退休。 | PASS | PASS |
| `reset_result` | processed SOURCE 已呈现且未接收，PIX 停高、DFI 停低，断言 PIX 复位。旧呈现撤回，帧 12 成功退休。 | PASS | PASS |
| `negative_cleanup` | 四组 RGB 实际成交后注入匹配的负源。预处理尾部跨下降沿保持，直至有效握手才允许局部 clear。局部 control/data clear 均解除后发布失败 STATUS，反压保持 drain 所有权，STATUS 成交后解除。帧 13 错误退休，帧 14 健康退休。 | PASS | PASS |

两版首 context 均在第 4 个有效 PIX 正沿成交，帧 1 的 processed SOURCE 均在第 38 个有效 PIX 正沿成交。负帧 13 在第 39 沿观察到 cleanup 提交脉冲、第 47 沿接收失败 STATUS、第 48 沿接收错误 processed SOURCE。

首轮基线的 `reset_rgb` 在 DUT 复位前触发夹具断言。DFI 已处在目标电平末端，原夹具的 1 ns 延迟撞上翻转。改为等待所需方向的 DFI 边沿后停钟，保留首轮 `FAIL_ASSERTION`。随后两版各执行完整七个场景。结果、输入哈希和原始日志入口见 [VALIDATION.json](VALIDATION.json)。

## 复跑

在仓库根目录的 Windows PowerShell 中使用本机登记的工具。每个版本独立冻结编译输入并建库。整轮墙钟限制 55 秒，每场景另有 20 µs 仿真 watchdog。两次调用使用同一测试台和参数，基线额外传入维护者导出的公开模块同名不透明文件。

```powershell
$sourceResetPython = 'python'
$sourceResetRunner = 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_source_reset_20261110/run_blackbox.py'
$sourceResetOptions = @('--repo', 'C:/fpga_workspace/anlogic-task3', '--modelsim-bin', 'D:/App/modelsim/win64', '--td-root', 'D:/App/TD_Release_2026.2.210.850')
& $sourceResetPython -X utf8 -I -B $sourceResetRunner @sourceResetOptions --variant baseline --baseline-source 'C:/fpga_workspace/anlogic-task3/tmp/timing_source_20261110/run_20261110T031955Z_309077/baseline/private_rgb_source_borrow4.v'
& $sourceResetPython -X utf8 -I -B $sourceResetRunner @sourceResetOptions --variant candidate
```

实测范围为 direct profile、8×2 和指定 cleanup 下游夹具。厂商仿真模型数为零。综合、布局布线、物理时序、bitgen 和板级均为 `NOT_RUN`。
