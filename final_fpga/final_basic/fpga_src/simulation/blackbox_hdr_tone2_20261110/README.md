# T96 HDR 四像素流独立黑盒短测

[公开合同](../../../docs/hdr_rate_seed56_20261110/TONE_PUBLIC.md)定义四像素 lane、时钟、握手、清除和整数算术。`tb_tone.sv` 在输入握手时用 64 位整数公式计算期望，在每个有效输出沿检查数据及 SOF、EOL、clipped。退休序列按握手写出，基线与候选分别通过公式检查后再比对序列 SHA256。

| 场景 | 验证内容 |
| --- | --- |
| `cadence` | HDR 和 SDR 各 24 组，下游持续 READY，检查接收间隔、首组退休延迟，记录退休间隔和尾部排空时间。SDR 包含 0、1022、1023、1024、16383。 |
| `numeric` | 4,096 组覆盖全部 16,384 个合法最大值和 96 个分段。各 lane 包含单通道最大、任意两通道并列和三通道并列。两套固定种子分别产生像素和 1 至 8 拍反压，组间穿插 1 至 3 拍供给间隙。 |
| `flow` | 保持 HDR 和 SDR 的 EOL 输出各一次，等待相反模式的首组。分别清除在途 HDR、清除被反压的 HDR 输出、复位被反压的 SDR 输出，每次随后退休一组独立新帧。 |

在仓库根目录用 PowerShell 7 运行。DUT SHA256 必须匹配传入的候选和指定的基线。

```powershell
& './refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_tone2_20261110/run_blackbox.ps1' `
    -TdRoot 'D:/App/TD_Release_2026.2.210.850' `
    -ModelSimBin 'D:/App/modelsim/win64' `
    -CandidateSha256 '21db78163fb014d03f0dd9f8fca3d325a4414397d9bd6ad2033d78c71c7a0442'
```

运行器为基线和候选各建库，以 `+define+PH1` 编译合同列出的 TD ERAM/DSP 模型和冻结的包装器。MIF 按 512 地址转换后放在各自的 `rom_init/`，供模型加载。每个 ModelSim 进程限 60 秒，每个仿真场景限 50,000 拍。新结果、日志、公开退休序列、初始化文件及输入哈希保存在 `tmp/hdr_rate_seed56_20261110/tone_blackbox/<run>/`。完整命令和裁决见 `result.json`，实测结果见 [VALIDATION.md](VALIDATION.md)。
