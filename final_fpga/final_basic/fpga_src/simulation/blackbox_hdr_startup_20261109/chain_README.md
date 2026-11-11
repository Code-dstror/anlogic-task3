# HDR 双眼冷启动黑盒短测

独立测试使用[公开启动合同](../../../docs/seed12fix_20261109/STARTUP_PUBLIC.md)。两眼通过公开 I²C 引脚完成真实 HDR 配方，再由夹具驱动 4×1 全裁剪的对齐 CSI WORD。链路经过真实 CSI parser、crop、两眼各自的 TD 成员 FIFO、pair gate 和 pair 反馈 CDC，观测边界为 RAW 与 SOURCE。

CAM0 从完整 LONG/SHORT pair 开始。CAM1 先收到一帧 CRC 正确的孤立 SHORT，之后两眼各接收八个完整 pair。夹具逐拍检查暖机无 RAW 或 SOURCE，并禁止稳定标志早于第八个好 pair。随后每眼发两组，核对 RAW10 的舍入和饱和、单 beat SOF/EOL、角色、同组身份以及真正 FE 后的 SOURCE 终态。第一组 CAM1 SHORT 的 READY 在观察到 VALID 后再延迟 32 个 PIX 周期，检查 VALID 和完整 SOURCE bundle 持有到交接。两组都检查退休后 quiet。

## 结果

| 运行目录 | 暖机观察，按 CAM0/CAM1 | 终态 |
| --- | --- | --- |
| [chain-baseline-v4](../../../tmp/seed12fix_20261109/chain-baseline-v4/result.json) | GOOD 8/0，BAD 0/6，stable `01`，暖机无 RAW/SOURCE | `WARMUP_LIVENESS_FAIL`。等待三个 pair deadline 后 CAM1 仍未稳定 |
| [chain-candidate-v1](../../../tmp/seed12fix_20261109/chain-candidate-v1/result.json) | GOOD 8/8，BAD 0/0，stable `11`，暖机无 RAW/SOURCE | `PASS`。8 个 RAW beat，8 个正 SOURCE，最终 GOOD 10/10、quiet `11` |

两次运行的 I²C 观察均为 139 次完成写入且 index 为 138。候选 SOURCE 交接序号如下，字段中的 session/epoch 分别为 `391ab04e` 和 `20261109`。模拟日志的 `hold` 是每个成员的累计停顿周期。

| 已准入组 | CAM0 LONG/SHORT | CAM1 LONG/SHORT |
| --- | --- | --- |
| 第一组 | 9/9 | 9/10 |
| 下一组 | 10/10 | 10/11 |

A/B 的公共输入 SHA-256 一致。板测提交 `4a08ae35391e7b7ea6767260d7d1b4b182ef4bb9` 的 gate SHA-256 为 `9a8aaad1b7e59827c9afb0ddfd539bcbc3f78ca39002a1a0e2861f4c789fb2ae`，候选为 `280f801799e867fb4bba438be1a6fbf05eb601066d9095c9bcc89600c2be0286`。共同夹具 SHA-256 为 `223334fc21fe1b2134b51c3e70df5a5980e3e126ec0a4057c3cb8aa7a8813446`。ModelSim SE-64 2020.4 和 TD 2026.2.210.850 模型的独立运行各约 4.6 秒，仿真分别到 1.846 ms 和 1.857 ms。每个目录的 `result.json` 保存命令、输入与模型哈希和公开结果，`simulate.log` 保存原始轨迹。

保留的早期运行包括 `chain-baseline-v1`（不透明编译清单缺冻结 SDR 表，装载失败），以及 `chain-baseline-v2`、`chain-baseline-v3`（公开合同缺 CFG 本域释放前置，START 在 500 ns 的复位释放期被忽略）。补齐依赖和复位边界后，基线与候选共用同一夹具和预期。

## 复现

在仓库根目录用本机 Python 3.12 与明确的 ModelSim 和 TD 路径启动。每次提供新的 `chain-` 运行名。Runner 墙钟上限 85 秒，HDL watchdog 7.9 ms。

```powershell
$bench = 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_startup_20261109/chain_run.py'
$modelsim = 'D:/App/modelsim/win64'
$td = 'D:/App/TD_Release_2026.2.210.850'
python $bench --variant baseline --run-id chain-baseline-repro --modelsim-bin $modelsim --td-root $td
python $bench --variant candidate --run-id chain-candidate-repro --modelsim-bin $modelsim --td-root $td
```

基线复现以非零状态报告活性失败。基线输入取公开合同规定的 board gate 副本。证据覆盖上述小几何仿真。综合、P&R、物理时序与板级均为 `NOT_RUN`。
