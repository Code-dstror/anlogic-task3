# TOP 首作业 DJ 监视行为短测

2026-11-05 的生产 UART 已接入共享 SDR/HDR 首作业观察。本夹具保留原 SDR 窗口回归并补齐新诊断输入；七个新位、四 SOF 同拍、单/双 HDR 和新旧解码器兼容的直接生产门位于 [job_uart_hdr](../../../experiments/job_uart_hdr/README.md)。停钟时新增解析字段按 UNKNOWN 处理，原 PIX 数据仍逐位核对。

2026-11-04，仅新增仿真和本地结果，不改生产 RTL、提交、服务器或板卡。

`run.py` 从当前 `anlogic2026.v` 的唯一 `First stereo job watch` 标记开始，
提取至 `g_no_status_uart` 之前。DFI/PIX 两个实际 always、全部原始页打包和原生
`uart_status_observer` 实例逐字节保存为 run-local `production_job_watch.vh`，直接编译。
SOURCE_START/END 同时记录完整 TOP、提取区间、提取字节 SHA256、实际叶模块、夹具和生产解码器身份。
提取边界数量和测试前后字节不一致即失败；没有另写一份监视功能副本。

夹具只显式驱动生产监视器的本域输入，使用独立 SYS/PIX/DFI/USER/WORD 时钟。
UART、四相 snapshot 和生产 Python 解码器均真实运行。仅 UART 分频、报告间隔与 snapshot
超时在仿真中加速；监视器的 `[27:24]+7` deadline 表达式保持原样。
common-time 数值由 BFM 逻辑推进，**未等待 100 ms 的模拟器实际经过时间**：
首次 PIX 无进展的输入时间跨度为 109.440512 ms，刷新后的 DFI 无进展跨度为 117.440512 ms。
这是定时比较和冻结行为验证，不是相机、DDR 或首作业业务路径的故障复现。

最终 `monitor_r2`：**PASS，1308 checks，8 轮、1288 UART 字节，零警告，2.625 s**。

| 覆盖项 | 实际检查 |
|---|---|
| 首 job 身份 | RUN 起沿同拍的真实 TAKE 锁存 CAM1/local2、SOURCE `0x12345678`、generation `0x10203040`、session17、epoch3；后续输入 tuple 和后续 TAKE 不改首身份。 |
| 定时与进展 | deadline bin 之前不冻结；time-valid=0 不冻结；有效时间到原 deadline 才冻结；真实新 AR handshake 刷新 DFI deadline。 |
| 两域独立 | PIX 已冻结时 DFI 仍 watching；DFI 后独立冻结。每域只按自己的 RUN 重新开窗。 |
| 冻结与 STOP | 后续 levels/fault/milestone 噪声不覆盖首控制现场；STOP 后两域样本保留，实际 UART 仍输出且两域 fresh。 |
| 停钟与 freshness | DFI 重开而 PIX 停钟时，DJ fresh_mask=1，仅 DFI fresh；PIX 恢复后 fresh_mask=3，仍保留旧 PIX 冻结值，直到 PIX 自己重开。 |
| 下次 run | DFI 新首 job 更新 CAM0/local1、SOURCE `0xdeadbeef`、generation `0x55667788`、session23、epoch4，清旧 stall；真实 retire 后成功停止 watching。PIX 新 run 的同拍首 admission 清旧 stall 并锁成功现场，后续变化不覆盖。 |
| 线上页 | 实际 8N1 采集混合 OB/DJ/RX，生产 `FrameDecoder` 校验布局和 CRC；四个关键阶段的实际解码页与原样 TOP 页逐字段一致。 |

**当前冻结范围。** 首 DFI 身份、milestones/levels/error/gates 与首 PIX events/levels/ticket/admission 字段冻结。
DFI `job_count0/1`、PIX `fs_count0/1` 与 `raw_count0/1` 在 run 内继续累计，它们位于 watch 条件之外。
本测试实际注入后续 TAKE/FS/RAW admission，确认计数更新而首身份/控制字段保持。
STOP 后整页均停止变化；不能将运行中的冻结描述成全部 224 bit 都固定。
该语义已报告父代理，未擅自修改生产设计。

```powershell
& 'python' -B -u refactor/dual_unified_r1/src_fpga/simulation/first_job_observer_r1/run.py --name unique_name --modelsim-bin D:/App/modelsim/win64
```

本测试无需 TD 器件模型，不启动 TD。每次新 run 名，输出在候选 `tmp/first_job_observer_r1/<name>/`。

- [最终 RESULTS](../../../tmp/first_job_observer_r1/monitor_r2/RESULTS.json)
- [原样提取与源身份](../../../tmp/first_job_observer_r1/monitor_r2/SOURCE_START.json)
- [四阶段实际解码](../../../tmp/first_job_observer_r1/monitor_r2/DECODED_PHASES.json)
- [原始运行日志](../../../tmp/first_job_observer_r1/monitor_r2/run.log)
- [实际 UART 二进制](../../../tmp/first_job_observer_r1/monitor_r2/top_job_uart.bin)

生产完整 TOP、真实业务可达性、传感器、DDR/JPEG/PCIe、综合、P&R、时序、bitgen和板级均 **NOT_RUN**。
本任务未发现上述覆盖范围内的功能错误；运行中 live 计数与控制字段冻结的区别按实际行为保留。
