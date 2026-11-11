# RK 参数开放与时序优化：实施前评估

日期：2026-11-10。基线 `camera_raw_r2`，固定源码 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213`。
用户审阅隔离综合结果后，认为新增 123 Slice 代价过大，**明确不采纳黑电平开放**。
本轮执行范围改为：完善已经接通的 RK 参数入口和文档、独立黑盒短测，通过后做有证据的时序优化。
黑电平保持 50/50，比例和其他固定参数保持；本轮不发布服务器编译。下文保留未采纳方案及成本依据。

## 未采纳方案：开放两路黑电平

新增运行时可调项为 `hdr_black_long` 和 `hdr_black_short`，各自使用已有 10 位字段，范围 0..1023。
默认仍为 50/50；单目使用一对值，双目两眼共用这一对值，不增加分眼配置银行。
它们改变 FPGA HDR 合并前的 RAW10 减黑，不修改相机 I²C 黑电平、曝光时间、传感器 gain 或自动曝光。
大值可能把图像压黑或使运动判断的短曝光可靠区间消失，是数学边界效果，不是推荐成像配方；测试应覆盖这些边界。

建议同时保留两个既有 schema 的一致数值能力：schema2 支持单/双目，legacy schema1 仍受原单目能力限制。
不放开双目 legacy 配置，不更改寄存器地址、1024 位 extension、208/214 位私有传输、业务记录格式或默认配置。

实际不是只删除一条校验。需修改以下位置：

- `src_fpga/rtl/mono_config_scan_v2.v`：取消两路黑电平必须为 50 的限制；比例、资格位、保留位和时限校验保留。
- `src_fpga/rtl/mono_config_legacy_scan_v1.v`：同样开放黑电平；保留原 schema1 固定其他 preset、能力及错误优先级。
- `src_fpga/rtl/frame_config_preset_owner.v`：同步未受信任 legacy 入口的黑电平校验。
- `src_fpga/rtl/anlogic2026.v`：把实际 `u_native_source` 的两个常量 50 改接已经原子生效的 DFI extension 字段。
- 本候选 `rk_sdk/dual_host/camera_shared.py`：同步物理 profile 校验，不放松 ratio、qualification、delta/wait/age 约束。
- 本候选 SDK/使用说明：更新参数范围、默认值、旧 bit 的拒绝行为与实际 profile 信息，避免把通用 r3/lab catalog 当成此版本能力。

现有 `hdr_pair_native_source_service4` → `hdr_pair_pixel_reader` → `hdr_merge4` 已有对应输入和作业锁存。
合并在 DFI 时钟域完成；无需新增 CDC 位宽或重新设计数据流水，但常量传播曾移除的配置 FF/算术逻辑可能恢复。

## 已经接通、RK 可直接使用的其他参数

这些项目以完善现有入口、文档和范围提示为主，不重复增加 FPGA 寄存器。

| 字段 | 已有范围/含义 |
|---|---|
| `quality` | 1..100；默认 75 |
| `min_quality` | 1..quality；默认 1 |
| `flags.ADAPTIVE_QUALITY` | 0/1；默认关闭；开启必须有非零预算 |
| `frame_budget` | 0..16777216 字节；默认 0；是完成 JPEG 的质量反馈目标，不是硬截断长度，也不替代 DMA buffer 容量 |
| `restart_mcus` | 0..65535 MCU；默认 0，不插入 restart 标记 |
| `hdr_motion_base` / `hdr_motion_shift` | 0..16383 / 0..15；已有板调示例 64/3，并非强制默认 |
| `hdr_max_delta_ns` | 0..4294967295 ns；协议槽为 u64，本生产 owner 只接受高 32 位为 0 |
| `hdr_max_wait_ns` / `hdr_max_age_ns` | 1..4294967295 ns；是不同层的配对/存留策略，不是 RK 命令超时或 CSI 固定看门狗 |

继续使用已有 CFG PREPARE_EXT → READY → COMMIT → APPLIED，以及 ACTIVE/epoch 回读。
JPEG 在线配置由同一 owner 串行提交，接收线程继续归还 lease，切换下一项前检查每个参与眼的新 epoch 产品。
RAW 运行期间仍拒绝在线 CFG；冷态双目启动 Q75 等原 BOOT 约束保持。
开放后的 SDK 必须与支持该范围的新 bit 匹配。对旧 bit 在线试写非 50 值虽然会被 FPGA 在 PREPARE 拒绝、
ACTIVE 不变，但既有 `SharedStereoReceiver.apply()` 会把控制 owner 标为 faulted，不能用试写作为无害能力探测。

## 本轮不建议开放的项目及原因

| 项目 | 原因 |
|---|---|
| `hdr_ratio` | 当前固定 log2 编码 4，绑定真实 DOL2 3200/200 行曝光身份和 bank owner 检查；只放校验会导致物理配方与融合不一致 |
| `hdr_qualification` | 固定 15 是实际成员身份/资格要求，不是图像效果旋钮；下游也没有独立的放宽消费者 |
| 自定义去雾 LUT、去雾强度/透射率/暗通道参数 | 当前 DCP 消费器内部固定，旧 LUT 主机通路关闭；不是放开现有校验即可恢复 |
| 高斯核/σ、HE 强度、F22 阈值、车道 ROI/梯度 | schema2 未携带这些可变值，实际 preset/独立车道规则固定；需要增加传输/存储/运算资格，而不只是连线 |
| 相机曝光、gain、白平衡、Gamma、任意帧率/分辨率 | 没有本版 RK 运行时完整入口；需配方、重配置、身份/元数据和 CDC 联动 |

`dehaze_lut_generation=0/1` 均指向同一内建算法，不作为强弱档位。
不添加与本次问题无关的自动控制或诊断状态机。

## 黑电平小模块成本测算（已运行）

未修改生产 `hdr_merge4.v`，只在隔离载体改变两个外部端口的绑定。
TD 6.2.3.210850，PH1A90SEG324-2，4 线程，`area_prior`、`partition`、`min_control_set=2`、`add_map_lut_struct=on`。
三臂均为 ratio=4、KNEE=768/896、相同 scan 寄存器载体、可变 motion 参数和 7.502ns DFI 时钟。
每项墙钟上限 100s，实际 38.531/28.703/28.219s；原生 opt_gate 标记、同 AL 重开及报告均通过。

| 测量 | 固定 50 | 可变 8 位 | 可变 10 位 |
|---|---:|---:|---:|
| 原始 gate LUT / Slice | 662 / 610 | 794 / 713 | 817 / 735 |
| 重开 LUT / Slice | 630 / 600 | 762 / 701 | 785 / 723 |
| FF | 864 | 864 | 864 |
| ERAM / DSP | 0 / 8 | 0 / 8 | 0 / 8 |
| 减黑第一级最差 setup 估计 | +5.704ns | +5.154ns | +5.023ns |
| 整个载体 SWNS 估计 | +4.030ns | +4.030ns | +4.030ns |

完整 10 位较固定值的重开增量为 155 LUT、123 Slice；较 8 位仅多 23 LUT、22 Slice，建议保持完整 10 位。
**这只是叶模块/同载体的综合估计。** 整机还可能恢复作业配置寄存器及其扇出/连线，不得把 123 直接加到旧整机资源当作新整机结果。
载体不含实际 pad 时序模型，检查报告中的 34 input/32 output 无延迟约束是 scan 端口边界；
HWNS=0 的综合摘要不是 hold 签核。生产功能仿真、新整机综合/P&R/STA/板级均 NOT_RUN。

原始执行证据：[三臂清单及 SHA](../../../../tmp/parameter_timing_41cb_20261110/blacklevel_probe_01/RESULTS.json)，
[探针源码/有界 runner](../../../../tmp/parameter_timing_41cb_20261110/blacklevel_probe.py)。

## 多种子时序依据及计划

固定回传 Git `c1c311c03406d4ef09311fed9ade819e75a64449`，读取时状态快照年龄 49.6 秒。
48 个任务均绑定本源；已用既有 `client.receive` 校验分块/整文件 SHA，收集全部已上传的选定日志及报告。
48 份最终摘要中 25 个 setup 负、35 个 HWNS 负；HWNS 包含不同 min 检查，不能全部称为数据 hold。
当前 26 份完整展开 detail、29 份 final，共 30 个种子至少有一份路径报告；其余明确保留 PENDING。
种子 20 虽摘要 -0.729/-1.082ns，关键路径尚未回传，不凭其他种子推断其根因。

已确认的优化候选：

1. PIX 复位释放至普通控制/数据 CE 的半周期路径。保持异步复位保护，研究把正沿数据资格与负沿释放分离，保留相同首个合法采样沿。
2. CSI 事件 FIFO 到 RAW ingress 的 START/sideband/模式选择组合逻辑。以不改变 VALID/READY/身份/取消时序的控制简化或寄存投影为优先。
3. DFI HDR bank owner 的 BEGIN 身份、年龄和状态判定。只预登记原先已有阶段内稳定的比较结果，不提前承诺槽、跳过实时故障或减少判定。
4. PIX 短路径和真实 removal 分别处理：capture FIFO 写口、replay FIFO 读口、去雾元数据、capture/JPEG 复位端点。先核准映射别名/真实时钟网，必要时用精确的物理 min 裕量策略，不大范围切掉检查。

30 个有路径的种子中，18 个存在负数据 hold、15 个存在负 removal，8 个重叠；所示 recovery 最小均正。
现有 DDR 128 条 0.350ns min 约束在已回传例外报告中均命中，不能因为短路径失败就默认继续加大整条 DDR 延迟。
原生 `fix_hold high`、`hold_fix_iteration 10`、`post_route_opt ultra` 已启用，不能仅靠重复加种子或盲加迭代作为修复。
不下调 PIX/DFI/USER 时钟、不关闭 recovery/removal、不扩大 false path。setup 端点和跨种子分簇见
[setup 评估](../../../../tmp/parameter_timing_41cb_20261110/SETUP_ASSESSMENT.md)。更细的 min 检查端点、行号、
钟树和告警见[最小延迟与复位评估](../../../../tmp/parameter_timing_41cb_20261110/HOLD_ASSESSMENT.md)。
参数逐级追踪见[接口审计](../../../../tmp/parameter_timing_41cb_20261110/PARAMETER_ASSESSMENT.md)。

库存：[REPORT_INVENTORY](../../../../tmp/parameter_timing_41cb_20261110/REPORT_INVENTORY.json)。
本地小综合只能筛选修改和比较资源/逻辑级数，后续真实收敛仍需用户另行授权的新源服务器 P&R。

## 验证计划

- 新建无实现上下文的黑盒作者，只提供公开 IO/合法参数/数学合同/风险及不透明编译入口，禁读生产 RTL、旧 TB、内部信号。
- 参数：验证已有 JPEG/HDR 参数范围与原子生效；黑电平非 50 的请求仍拒绝。未采纳的可变黑电平不进入生产测试或功能声明。
- CFG：完整 32 字、schema1/2、单/双目、保留位/非法字段、stale session/epoch、已有在途帧后原子生效、ACTIVE 回读与下一事务恢复；不以单叶 PASS 代替合法端到端首事务。
- 时序修改：VALID/READY 受压保持、第一帧/末拍/取消/复位释放、承诺 burst 排空、帧身份不漂移。保留已有孤立 SHORT 不锁死、双眼预热和 HE/去雾/HDR 切换边界。
- 每次测试有墙钟与仿真 watchdog，优先小几何/短控制刺激，不跑多帧满幅长仿真。按风险补足后停止，不声称能在数字仿真中穷尽所有板级问题。
- 逐项小模块同设置 A/B，记录不成功候选；完成后本轮仍不提交服务器编译。

当前按用户确认执行“已有参数接口/文档/黑盒验证 → 时序优化”，不再等待或重复请求黑电平开放许可。
