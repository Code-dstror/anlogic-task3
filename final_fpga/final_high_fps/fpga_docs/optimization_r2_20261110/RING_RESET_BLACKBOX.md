# JPEG DDR 六槽环独立黑盒短测

2026-11-10，基线和候选的功能仿真均为 **PASS**。两臂分别通过字节、槽位和终态记分板，且撤复位后的 1,411 个 DFI 边沿采样中的 READY、quiet 电平和逐拍事件轨迹完全一致。

测试作者仅使用[公开合同](../../fpga_prj/verification_archive/experiments/ring_data_qual_r3_20261110/PUBLIC_CONTRACT.md)、
[端口](../../fpga_prj/verification_archive/experiments/ring_data_qual_r3_20261110/PORTS.vh)及[不透明清单](../../fpga_prj/verification_archive/experiments/ring_data_qual_r3_20261110/OPAQUE_SOURCES.json)。
以相同的 7.502 ns DFI 时钟、两眼各三槽、16 MiB 槽、writer tag/result 开启及 mask 关闭配置运行。
AXI BFM 分开处理 AW、W、B、AR 和 R，按 WSTRB 写入稀疏字节存储。
记分板独立生成预期字节、元数据、每眼槽轮转和代次，按实际边沿握手逐项核对。

## 场景与观察

| 风险 | 两臂结果 |
| --- | --- |
| 首帧写入债务及提前提交 | 首帧 4,167 字节，261 个 DATA 拍，尾 KEEP 为 `007f`。RESULT 在复位后第 644 个采样接受，最后 W 在 653，最终成功 B 在 663，ACK 在 671。最后 W 后连续 9 个边沿无最终 B、成功 ACK 或本帧 READY。检查每次 AW 承诺的 W 及 B、4 KiB 边界、字节地址和写掩码。 |
| ACK 持有与反压 | 旧 ACK 被持有时，第二眼 START 保持待接。前两帧窗口记录到 START 10、DATA 378、AW 4、W 89、AR 4、R 13、ACK 6、READY 15、PAYLOAD 13 个 stall 样本。RESULT 保持到真实接受，该窗口 RESULT stall 样本为 0。 |
| 读尾、正常退休与 quiet 分工 | READY 按提交顺序领取。全量读回字节及尾 KEEP 正确，尾拍反压 6 拍且保持稳定，read-complete 在尾拍后出现。前置负例得到 BUSY，错误代次得到 STALE，匹配退休得到 OK。第一眼的 OK 响应在第 1060 拍接受，第二眼仍欠的最终 B 在第 1062 拍接受。观察到 writer quiet 为高且 pending READY 或 reader owned 时 record quiet 为低，最终两个 quiet 均为高。 |
| 失败 B 与原地恢复 | 失败帧在最终 B 接受 `SLVERR` 后收到 error 3、成功长度 0 的 ACK，未发布 READY。下一帧不复位，RESULT 和最终成功 B 均在第 1132 拍接受，随后完成 ACK、读出和正常退休。 |
| 两眼所有权及复用 | 两眼都走过各自三个槽。分配在接受 START 时推进，失败帧仍消耗该次分配。两眼初槽分别复用至 generation 2。第一眼复用记录按冻结身份读出和退休，第二眼复用记录作为协调复位前持有的 READY。 |
| 冷启动及停钟释放 | 首次冷启动、DFI 停低且停钟期间撤复位、DFI 停高并先恢复时钟再撤复位，三例均在 R4 首次接受 held START。停低复位前保留一个尚未领取的 READY，且 AXI 无债务。两个重启后的合法首帧均以 generation 1 完成写入、读出和正常退休。 |

每臂 10 个 START、10 个 RESULT、26 个 AW 和对应 B、285 个 DATA 和对应 W、24 个 AR、278 个 R 和对应 PAYLOAD。
共接受 9 个成功 ACK 和 1 个失败 ACK，8 个记录正常退休，另一个已提交 READY 由无 AXI 债务的协调复位丢弃。
两臂各观察到 1 个 `DROP_PULSE` 和 8 个 `READ_DONE_PULSE`，仅记录其 A/B 周期。
外部 SAFE 由下游 BFM 在实际接受并核对全部字节、确认读债务排空并经过独立延时后给出。

## 复现与封印

清单中的封印输入就绪后，在工作树根目录执行。每次创建新的输出目录。

```powershell
$ringResetReplay = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
& '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe' -I -B -X utf8 `
  'refactor/camera_fusion_r1/src_fpga/simulation/blackbox_ring_reset_r3/run.py' `
  --modelsim-bin '<TOOLS_ROOT>/modelsim/win64' `
  --td-root '<TOOLS_ROOT>/TD_Release_2026.2.210.850' `
  --out "refactor/camera_fusion_r1/tmp/ring_reset_r3_blackbox_replay_$ringResetReplay"
```

实际运行使用 ModelSim SE-64 2020.4 和 TD 6.2.3.210850 的官方 DRAM 模型。
编译前后均校验清单内源和模型哈希。精确命令、完整哈希、工具版本及状态在[运行回执](../../tmp/ring_reset_r3_blackbox_20261110_01/run.json)。
同一目录中保留两臂独立的 `01-vlib-work.log` 至 `08-vsim.log` 及 `events.trace`。
子进程上限 50 秒、suite 上限 165 秒、仿真上限 75 µs 和每个复位段 6,000 个采样沿。实测最长子进程 2.62 秒、仿真完成于 11.650607 µs。

| 输入或证据 | SHA-256 |
| --- | --- |
| Opaque manifest | `dc2ee5a1899ba5c7d117982396ff1f39c16acd7b0258d30bea7dbe9e25a46d70` |
| Baseline ring（`eade457d7477110605f90eb5abc08420d8936642`） | `5c45615f818173b96a25a1a184691f8ffcdd3ef2155fa54581804b6e567153e1` |
| Candidate ring | `eed3c6b1955a465ac113d7492134d298fe9a62c7727d8c88b4c64c5379248b5b` |
| Baseline reset boundary | `853d83f71203279c75efc425406a5a6cfe705cd6f80b4f466324e9d93993fcea` |
| Candidate reset boundary | `edbfec8204a35ebc67331c4a397861caaf5295d780dc2829ecd8d356a6413f97` |
| 独立 testbench | `1f6dc9c789f4d8f68b9c3fb1c897c7662ed472de134fff889a593cd779f31b00` |
| 独立 AXI BFM | `494686f2fc5ddd38e70bddfcac081b2cca0a32cbcc80ef4b6fe91eed75bb30d9` |
| 比对 runner | `3f9166c81b4c7a24dbf7adc970cb47183a041d6cc90cc8b8c845ab5c840979d2` |
| 两臂事件轨迹 | `0734779a59b3861133f4a1ea49603e55a81d608ec4941c43fa1734e22b768dd2` |

本运行覆盖环及其 DFI 复位边界。实际 PCIe SAFE、满幅持续帧率、综合、P&R、物理时序和板级在本黑盒运行中均为 **NOT_RUN**。
