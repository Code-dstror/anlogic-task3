# JPEG 字节打包器可达状态对照

固定融合源 `eade457d` 的打包器每拍最多接收一字节，每次输出最多一拍 16 字节。
之前的 [KEEP 阈值试验](../packer_keep_r2/README.md) 使用另一处切口。本次候选仅删除两处
`byte_count > 16` 分支及其减 16，KEEP、MAX 判定和所有可达分支保持原样。

## 归纳与故障路径审计

复位后计数为 0。假定某正缘之前的已复位计数在 0 到 16。

| 最高优先路径 | 当拍计数更新 |
| --- | --- |
| 同步复位 | 清零。 |
| 外部 abort | 已呈现且未接受的输出保持，其他情形清零。 |
| abort drain | 受压时保持，已承诺输出实际接受后清零。 |
| error drain | 受压时保持。接受输出时，原计数大于 16 的分支与归纳前提矛盾，实际清零。 |
| 丢弃超长帧 | 保持，直到输入 LAST 终结丢弃。 |
| 本拍溢出 | 尚未排出的已呈现输出保持，其他情形清零。超限字节不加入存储。 |
| 正常 | 出拍实际接受时先清零。仅当接受一个合法保留的输入时再加一。 |

正常追加若无输出握手，原计数不能等于 16。此时 full 为真，普通输入 READY
明确要求输出握手，且丢弃模式在追加条件之外。因此增加前的基数最多 15。
若计数为 16 且本拍同时进出，先清零再把一字节写入位置 0。没有追加时，计数
只保持或清零。每条转移都保持 0 到 16，且实际写入位置在 0 到 15。

两处大于 16 的分支对所有上述已复位可达状态均不可达。证明不使用 MAX 的具体
数值或 LAST 出现的位置。保留受压的 DATA/KEEP/LAST、溢出脉冲、错误排空和
复位优先级。功能测试按 [公开合同](PUBLIC_CONTRACT.md) 独立核对。

普通溢出分支发生在真实输入握手上。当时 READY 排除了已有终止或排空状态，
若有满拍输出则同拍接受该输出。因此已复位、正常二值接口不会因这条溢出分支
建立新的 error drain。上表仍对该保护分支的保持和清零分别核过计数范围。

## 同设置局部综合

TD 6.2.3.210850，PH1A90SEG324-2，PIX 8 ns，SYN4、`area_prior`、
`partition`、`min_control_set 2`、`add_map_lut_struct on`。两臂使用生产
`MAX_PAYLOAD_BYTES=16777216`，保留全部 AXIS 输出字节的可观察性，独立 AL/Runs。
每臂进程看门狗 80 秒，另预留 10 秒终止清理。

| 项目 | 基线 | 候选 |
| --- | ---: | ---: |
| 终态／墙钟 | PASS／42.219 s | PASS／24.969 s |
| 原始 gate 和原生重开 Slice | 117 | 117 |
| 原始 gate 和原生重开 LUT | 122 | 104 |
| FF／ERAM／DSP | 204／0／0 | 204／0／0 |
| 输入寄存器到数据 D setup 裕量 ns | +7.330 | +7.330 |
| 输入寄存器到计数 D setup 裕量 ns | +5.053 | +5.161 |
| 计数寄存器到计数 D setup 裕量 ns | +5.144 | +5.506 |
| 输入寄存器到数据 CE setup 裕量 ns | +5.904 | +5.547 |
| 计数寄存器到数据 CE setup 裕量 ns | +6.372 | +5.704 |
| 全局 setup 裕量 ns | +5.036 | +5.141 |

纯字节输入到数据 D 与全部输入到数据 D 的最差值相同。计数到数据 D 查询两臂均无
直接路径。输入、纯字节、计数、数据 D、计数 D 分别匹配 13、8、5、128、5 个对象。
两臂 STNS 均 0，max 端点均 505，min 端点为 0，覆盖率 98.06% → 97.94%。
同 AL 补读命中 128 个数据 CE。候选减少 18 个逻辑 LUT，Slice 为 117。
全局估计改善 0.105 ns，输入和计数到数据 CE 的估计分别回退 0.357 和 0.668 ns。
Slice 保持同一数值且局部 CE 路径退步，建议保留为本轮实验。
[原始基线](../../tmp/packer_reachable_r4_20261110/packer_syn4_a1/baseline/evidence.json)
· [原始候选](../../tmp/packer_reachable_r4_20261110/packer_syn4_a1/candidate/evidence.json)
· [候选数据 CE 原件](../../tmp/packer_reachable_r4_20261110/packer_syn4_a1/candidate/count_to_data_ce.timing)

基线 SHA-256 为 `2a39a241c6ed1c722a4ccfaa96287789898ae6da54736614b7064e697a95446f`，
候选为 `8b27772b4455d2107a2fbdfeb0cac9a17ce853f003ca469e64f638094cb59354`。
独立黑盒四组 **PASS**。基线与候选在同一 MAX 的事件统计相同。
MAX 17 每臂 518 拍、324 字节输入和 35 个输出拍，MAX 31 每臂 1065 拍、737 字节输入
和 63 个输出拍。两档均覆盖尾 KEEP 1–16、两个溢出脉冲、两个中止排空和随后合法恢复。
整机综合、P&R、物理 STA、bitgen 和板级为 **NOT_RUN**。
[独立短测报告](../../docs/optimization_r2_20261110/PACKER_BLACKBOX.md)
· [原始黑盒回执](../../tmp/packer_r4_blackbox_20261110_223146_747874/result.json)

```powershell
$packPython = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
$packExp = 'refactor/camera_fusion_r1/experiments/packer_reachable_r4_20261110'
$packTd = '<TOOLS_ROOT>/TD_Release_2026.2.210.850'
& $packPython -X utf8 -B "$packExp/run_probe.py" --name repro_a1 --variant baseline --td-root $packTd
& $packPython -X utf8 -B "$packExp/run_probe.py" --name repro_a1 --variant candidate --td-root $packTd
```
