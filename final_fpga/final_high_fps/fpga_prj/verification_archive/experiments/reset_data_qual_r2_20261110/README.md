# PIX 原始源复位与数据资格局部对照

融合固定源 `eade457d7477110605f90eb5abc08420d8936642` 的五个已放置种子都出现
PIX 下降沿释放到数据端点的 4 ns 半周期路径。最差裕量为 −2.024 至 −1.208 ns。
多个种子的真实数据终点属于 CAM0 RAW ingress，另一个种子为物理 SOURCE 错误数据。
[五个放置种子的路径与原件](../../docs/optimization_r2_20261110/PLACED_BASELINE.md)

## 变更与首次采样

候选用既有 `reset_release_sync_data(FALLING_RELEASE=1,DATA_RESET_COPIES=0)`
替换 `u_pixel_reset` 的单输出模块。原 F3 仍驱动状态、原始清理和 adapter 的复位，
清理使用原有 `FALLING_INPUT_RESET` 及同步提交。R3 取原三拍释放链末级，专门用于
`s_raw_source_ready`、`s_raw_ready` 和 `o_payload_enable` 的同域资格。零复制分支
为连续赋值，保持原释放寄存器、层次及约束对象。生产 SDC 无该实例特有的例外。

R3 到 F3 间 F3 仍保持 IDLE。三个资格需要 RUN 或 DRAIN，在这个窗口全部为低。
F3 仍在同一个下降沿释放，R4 仍是首次活动正缘。IDLE 下在 R4 才能采样上游静默并
发布 context 可用，后续合法命令和 owner 鉴权按原边沿推进。异步断言仍清空三拍链和
F3。实际借用、稳定性、故障恢复和停钟的独立验收见公开合同。
[公开验收范围](PUBLIC_CONTRACT.md) · [冻结输入](OPAQUE_SOURCES.json)

## 原生载体和覆盖

PH1A90SEG324-2，TD 6.2.3.210850，PIX 8 ns，上升／下降沿为 0／4 ns。SYN4、
`area_prior`、`partition`、`add_map_lut_struct on`、`min_control_set 2`。
两臂使用独立 AL/Runs，进程看门狗 170 秒，另预留 10 秒终止清理。

实际原始源、清理器、RGB adapter 和 CAM0 compact HD/UHD RAW ingress 进入映射。
载体复现生产 replay 首拍许可及裁剪接收关系，从小载体的寄存字段供给外部 READY、
选择和载荷。ISP 边界包含生产同结构的独立复位释放和核启用寄存器。三个资格各接到
一个正缘观察 D 端点。RAW ingress 的 128 个真实数据 D 和 CE 分开查找。F3 和 R3
也分别查询本地状态 D/CE、ASR 和另一阶段的复位入口。该载体使用独立的外围选择
寄存字段，并覆盖主 RAW 数据路径的逻辑形状。种子 4 的 SOURCE fence 端点及实际
扇出、复制、时钟树和布线需要完整工程报告。
[载体](ready_probe.v) · [实际原生脚本](synth.tcl)

## SYN4 实测

| 实验 | 终态／墙钟 | 原始 gate Slice／LUT／FF／ERAM／DSP | 重开 |
| --- | --- | --- | --- |
| 基线 | PASS，50.781 s | 1294／1467／1551／0／0 | 同原始 |
| 候选 | PASS，68.657 s | 1223／1316／1551／0／0 | 同原始 |

原始和重开整体最差 setup 由 +0.742 ns 变为 +1.593 ns，STNS 均 0。两臂各 2099 个
max 端点，min 端点为 0，原生 STA coverage 由 83.57% 变为 83.03%。PHY 级 hold、
recovery、removal 需要对应同源物理检查。两份规范 AL 各通过 8 项路径检查。
源清单及实际选项的 SHA 对照只有 `private_raw_isp_borrow4.v` 改变。
[基线回执](../../tmp/reset_data_qual_r2_20261110/pixel_syn4_a1/baseline/evidence.json)
· [候选回执](../../tmp/reset_data_qual_r2_20261110/pixel_syn4_a1/candidate/evidence.json)

| 源与端点，重开最差裕量 ns | 预算 | 基线 | 候选 |
| --- | ---: | ---: | ---: |
| F3 → 资格 D | 4 ns | +2.465 | 无路径 |
| R3 → 资格 D | 8 ns | 无路径 | +6.705 |
| F3 → RAW ingress D | 4 ns | +0.742 | 无路径 |
| R3 → RAW ingress D | 8 ns | 无路径 | +4.514 |
| F3／R3 → RAW ingress CE | 对应 4／8 ns | 均无路径 | 均无路径 |
| F3 → 私有 D 查询组 | 4 ns | +1.373，protocol fault D | +1.593，实际为 adapter CE |
| F3 → 私有 CE | 4 ns | +1.592 | +1.593 |
| R3 → 私有 D | 8 ns | 无路径 | +5.859 |
| R3 → 私有 CE | 8 ns | 无路径 | +5.700 |
| F3 → ASR recovery | 4 ns | +2.883 | +2.502 |
| R3 → F3 ASR recovery | 4 ns | +3.599 | +3.505 |

两臂 PIX、F3、R3 各命中 1 个，资格 D 命中 3 个，RAW ingress D／CE 各 128 个，
私有 CE 各 655 个，ASR 各 658 个。私有 D 集合 1045 → 1053，候选的 D 查询前六条
均以真实的 adapter CE 端点列出，按报告实际类型解读。候选三个资格观察点均测得
R3 正缘路径，裕量为 +6.705、+7.048、+7.048 ns。

RAW ingress 数据端点由 F3 的 `axis_data_reg[124].d` 转为 R3 的
`axis_data_reg[70].d`。估计数据延迟由 3.188 变为 3.416 ns，预算增加 4 ns。
剩余 F3 最差为本地 adapter raster group CE，+1.593 ns。两臂的 F3 recovery 最差均
在 ISP 模型释放链，原有 adapter recovery 已展开路径分别最小 +3.265 和 +3.266 ns。
[基线 F3 定向报告](../../tmp/reset_data_qual_r2_20261110/pixel_syn4_a1/baseline/f3_to_ingress_d.timing)
· [候选 R3 定向报告](../../tmp/reset_data_qual_r2_20261110/pixel_syn4_a1/candidate/r3_to_ingress_d.timing)
· [候选 F3 保留路径](../../tmp/reset_data_qual_r2_20261110/pixel_syn4_a1/candidate/f3_all.timing)

源 SHA-256 为 `782e4b6bd3f9845c61a1fe26308f763b50c68b6a461ff09401f5299c733fcf8b`
到 `7a1ef673db77bc3f5b961f717e208c9180aa742d0a6dd51c851ab8cf875228ba`。
小载体 opt_gate 和重开 **PASS**。独立功能验收另计。新候选的整机综合、P&R、
物理 STA、bitgen 和板级均为 **NOT_RUN**。

## 复现

```powershell
$pixelPython = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
$pixelExperiment = 'refactor/camera_fusion_r1/experiments/reset_data_qual_r2_20261110'
$pixelTd = '<TOOLS_ROOT>/TD_Release_2026.2.210.850'
& $pixelPython -X utf8 -B "$pixelExperiment/prepare_inputs.py"
& $pixelPython -X utf8 -B "$pixelExperiment/run_probe.py" --name repro_a1 --variant baseline --td-root $pixelTd
& $pixelPython -X utf8 -B "$pixelExperiment/run_probe.py" --name repro_a1 --variant candidate --td-root $pixelTd
```
