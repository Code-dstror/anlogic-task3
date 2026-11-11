# JPEG 跨域复位独立黑盒短测

固定基线 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213` 与当前候选均为 5/5 PASS。五例共 1,480 条公开采样与握手记录逐条相同。每侧完成 6 帧成功 RESULT、1 帧 E2 负 RESULT、2 帧复位取消、7 次 fence prove 与 3,718 个扩展 RAM 字比较。实际输入、SHA256、命令和日志索引见 [VALIDATION.json](VALIDATION.json)。

独立测试作者只使用[本轮公开合同](../../../docs/parameter_timing_20261110/JPEG_RESET_PUBLIC.md)和[出口公开线协议](../../../verification_reference/egress_public.md)，从确定性输入计算字节、KEEP、LAST、身份和扩展 RAM 小端字的期望值。两侧分别满足相同的独立断言后才比较 A/B 边沿。生产 profile 使用实际 FIFO、ERAM 和 fence；8.000 ns 源时钟与 7.502 ns 汇时钟异相。每帧包含三拍合计 38 个载荷字节，尾拍为 6 字节。扩展包含 128 个 flit、record-v2 身份和全禁用的 record-v4 形状。

| 场景 | 公开端口检查 | A/B 一致事件数 |
| --- | --- | ---: |
| 1 | 两侧冷释放。预先提供首笔 START，真实消费 RESULT 后取得 fence prove | 166 |
| 2 | 源第三个上升沿后拉长高相，再完成首笔。第二笔在源停低时撤销两侧复位，恢复后完成 | 336 |
| 3 | 扩展被借用且受压时停源于高相，仅断言汇复位。恢复后用不同身份完成下一笔 | 325 |
| 4 | E2 RESULT 被反压时停汇于低相，仅断言源复位。取消旧 RESULT，恢复后用不同身份完成下一笔 | 327 |
| 5 | 38 字节上报为 45 字节，消费 `ok=0/error=E2/length=45` 的 RESULT，再在同一复位会话中完成不同身份的成功帧 | 326 |

每笔覆盖 START、DATA LAST、扩展和 RESULT 的受压阶段，其中场景 3 在扩展阶段取消。扩展被借用时比较全部 410 个 RAM 字。已消费 RESULT 的帧在下一个 START 前再抽查身份、形状和补零位置，随后验证新 START 撤销旧扩展形状资格、新扩展写入新身份。扩展及 RESULT 待消费时，测试提前置汇 `quiet=1` 并保持相等的非零 RAW 计数，确认 fence 尚未证明。收到真实 RESULT 并排空后检查证明保持到请求撤销。

冷释放时，源侧第 10 个真实上升沿后采到 `reset_done`，第 11 个边沿后采到 START READY，第 12 个上升沿握手。汇侧 `reset_done` 于其第 10 个边沿后采到。拉长源高相时，在第三个边沿后 100 ps 开始暂停 43.123 ns，整个窗口保持源 `reset_done=0` 和 START READY=0。恢复后源侧的 done、READY 和 START 相对边沿仍为 10、11、12。停汇释放的恢复帧中，源侧相对边沿为 13、14、15。边沿对照只适用于本测试的时钟相位与刺激。

`run01` 的基线五例在本机墙钟异常之前完成，记录的基线编译和仿真进程累计 18.578 s。其后候选场景 1 有功能 PASS，但 ModelSim 同时记录 44 分 39 秒墙钟，场景 2–5 耗尽预算，整批标记 INCOMPLETE。`run02` 校验原基线的编译闭包、测试台、工具、模型和事件文件 SHA256 后复用，重做候选五例，17.281 s 完成。新批次的进程墙钟预算为 58 s，各仿真另设 50 µs watchdog。首轮文件、失败状态及原日志均保留。

ModelSim SE-64 2020.4 使用 TD 2026.2 / 6.2.3.210850 模型。两侧每例加载时均有四条相同的供应商模型告警。`ram40_sdp_fixed.v:69` 与 `ph1_logic_eram.v:52` 报两条 ECC 注入端口宽度诊断 `vopt-2241`，`ph1_logic_eram.v:1287` 报两条 INIT_FILE 索引诊断 `vopt-2697`。编译无告警，未屏蔽加载告警。

本记录的验证范围是合成前 JPEG 字节运输、扩展租约、复位资格、RESULT 和 fence。JPEG 编解码质量、满幅持续性能、门级复位脉宽、DDR/PCIe 完成和板级行为未覆盖。本黑盒任务中的综合、布局布线、物理时序、bitgen 与板级均为 NOT_RUN。

## 复现

从仓库根执行，并为 `--output` 指定新的运行目录。`--baseline` 指向从固定提交提取的两份不透明 RTL 文件。省略 `--reuse-baseline` 时使用独立库重新编译并运行两侧。

```powershell
& 'python' `
  'refactor/camera_raw_r2/src_fpga/simulation/blackbox_jpeg_reset_20261110/run.py' `
  --baseline 'tmp/parameter_timing_41cb_20261110/jpeg_reset/native01/baseline' `
  --modelsim-bin 'D:/App/modelsim/win64' `
  --td-root 'D:/App/TD_Release_2026.2.210.850' `
  --output 'refactor/camera_raw_r2/tmp/timing_jpeg_reset_20261110/blackbox/replay01'
```
