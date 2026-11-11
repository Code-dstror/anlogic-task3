# DFI ring 复位资格局部证据

候选保留 ring 的 F3 所有权复位，以既有 R3 驱动 START、DATA、RESULT 三个 READY
和写静默。全局记录静默、已承诺 AXI、READY 描述符、读完成、QUERY 与 RETIRE 继续
使用原资格。零复制参数直接复用原末级寄存器。生产包装候选从固定 `eade457d`
生成，局部原生测量使用含同一释放接线的公开边界和实际 ring。
[消费者分类、R4 与跨域证明](PLAN.md) · [候选及模型清单](OPAQUE_SOURCES.json)

## 源和独立功能证据

| 固定文件 | 基线 SHA-256 | 候选 SHA-256 |
| --- | --- | --- |
| `jpeg_frame_ring.v` | `5c45615f818173b96a25a1a184691f8ffcdd3ef2155fa54581804b6e567153e1` | `eed3c6b1955a465ac113d7492134d298fe9a62c7727d8c88b4c64c5379248b5b` |
| `ddr3_jpeg_store.v` | `e60fe999ce02fa4720efcc032d9de468377291c5b58fc051ee6d2f396fd09c25` | `cc9ec6b40702c0d35978c5041b7f002a799f28cc8bdbc498d2a33fbf9c547310` |

独立黑盒两臂 **PASS**。1411 个 DFI 采样与事务轨迹逐项相同，SHA-256 为
`0734779a59b3861133f4a1ea49603e55a81d608ec4941c43fa1734e22b768dd2`。
每臂 10 START、10 RESULT、26 AW/B、285 DATA/W、24 AR 和 278 R/PAYLOAD。
9 个成功 writer ACK、1 个失败 ACK、8 次合法 RETIRE，覆盖六个槽和两个 generation 2
的复用，三次冷／停钟释放均在 R4 首次 START。测试使用稀疏 DDR BFM，SAFE 由下游
前提驱动，板级 host transport 另计。
[独立短测报告](../../docs/optimization_r2_20261110/RING_RESET_BLACKBOX.md)
· [实际仿真回执](../../tmp/ring_reset_r3_blackbox_20261110_01/run.json)

## 完整依赖下的原生 gate 与重开

PH1A90SEG324-2，TD 6.2.3.210850，SYN4，`area_prior`、`partition`、
`add_map_lut_struct on`、`min_control_set 2` 均原生读回。DFI 周期 7.502 ns，
波形 0.229/3.980 ns，辅助 PIX 8 ns。实际 ring、生产 egress 流式 16 KiB 扩展、FIFO
fence 和原字节 147×512 FIFO 均进入映射。写静默旁路使用采样的原 HDR release
组合关系。A/B 输入仅差 ring 叶和该边界的释放接线，两份规范 AL 均通过 17 项路径检查。

| 实验 | 终态／墙钟 | 原始 gate Slice／LUT／FF／ERAM／DSP | 重开 Slice／LUT／FF／ERAM／DSP |
| --- | --- | --- | --- |
| 基线 | PASS，68.547 s | 2778／3459／3188／5／0 | 2774／3448／3188／5／0 |
| 候选 | PASS，67.688 s | 2752／3426／3188／5／0 | 2747／3415／3188／5／0 |

a4 两臂原生 `.opt_gate.end.f`、gate DB、同 AL 重开终标及面积/时序均齐全，
wrapper 错误数为 0。分析、展开和层次面积显示冻结 FIFO 及其 core 实际编译，
FIFO 本体占 4 ERAM，扩展 1 ERAM。日志读入原 `read_sdc -ip`，两条 Gray 指针方向
的 datapath-only 路径以 7.202 ns 预算单列。
[a4 基线回执](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a4/baseline/evidence.json)
· [a4 候选回执](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a4/candidate/evidence.json)

## a4 分路径时序

重开最差裕量单位为 ns。F3 到正缘预算 3.751 ns，R3 到下一正缘预算 7.502 ns。

| 端点 | 基线 F3 | 候选 F3 | 候选 R3 |
| --- | ---: | ---: | ---: |
| egress token READY 的采样 D | +1.217 | 无路径 | +5.459 |
| 真实 FIFO 读计数/读头寄存器 D，全部支路 | +0.536 | +1.213 | +5.443 |
| 写静默采样 D | +2.487 | 无路径 | +6.145 |
| HDR release/clear 关系采样 D | +2.188 | 无路径 | +5.205 |
| ring slot D | +0.513 | +0.990 | 无路径 |
| ring slot CE | +0.539 | +0.994 | +4.390 |
| ring ASR recovery | +2.944 | +2.944 | R3 到 F3 为 +3.286 |

基线 R3 到 F3 recovery 为 +3.350，预算同为 3.751 ns。两臂均命中 F3、R3 各 1，
token D 和 quiet D 各 1、HDR D 两个、真实 FIFO 读计数/读头 3 个、slot CE 18 个、
ASR 1361 个。slot D 为 50 → 39。DFI 同域整体 SWNS 为 +0.513 → +0.990，
STNS 为 0，max 端点均 6690。两臂报告的 min 端点均为 0。双时钟载体还报告未设
整机 CDC 例外的跨域组。DFI→PIX 有 6 个端点，最差 −0.913 → −0.914 ns，涉及
egress 释放到 FIFO 异步 reset、对端 release、marker ACK 和故障同步首级。
PIX→DFI 有 2 个端点，最差 −0.400 → −0.407 ns，涉及反向 release/故障首级。
这些与 Gray 指针守护及 DFI 本域业务 setup 分别记录。
原始与重开报告一致，覆盖率 91.21% → 91.14%。

同 DB 补读证实基线 F3 经 `u_egress/o_token_ready` 到真实 FIFO
`read_count[0].d` 的 +0.536 ns 路径。候选该限定 F3 路径为空。候选 R3 到 FIFO
读计数的实际展开含 egress `last_seen` 与 token 选择组合，映射已经合并一部分
选择逻辑，按独立 READY 净名限定的 R3 查询为空。候选 F3 到 FIFO 的剩余展开经
`ack_toggle` 的 marker 逻辑，对应保留的 `record_quiet` fence 支路。

FIFO 读缓冲的 160 个 `.cea/.ceb` 引脚已匹配，门级计时器拒绝其为有效端点。
90 个对应 cell 的补查也没有有效时序路径。上述 FIFO 数值均取真实读计数寄存器
和 egress READY，RAM CE 证据仍需实际物理阶段。
[基线限定 egress 路径](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a4/baseline/f3_through_egress_ready_to_fifo_data.timing)
· [候选 R3 FIFO 路径](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a4/candidate/r3_to_fifo_data.timing)
· [候选 F3 保留路径](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a4/candidate/f3_to_fifo_data.timing)
· [候选补读日志](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a4/candidate/fifo_branch_td.log)

## 受控 FIFO 文件闭包

最初 a1 的两个 include 设置被覆盖，a2 缺少 16 KiB 稀疏校验依赖。两次都止于分析或
展开。a3 复制清单漏了原组件 XML 声明的 `camera_packet_fifo_147x512.tcl`。两臂的
gate DB 和重开报告虽齐全，TD 仍报 `PRJ-7002` 生成文件 `D` 缺失，外层记 **FAIL**。
该 Tcl 的
SHA-256 为 `6b05393e65201073741f1a8cb96f985b47f22184484f6b8e88e94980f6de4979`。
补入这份原字节后，递归检查三个 package XML 的文件引用。Tcl 由原 XML 管理，
包含 FIFO 两条 Gray 指针 datapath-only 延迟约束。新的最小原生 read_design
和同 AL 冷重开均通过，wrapper 错误数为 0。随后以完整闭包重跑同设置 a4。
[a1 首次失败](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a1/baseline/evidence.json)
· [a2 第二次失败](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a2/baseline/evidence.json)
· [a3 基线原件](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a3/baseline/evidence.json)
· [a3 候选原件](../../tmp/ring_data_qual_r3_20261110/dfi_syn4_a3/candidate/evidence.json)
· [依赖闭包原生检查](../../tmp/ring_data_qual_r3_20261110/dfi_closure_a1/baseline/closure_td.log)

## 复现

```powershell
$ringPython = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
$ringExp = 'refactor/camera_fusion_r1/experiments/ring_data_qual_r3_20261110'
$ringTd = '<TOOLS_ROOT>/TD_Release_2026.2.210.850'
& $ringPython -X utf8 -B "$ringExp/prepare_ring.py" --td-root $ringTd
& $ringPython -X utf8 -B "$ringExp/run_probe.py" --name repro_a1 --variant baseline --td-root $ringTd
& $ringPython -X utf8 -B "$ringExp/run_probe.py" --name repro_a1 --variant candidate --td-root $ringTd
```

两臂使用隔离原生项目与 170 秒进程看门狗，另预留 10 秒终止清理。补读用
`tools/run_td.py`、同一 TD 根和 `report_fifo_paths.tcl`，`--workdir` 指向相应臂。
本候选整机综合、P&R、物理 STA、bitgen 和板级均为 **NOT_RUN**。
