# 实际候选扫描器与 RX/RT 双故障短测

仅新增本目录验证文件；没有修改生产 RTL/IP、旧工程、服务器、Git 或板卡。
ModelSim `D:/App/modelsim/win64`，SE-64 2020.4；Python 3.12.9 使用本机显式路径。
本组纯 RTL 单元/组合仿真不使用 TD 器件模型。

| 检查 | 结果 | 证据目录（仓库根相对路径） |
| --- | --- | --- |
| 实际候选 `ph1a_rx_delay_scan` 独立矩阵 | PASS，217/217，编译警告 0 | `tmp/runtime_fix_20261028/validation/results/scanner_candidate_r02_native/` |
| 真实 byte/word aligner、gearbox、parser、RX/RT mailbox，恢复开启 | PASS，363 检查，警告 0 | `tmp/runtime_fix_20261028/validation/results/trace_recovery_r01_native/recovery/` |
| 同链路 strict 默认参数，无 recovery override | PASS，363 检查，警告 0 | `tmp/runtime_fix_20261028/validation/results/trace_recovery_r01_native/strict_default/` |

扫描 runner 必须传 `--source-root`，直接读取实际候选生产文件，按原始字节复制后编译；
没有旧 runner 的 `--candidate-first-edge` 文本替换路径，也没有 Git 导出或 tmp RTL 冒名。
本次 scanner SHA256 为
`c2c10d56465e074be32ebeac5aec08e402986037670771aa7be92424364f20cb`。
模拟后再次核对实际源和封存副本一致。输入刺激由公开的 tap-load 事件独立排程，
窗口选择由 Python 最长非循环区间模型计算，不依赖被测 FSM 延长 valid。
矩阵含随机稀疏窗口、32 码单点/单洞、首/尾/平局/不环绕、粘高 lane、错开 lane、
状态复位与停钟、活动阈值边界和两轮重试。生产参数下 63/64/65 个外部连续有效边沿
分别拒绝/接受/接受；64 边沿计数实际读为 64，tap31 最小窗口也通过。

组合测试先用无假 SoT 的 CRC 正确 RAW10 行作负对照，确认无 RX 首错与 RT 冻结。
再于 FS2320 后注入 lane3 提前两拍 B8，实际生产 aligner/gearbox 将原始
`21097e2b` 形成 `00097e2b`；parser 接收的是真实坏字，没有补头或改 ECC。
第一个坏帧保留原身份负终结，RX 精确为 W0=`09108791`、W1=`00097e2b`。
恢复 FS2321 后，通过同一字节链原样发送另一坏头 `80000000`，然后发送 FS2322。

恢复模式的两个新 FS 都获得互不别名的有效身份，live fault 最终为 0；strict 默认
模式继续失信，live fault 最终为 1。两模式都保持真实 ECC 错误状态与第一份 RX 诊断。
恢复模式 parser 触发两次，strict 一次；两模式 recorder 都只 freeze 一次、generation
始终为 1。RT 首次 40 槽逐拍对照触发前 32 拍、触发及后 7 拍日志；第二次故障和恢复后
再读 40 槽，metadata 和全部 256-bit payload 与首次读逐字相同。

RX 使用生产 `cfg_diag_snapshot(DATA_WIDTH=128)`，RT 使用生产
`rx_first_loss_trace` 的 RAM/SYS mailbox；两者 ACK/请求保持期间跨越恢复和第二次故障，
持有的数据不变，完成四相握手后的新请求仍返回第一份证据。RT index63 的 live 视图
另外证明当前 sequence=2322、trust 与模式一致，同时冻结视图仍属于首错。
runner 核对 RT packing 与实际 receiver 表达式、生产 RX mailbox 类型/宽度、core strict
默认值，并对实际生产文件及编译副本封 SHA256、结束时复核。

命令（仓库根目录，`--name` 每次必须全新）：

```powershell
& 'python' -I -B refactor/hdr_rx_runtime/src_fpga/simulation/runtime_recovery/scanner_matrix.py --source-root refactor/hdr_rx_runtime --output-root tmp/runtime_fix_20261028/validation/results --modelsim-bin D:/App/modelsim/win64 --name scanner_candidate_r02_native
& 'python' -I -B refactor/hdr_rx_runtime/src_fpga/simulation/runtime_recovery/run_trace_recovery.py --source-root refactor/hdr_rx_runtime --output-root tmp/runtime_fix_20261028/validation/results --modelsim-bin D:/App/modelsim/win64 --name trace_recovery_r01_native
```

首个 `scanner_candidate_r01` 尝试保留：ModelSim vlib 在 Windows 沙箱启动时报
WinError623（系统 DLL 重定位），RTL 未编译，模拟 NOT_RUN；按已登记环境改为原生
Windows 执行后得到上述结果。该工具启动阻塞没有改写为 RTL PASS。

全部命令、输入 SHA、日志、CASE 表与逐槽 mailbox 数据在各目录的 `RESULTS.json`、
`CASES.json`、`TRACE_READBACK.json`。本组不证明电气采样、传感器真实波形、完整 UART
串行化、TOP quiet、ISP/JPEG、综合、P&R、时序或板级；这些门禁均 NOT_RUN。
