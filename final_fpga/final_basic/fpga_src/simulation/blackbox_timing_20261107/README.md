# Camera RAW 定向端口仿真

夹具从公开 I/O 合同推导激励和预期，只通过端口观察握手、数据与状态。每组有
60 秒墙钟预算和仿真时间 watchdog。运行目录包含 `run.json`、原始 ModelSim
日志、精确 argv 和输入文件的前后 SHA256。

从仓库根目录运行。先按本机 `ENVIRONMENT.local.md` 设置 `$bbPython`、`$bbSim`
和 `$bbTd`，分别指向 Python 可执行文件、ModelSim bin 目录和 TD 安装根目录。

```powershell
$bbRunner = 'refactor/camera_raw_r1/src_fpga/simulation/blackbox_timing_20261107/run_blackbox.py'
& $bbPython $bbRunner stereo_cold_control --modelsim-bin $bbSim
& $bbPython $bbRunner real_hdr_pair_cycle_gate --modelsim-bin $bbSim
& $bbPython $bbRunner reset_pix --modelsim-bin $bbSim
& $bbPython $bbRunner reset_dfi --modelsim-bin $bbSim --td-root $bbTd
```

## 2026-11-07 结果

证据根目录为 `refactor/camera_raw_r1/tmp/blackbox_timing_20261107`。

| 套件 | 通过用例 | 关键观察 | `run.json` 所在目录 |
| --- | ---: | --- | --- |
| 冷态控制 | 6 | 两个异相时钟组合，PIX/DFI 分别推迟采纳或停钟，忙时 APP/DMA 和单域复位 | `stereo_cold_control/20261107T144400Z-94dfe4` |
| HDR 配对门 | 5 | FS/FE、旧 SHORT 与新 LONG 交叠、两上下文满、SOURCE 独立保持、排空、取消、外部超时及恢复 | `real_hdr_pair_cycle_gate/20261107T150023Z-f6df2a` |
| PIX builder 和 join | 2 | 分相与兼容模式，R3/F3、R4 准入、借用式共拍消费、末端反压与停钟复位 | `reset_pix/20261107T150414Z-340cb7` |
| DFI 元数据 | 2 | 早释放与 F3 对照，预留后反压，TD RAM 写读，复位撤销预留并恢复 | `reset_dfi/20261107T150611Z-3587f9` |

DFI 两档各记录 2 条 `vopt-2241` 与 4 条 `vopt-2697`，原警告保存在各档日志中。

## 保留的早期观察

- HDR `20261107T145048Z-b2a006` 包含两项早期合同差异。同拍真实 FE 和负事件
  以负结果为先，负 pair 后要经历 `i_stable` 低到高才能重新取得捕获资格。
  明确合同后保留了这两项验证及更早已呈现的正 SOURCE 不被撤回的检查。
- HDR `20261107T145250Z-3d7f4b` 的原断言把相距恰好 `0x80000000` 的两个组号
  当作必须拒绝，实测该输入输出了正 RAW。该点记录为 `OUT_OF_CONTRACT_OBSERVATION`。
  通过用例检查开放半范围内的前后顺序、32 位回卷和组号零。
- PIX `20261107T150006Z-39da62`、`20261107T150103Z-fb4cc5` 与
  `20261107T150210Z-eff567` 保留借用式握手诊断。join 的 SOURCE READY 与最终向量
  消费同拍，夹具从有效期间直接比较数据并在真正消费沿核对两路握手。
- DFI `20261107T150016Z-21c84e` 保留缺少 `PH1_LOGIC_DRAM` 的 elaboration 日志。
  `20261107T150422Z-d9a80e` 和 `20261107T150521Z-3e27eb` 保留 ring 尚未就绪时
  R4 无预留的端口观察。正式用例让 ring 在 R4 就绪，在 R5 前加反压。
