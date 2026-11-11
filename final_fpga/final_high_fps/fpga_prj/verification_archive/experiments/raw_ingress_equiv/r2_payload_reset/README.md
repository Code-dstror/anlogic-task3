# RAW10 上下文 payload 复位 A/B

本实验比较已采用的五窗口叶和隔离候选。源码身份见 [不透明清单](OPAQUE_SOURCES.json)。
候选只把 `context_data`、`context_timestamp`、`context_calibration` 和 `source_identity`
移到原 `start_allowed` 采样条件下的无复位正缘块。行列、`frame_uhd`、计数、SOURCE 判定状态和
输出所有权继续按原复位与时序。未改时钟或 SDC。

复位把状态清到 IDLE，同时取消上下文待发计数和输出 VALID。此时 SOURCE 匹配入口无所有权，
AXIS 输出 payload 受 VALID 屏蔽。正常 SOF 的 START 与全部 context/identity 取同一边沿的输入，
下一个或更晚的边沿才可使用已写齐的快照。前一终态同拍转移并接收下一 SOF 时，采样条件仍命中，
从下一边沿开始使用新快照。非法几何的 SOF 仍按原 START、ABORT 路径输出，
ABORT 状态无 CONTEXT 或 SOURCE 匹配资格。停止时钟时复位仍立即清除所有权，恢复后第一笔
合法 SOF 可在第一个正缘重写完整 payload。独立验证边界见 [公开合同补充](PUBLIC_ADDENDUM.md)。

从仓库根使用已登记的 Python 与 TD 运行。

```powershell
$rawProbePython = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
$rawProbeTdRoot = '<TOOLS_ROOT>/TD_Release_2026.2.210.850'
& $rawProbePython -B refactor/camera_fusion_r1/experiments/raw_ingress_equiv/r2_payload_reset/run.py --name payload_reset_fresh --td-root $rawProbeTdRoot
```

使用第一轮相同的两个载体、`area_prior`、`partition`、`add_map_lut_struct on`、
`min_control_set 2` 与 4 线程。每臂 160 秒 watchdog，只运行原生 `opt_gate` 和重开。
命令、输入及报告哈希见各臂 `RESULT.json`，运行保存于 [payload_reset_r2](runs/payload_reset_r2)。

## 结果与取舍

| 载体 | 原始 gate 及重开 Slice | #lut | FF | 8 ns SWNS | history→DATA | count→DATA |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| HD/UHD compact | 730→715 | 840→829 | 1,008→1,007 | +4.706→+4.567 ns | +6.201→+6.201 ns | +5.056→+4.875 ns |
| CAM1 fixed LONG | 666→640 | 664→669 | 899→898 | +4.478→+4.601 ns | +6.201→+6.500 ns | +4.776→+4.870 ns |

四臂原始 gate 与同 AL 重开面积文件各自逐字节相同。叶 logic LUT 分别 552→540 和 495→475。
各臂 ERAM/DSP 均为 0。综合和重开均 PASS，按上表每行基线、候选次序耗时
39.547/41.875 秒及 37.328/52.421 秒。最小值路径无有效端点。

作为容量回收，两个载体分别少 15 和 26 Slice。UHD 载体 count→DATA 的门级估计下降 0.181 ns。
候选仅保留为实验，当前生产采用已经验证的五窗口版本。该实验的独立功能、物理四类 STA、整机综合、
P&R、bitgen 和板级均为 NOT_RUN。
