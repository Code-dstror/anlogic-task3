# 8258220f 板测：HDR/HE 切去雾卡死修复

本轮从实际板测的 `camera_raw_r2 · 8258220f` 修复两种已复现的配置活性缺陷。只改本工程，不合入旁路 camera_rate/HDR 色调试验，不继续资源优化或增加图像模式。去雾数学模块保持原字节，RK 业务 BAR、CFG、AJPG、ARAW 格式不变。UART 观察页升 DJ/v3。

修复源码 `4a08ae35391e7b7ea6767260d7d1b4b182ef4bb9` 已推送。请求 `camera-r2-dehaze-fieldfix-20261109-syn16-48s4t` 已获服务器 **ACCEPTED**：一次16线程共享综合、48个物理种子各4线程。综合job为 `manual-camera-r2-dehaze-fieldfix-20261109-syn16-48s4t-62603ee8e51a0817-syn`；新阶段结果待回传，完整回执见下方派发记录。

## 现场与结论

[完整证据复核](EVIDENCE.md)区分两个独立冷轮，不把重复打包资料当多次现场。HDR→去雾停在旧 capture/DFI epoch2；HE→去雾已经有合法 CAM1 epoch17 AJPG 到达 RK，但对外 ACTIVE 停在16。后者 SDK 等 APPLIED，持有两条未确认记录后停止补充 N2 接收槽，后继流水因此背压。后续停产不能直接证明去雾计算本身死锁。

以下是由原版RTL在公开端口条件下复现、与现场边界一致的机制。现场没有逐周期 PREPARE/READY/COMMIT trace，因此不声称已唯一排除所有其他触发原因。

| 问题 | 原因与最小修复 | 保留的保护 |
|---|---|---|
| HDR旧配置退场没有ACK | 停新准入后仍到来的弃组 token 会维护 skip watermark。旧 `o_quiet` 把这种无RAW/SOURCE所有权的维护也算忙，短暂撤销已借出的 capture drain 资格，触发粘滞故障。现quiet仅按活跃组和持有SOURCE定义；弃组过滤数据通路不变 | 旧组、未取SOURCE、真实enqueue/consume计数、DFI写响应债务仍阻止CONFIG ACK；不清故障或伪造计数 |
| HE目标数据已产生而公开配置不发布 | 旧PIX引擎在whole ACK后再次要求 `pipeline_idle && frame_accept` 同拍。双目CAM1/新作业可以已经占有处理器，使真实CAM0新配置SOF不断错过APPLIED | 只在本工程强制远端whole-ACK的service关闭二次idle要求；独立engine默认仍要求idle。PREPARE旧工作排空、完整ACK身份校验、真实CAM0边界、故障优先和USER原子ACTIVE发布均保留 |
| 现场难分清排空、ACK还是APPLIED等待 | DJ/v3在原两域224bit页中用32bit配置已发布epoch和16bit状态/quiet标志替代两个FS计数器及保留位 | UART长度/速率/CRC/双域快照不变，无返回主系统控制的输出，无新增CDC缓存；DFI job/拒收/超时/负FINISH及四路capture_admit仍保留 |

TOP对stored SDR使用真实RAW入口frame_accept，单目实时SDR仍用实际接收SOF，HDR仍要求真实主眼LONG及可信/已准入元数据。冷态观察边界仍要求原全静默和合法传感器资格，未把sensor offer、capture时间或新epoch数字本身当作APPLIED。

## 独立黑盒与复现

新建不继承实现讨论的测试作者；只提供公开端口/合法profile/外部行为合同和不透明源清单。测试不读取RTL、旧TB、厂商模型实现或内部信号。所有场景有墙钟和仿真watchdog，没有多帧满幅长仿真。

| 验证组 | 原版与修复版结果 | 范围 |
|---|---|---|
| [CFG真实BAR/FIFO链](../../src_fpga/simulation/blackbox_cfg_transition_20261109/cfg_README.md) | 原版：HE首事务正常；去雾whole ACK后4个CAM0首帧事件全部错过，STATUS=0x11/旧epoch。候选5场全部PASS；首个序号0x480正确APPLIED | PREPARE等旧债、两轮HE/去雾/SDR、HDR退场、全32字ACTIVE、错/负ACK、首帧同拍故障、停USER钟双复位后新合法事务；capture/DFI为公开BFM |
| [HDR门＋真实paired drain](../../src_fpga/simulation/blackbox_cfg_transition_20261109/hdr_cfg_drain_README.md) | 原版：弃组开始35ns后source drain fault；债务清后仍无ACK。候选：持续每眼768个拒收token、quiet不撤销、ACK受压7周期保持，HDR重入epoch3两眼SOURCE退休 | 实际受控FIFO、两成员enqueue/consume及写债、held SOURCE和分支复位；非完整传感器/DDR仿真 |
| 去雾叶流活性 | 9个256×128完整栅格、2次部分栅格中止通过，3.563s墙钟；本轮未改该叶 | 禁用/启用、历史隔离、错身份/晚SOURCE、负终态+clear、停钟复位后首帧；未做有历史像素数值/画质与生产外部暗统计资格 |
| UART与解码 | 9轮实际8N1 OB29+DJ68、CRC、8个阶段通过；旧DJ/v1/v2及新v3手工帧、分片和坏CRC恢复通过，2.656s墙钟 | 加速串行参数；停PIX与业务复位有效位分开，采集target17/applied16可区分；非板级串口测试 |

CFG每场约5–7s、最长84.085us模拟；HDR候选18.710us模拟、约4.6s墙钟。原始FAIL保留：CFG前置HOST_CAPABILITIES遗漏/ModelSim退出码处理、HDR夹具在首FS前误将ingress置忙均已分类为合同或夹具问题；它们不替代最终同刺激A/B反例。

精确命令、输入SHA和结果路径统一见 [VALIDATION.json](VALIDATION.json)。全新checkout先执行测试目录的 `restore_baseline.py` 从固定8258220f恢复三份不透明基线，脚本不会覆盖不同内容；不依赖tmp作为唯一源码。

## 原生检查与资源边界

新版TD原生read_design、同AL重开和层次/共享IP检查用于工程集成；不能代替功能或布线资格。首次read_design导出DB后退出报PRJ-8806，原日志保留；同源码重试原生流程成功。首次层次脚本仍期望DJ/v2而失败，更新为实际v3并新增远端frame发布参数检查后复验，结果见验证记录。

RTL没有引入新的ERAM/DSP模块、图像缓冲或业务流水。quiet和APPLIED改动删去不正确资格条件；诊断复用原快照，删除32bit物理FS计数。实际映射资源和时序只有新服务器结果能确认，本轮未跑本机整机综合/P&R。时钟、SDC、DDR min guard、复位策略及受控IP字节保持；旧seed20的时序不能签核本轮新bit。

## 下一轮板测与仍未解决事项

使用[DJ/v3字段说明](UART_FIELD_V3.md)和本工程解码器。先以同一已匹配RK控制程序重复两轮HE→去雾和HDR→去雾，保持原超时，不自动热重试；记录PREPARE/READY/COMMIT/APPLIED、全32字ACTIVE、首CAM0新epoch序号与两眼实际产品。
若继续卡住，用新页区分WAIT_IDLE的三个quiet门、WAIT_FRAME是否收到whole ACK、PIX已发布epoch与USER ACTIVE是否长期不一致。短脉冲未采到不等于没发生，仍保留原始UART与真实记录。

HDR短窗的25/25以及30/20反向不对称在本轮证据中仍存在。当前聚合BEGIN拒收不能唯一定位容量、调度或下游背压原因；**本轮不宣称HDR30帧或长期所有模式达标**。保留分眼准入/job/拒收观测，待新bit正常切模后按同窗SOURCE—产品—退休继续定位，不能为了指标修改序号或计数口径。业务功能目标不削减。

提交任务采用一次16线程共享综合，复用其检查点的48个物理种子各4线程，全流程至bitgen。当前源码身份、实际派发及回执见 [SUBMISSION.json](SUBMISSION.json)；新综合、P&R、STA、bitgen和板级资格均需独立报告。
