# JPEG 熵核局部面积对照

固定融合基线为 `eade457d7477110605f90eb5abc08420d8936642`。TD 6.2.3.210850，
PH1A90SEG324-2，PIX 8.000 ns。所有实验沿用实际生产的流式系数、银行存储和 RST 参数。
直连 READY 载体读回 SYN16、`area_prior`、`partition`、`add_map_lut_struct on`、
`min_control_set 2`。每个同口径对照用独立 AL 和 Runs，封印内 RTL、ROM、IP 源和公共
载体 SHA 一致，只替换熵核。原生脚本含 170 秒进程看门狗，终止清理预留 10 秒。
[方案与等价推导](AREA_PLAN.md)

## 面积与阶段

| 实验 | 首次外层进程 | 原始 gate Slice / LUT / FF / ERAM / DSP | 原生重开 Slice / LUT / FF / ERAM / DSP |
| --- | --- | --- | --- |
| 融合基线 | PASS，144.656 s | 1860 / 2288 / 1186 / 1 / 0 | 1844 / 2255 / 1186 / 1 / 0 |
| 72 位固定切片合并 | TIMEOUT，170.781 s，原生重开补读 PASS | 1802 / 2278 / 1186 / 1 / 0 | 1785 / 2245 / 1186 / 1 / 0 |
| AC 幅值常量阈值 | PASS，82.750 s | 2016 / 2617 / 1186 / 1 / 0 | 2011 / 2606 / 1186 / 1 / 0 |
| 64 位分级对齐 | PASS，148.890 s | 1741 / 2253 / 1186 / 1 / 0 | 1724 / 2219 / 1186 / 1 / 0 |

固定切片候选在首次进程终止前已写出 `.opt_gate.end.f`、gate DB、原始面积与时序、
重开面积和参数。进程停在重开后的定向计时初始化。保留原 TIMEOUT，单独通过同一
AL 和原生 `syn_1` 补读定向时序，原始工件按首跑 SHA 复核。补读脚本首次冷开
在导入 ChipWatcher 时发生 TD 访问异常，加载器件后正常重开。重开过程直接读取原检查点。
[基线回执](../../tmp/entropy_area_r2_20261110/syn16_a1/baseline/evidence.json)
· [固定切片首跑回执](../../tmp/entropy_area_r2_20261110/syn16_a1/fused_slice/evidence.json)
· [固定切片同 AL 补读](../../tmp/entropy_area_r2_20261110/syn16_a1/fused_slice/data_pins_device_td.log)
· [冷开异常日志](../../tmp/entropy_area_r2_20261110/syn16_a1/baseline/data_pins_td.log)
· [幅值阈值回执](../../tmp/entropy_area_r2_20261110/syn16_a1/mask/evidence.json)
· [分级对齐回执](../../tmp/entropy_area_r2_20261110/syn16_a1/coarse64/evidence.json)

## 8 ns 综合估计时序

| 重开目标路径，最差 setup 裕量 ns | 基线 | 固定切片 | 幅值阈值 | 分级对齐 |
| --- | ---: | ---: | ---: | ---: |
| count → reservoir D | +2.309 | +2.260 | +2.815 | +3.554 |
| READY → reservoir D | +4.611 | +3.928 | +3.404 | +3.723 |
| AC length → reservoir D | +3.364 | +3.344 | +3.406 | +3.597 |
| READY → state D | +4.915 | +4.806 | +4.761 | +4.798 |
| READY → state CE | +4.703 | +4.711 | +4.719 | +4.712 |
| AC category → code D | +5.864 | +5.879 | +5.890 | +5.893 |
| 全局 SWNS，原始与重开相同 | +2.309 | +2.260 | +1.959 | +2.365 |
| 全局 STNS，原始与重开相同 | 0.000 | 0.000 | 0.000 | 0.000 |
| 原生 STA coverage | 93.72% | 93.58% | 94.06% | 93.25% |

四组的 max endpoint 依次为 2382、2390、2382 和 2382，min endpoint 均为 0。
PIX 时钟各命中一个，储备、计数、AC 长度、注册 READY 分别为 64、7、6、1
个对象。状态 D/CE 各 11 个，AC 类别 8 个、AC 码字 D 52 个。载体只有 8 ns 时钟约束，
74 个输入和 55 个输出无端口延时。物理 hold、recovery、removal 需对应布局布线结果。
四臂规范 AL 副本均通过 9 项路径可移植性检查。
[基线报告](../../tmp/entropy_area_r2_20261110/syn16_a1/baseline/reopened.timing)
· [固定切片报告](../../tmp/entropy_area_r2_20261110/syn16_a1/fused_slice/reopened.timing)
· [幅值阈值报告](../../tmp/entropy_area_r2_20261110/syn16_a1/mask/reopened.timing)
· [分级对齐报告](../../tmp/entropy_area_r2_20261110/syn16_a1/coarse64/reopened.timing)

固定切片减 58/59 个原始/重开 Slice，READY 到储备 D 回退 0.683 ns。全局瓶颈仍为
计数到储备 D，11 级逻辑和 1.832 ns 单元延迟相同，估计连线延迟从 3.789 增至
3.838 ns。幅值阈值增加 156/167 个 Slice，整体 setup 回退 0.350 ns，该项排除。
固定切片直接熵黑盒 PASS，完整编码器在两次独立时限内未到全部终态，记为 BLOCKED。
[固定切片 READY 路径](../../tmp/entropy_area_r2_20261110/syn16_a1/fused_slice/ready_to_reservoir.timing)
· [候选不透明清单](../../tmp/entropy_area_r2_20261110/syn16_a1/blackbox_inputs/candidate01/compile.json)

分级对齐减 119/120 个原始/重开 Slice，原 count → reservoir D 路径增加 1.245 ns
估计裕量。全局瓶颈移至 AC Huffman ROM → reservoir D，8 级逻辑，估计裕量增加
0.056 ns。READY → reservoir D 余量回退 0.888 ns 至 +3.723 ns。载体由独立 READY
寄存器发射，生产 READY 还经过 formatter 核心、两槽队列占用和 abort 逻辑。物理验证时
需检查生产 READY 锥。
[分级对齐 READY 路径](../../tmp/entropy_area_r2_20261110/syn16_a1/coarse64/ready_to_reservoir.timing)
· [候选不透明清单](../../tmp/entropy_area_r2_20261110/syn16_a1/blackbox_inputs/candidate02/compile.json)

算式枚举检查了 3976 个合法储备计数、码长、排字节组合，包含 388 个必须同拍真排
才能容纳的组合。每组以 52 个单比特作为码字输入，合计 206752 个旧切片与新对齐
比较全部相等。对齐对输入的各位分别作用，等价关系适用于全部已知码字。幅值掩码的
16 个类别值也逐项相等。该检查覆盖纯数学表达式，公开接口握手和故障恢复由独立短测确认。

分级对齐的独立黑盒 **PASS**，包含直接熵 11 事务和完整编码器 4 事务。主扫描 4097 字节、
456 个 FF00、126 个 ZRL、10 个 RST。两臂都通过独立 JPEG oracle，输出字节和输入、输出、
SOURCE、RESULT、错误、DONE 等握手周期的原始 trace SHA 相同。完整编码器同一输入拆成
低高成功、负 SOURCE 后恢复两组，各在 56 秒单进程预算内。
[独立黑盒报告](BLACKBOX.md)
· [生产与候选 trace 对照](../../tmp/entropy_area_r2_blackbox_candidate02_split_a1/comparison.json)

## 含生产组合关系的 READY 返回载体

在熵核的 READY 端接入生产 formatter 状态、缓冲有效/末字节、两槽队列计数以及 encoder
中止状态与释放位。入口使用共同 8 ns 时钟的本地寄存字段，复现两份固定生产源中的 READY
比较、使能和 abort 优先级。载体用于判断这段逻辑给储备 D/CE 带来的相对变化。
[READY 载体](../../fpga_prj/verification_archive/experiments/entropy_area_r2_20261110/ready_return_probe.v)

首次 SYN16 基线在 170.625 秒触发进程看门狗，停在 Map Gate。原生目录只有 gate 开始
标记，比较所需的 gate DB、面积和重开报告未生成。再以生产共享综合同为 4 线程的设置
补测两臂，保留同一 170 秒看门狗与其余选项。以下均为 SYN4 对照。
[SYN16 首跑回执](../../tmp/entropy_area_r2_20261110/ready_syn16_a1/baseline/evidence.json)

| 实验 | 首次进程 | 原始 gate Slice / LUT / FF / ERAM / DSP | 原生重开 Slice / LUT / FF / ERAM / DSP |
| --- | --- | --- | --- |
| 融合基线 | PASS，107.172 s | 1983 / 2499 / 1196 / 1 / 0 | 1980 / 2492 / 1195 / 1 / 0 |
| 64 位分级对齐 | PASS，90.485 s | 1744 / 2244 / 1196 / 1 / 0 | 1738 / 2232 / 1195 / 1 / 0 |

| 起点 → reservoir，最差 setup 裕量 ns | 基线 D | 分级对齐 D | 差值 | 基线 CE | 分级对齐 CE |
| --- | ---: | ---: | ---: | --- | --- |
| formatter 状态 | +4.054 | +4.033 | −0.021 | 无路径 | 无路径 |
| buffer valid | +4.381 | +4.360 | −0.021 | 无路径 | 无路径 |
| buffer last | +4.054 | +4.033 | −0.021 | 无路径 | 无路径 |
| 两槽队列计数 | +4.054 | +4.033 | −0.021 | 无路径 | 无路径 |
| encoder 状态 | +4.106 | +3.967 | −0.139 | 无路径 | 无路径 |
| abort release | +4.106 | +3.967 | −0.139 | 无路径 | 无路径 |

两臂在储备 D/CE 各命中 64 个对象。formatter 和 encoder 状态各命中 3 个起点，其余
各 1 个，队列计数命中第 1 位。全局 setup 裕量原始 gate 与重开一致，基线 +2.356 ns，
候选 +2.384 ns，STNS 均 0，max 端点均 2382，min 端点均 0，coverage 93.92% →
93.28%。全局最差路径都由 Huffman ROM 到储备 D，均 8 级，最大扇出从 84 降到 48。
两份规范 AL 各通过 9 项路径检查。
[SYN4 基线回执](../../tmp/entropy_area_r2_20261110/ready_syn4_a1/baseline/evidence.json)
· [SYN4 候选回执](../../tmp/entropy_area_r2_20261110/ready_syn4_a1/coarse64/evidence.json)

生产返回关系的载体显示原始/重开少 239/242 Slice，最差返回裕量由 +4.054 变为
+3.967 ns。局部整体估计改善 0.028 ns，六类返回中最大单类回退 0.139 ns。候选源 SHA
与独立黑盒完全相同。该对照保留生产组合关系，起点仍是载体寄存器。生产设计实际
状态映射、时钟分布与布线由同源物理报告核对。

## 源身份与复现

| 实验 | 熵核 SHA-256 |
| --- | --- |
| 融合基线 | `baf534007844b006331b0f0095079fbcc1a698ad74ef6003454010c5592c9663` |
| 72 位固定切片合并 | `96bf7d45df9728406ac0bda256f9f53c597874948b059b021d9522a863a64700` |
| AC 幅值常量阈值 | `5ba4e3e7021db0f6620996cb54badd77b5e8a6362d9842eda0cdd2441940e74a` |
| 64 位分级对齐 | `c6f2e10a8208e500c98154d3e7647f2d4d11a8ed3e7df9fd1f94a09b488a77c7` |

```powershell
$areaPython = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
$areaExperiment = 'refactor/camera_fusion_r1/experiments/entropy_area_r2_20261110'
$areaTdRoot = '<TOOLS_ROOT>/TD_Release_2026.2.210.850'
& $areaPython -X utf8 -B "$areaExperiment/run_area.py" --name repro_a1 --variant baseline --td-root $areaTdRoot
& $areaPython -X utf8 -B "$areaExperiment/run_area.py" --name repro_a1 --variant fused_slice --td-root $areaTdRoot
& $areaPython -X utf8 -B "$areaExperiment/run_area.py" --name repro_a1 --variant mask --td-root $areaTdRoot
& $areaPython -X utf8 -B "$areaExperiment/run_area.py" --name repro_a1 --variant coarse64 --td-root $areaTdRoot
& $areaPython -X utf8 -B "$areaExperiment/run_area.py" --name repro_ready4 --variant baseline --ready-return --threads 4 --td-root $areaTdRoot
& $areaPython -X utf8 -B "$areaExperiment/run_area.py" --name repro_ready4 --variant coarse64 --ready-return --threads 4 --td-root $areaTdRoot
```

实际命令、输入与原件 SHA 位于每臂 `evidence.json`。补读由 `tools/run_td.py` 启动
`report_data_pins.tcl`，`--workdir` 指向对应臂，显式使用同一 TD 根。当前工作保持隔离。
对本地实验候选，整机综合、P&R、物理 STA、bitgen 和板级均为 **NOT_RUN**。
合入后复现时，脚本从固定提交读取熵基线。四个源快照以 `--prepare-only` 复现的 SHA
均与实测输入一致。复跑用的独立编译清单也采用此冻结基线。
[前三臂实测脚本快照](../../tmp/entropy_area_r2_20261110/syn16_a1/run_area_measured_v1.py)
· [64 位直连载体实测脚本快照](../../tmp/entropy_area_r2_20261110/syn16_a1/run_area_measured_v2.py)
· [返回载体 SYN4 实测脚本快照](../../tmp/entropy_area_r2_20261110/ready_syn4_a1/run_area_measured.py)
· [冻结基线复跑清单](../../tmp/entropy_area_r2_20261110/syn16_a1/blackbox_inputs/candidate02_eade_frozen/compile.json)
