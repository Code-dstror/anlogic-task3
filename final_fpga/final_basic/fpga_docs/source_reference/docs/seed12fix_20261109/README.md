# seed12 彩色切HDR启动死锁修复

本轮针对 `camera_raw_r2 · 4a08ae35 / seed12` 的最新现场。已按用户最新要求停在本地修复与验证，**未推送服务器编译任务**；原32种子安排本轮不执行。没有继续优化面积、提帧率或改图像算法。

## 现场与可复现原因

[原件核验](EVIDENCE.md)确认HE→去雾→彩色六轮18笔请求均成功，第19笔首次彩色→HDR超时。配置whole ACK已到，PIX与DFI target epoch19，公开applied仍18。CAM0完成预热，CAM1表已写完却停在warmup0；两眼新RAW准入没有增长。较早“两条路径均正常”的口头反馈已被更正，不作为HDR通过证据。

本次找到了与这一冻结状态一致、可从真实数字接收链复现的缺陷：

1. MIPI接收发布恢复时可能先看到VC1 SHORT。新cohort尚无可见LONG，真实parser给该SHORT标记group0、common-cycle无效；这属于未配对的启动帧，不能生成产品。
2. 旧配对门却把所有未匹配SHORT帧首都留在FIFO头等待未来LONG。group0永远不可能与随后从1开始的LONG组匹配，也不进入非零组skip规则，因此把合法后继SHORT一起堵住。
3. CAM1无法取得连续好pair；双目正常保护要求两眼稳定，CAM0也不能开始真正RAW输出，于是CFG继续等真实新帧。这不是已完成配方写入就可以提前APPLIED的理由。

现场没有逐字CSI/FIFO队首trace，故不把“第一可见VC一定为SHORT”写成板上实测事实。相同板源在独立模型中能重现相同的CAM0稳定、CAM1预热未完成、无产品签名；本版消除这一确定的RTL活性缺陷，实际板卡仍待复测。

## 最小修改

生产RTL仅改 `real_hdr_pair_cycle_gate.v` 的future SHORT等待资格：只有**成员身份可信、common-cycle可信且group非零**的未匹配SHORT才等待对应LONG。没有匹配上下文的无效孤立SHORT允许排空，不生成RAW、SOURCE或好pair；已经匹配有效上下文的坏FS仍按原失败规则处理。

保留合法future SHORT的等待和持有、两眼稳定门槛、八个连续好pair、SOURCE身份与反压、负终态恢复、STOP/旧承诺排空，以及上一轮两个配置活性修复。没有改传感器寄存器表、warmup门槛、CRC/身份判断、序号或HDR数值策略。不会把丢掉的预热帧重新编号成有效产品。

没有新增寄存器、FIFO、ERAM、DSP或业务流水；增加的是已有SHORT身份/非零判断对等待条件的组合资格。源/IP/约束/时钟/复位策略均保留，实际Slice和时序仍只能由后续综合/P&R确认。旧seed12只有1ps hold余量，不能因改动小就继承其物理资格。

## 独立黑盒证据

测试作者均是新建、无实现上下文的子代理，只收到公开IO、合法profile、外部合同和不透明源清单；没有读取生产RTL/旧TB/厂商模型内部或探测内部状态。两个最终A/B各使用同一TB，仅gate不同。

| 测试 | 固定旧源 | 候选 |
|---|---|---|
| [配对门RTL短测](../../src_fpga/simulation/blackbox_hdr_startup_20261109/leaf_README.md) | 组号0 SHORT保持64个有效时钟仍不接受，705ns触发失败 | 13场景PASS，2126ns模拟、约2.45s墙钟；包含孤立无效FS、正常future等待、真实RAW与独立SOURCE、坏匹配组后重新预热、STOP、停钟相位异步复位后新cohort |
| [两眼真实数字接收及预热链](../../src_fpga/simulation/blackbox_hdr_startup_20261109/chain_README.md) | 两眼均139笔真实I²C写完，随后各8个完整pair；等三个deadline后GOOD8/0、BAD0/6、stable01，始终没有产品 | 同一刺激GOOD8/8、stable11，预热期间无产品；首组SOURCE为CAM0 9/9、CAM1 9/10，下一组10/10及10/11；CAM1 SHORT终态反压32拍保持；最终GOOD10/10、quiet11、无sticky fault |

链路使用实际配置器、CSI WORD parser、crop、两眼各自TD成员FIFO、pair gate和跨域反馈。两次各约4.58s墙钟，模拟1.846/1.857ms；小几何4×1，没有满幅长仿真。它验证从对齐WORD到真实RAW/SOURCE终态，**不验证物理眼图/MCLK切换、DDR、CFG BAR到PCIe、满幅帧率或板级效果**。配对门短测也是RTL功能仿真，不是综合后网表/SDF时序仿真。

原始失败保留：叶测试最初漏了坏pair后sensor需撤销stable并重新预热的恢复前置；链路最初漏冻结SDR表编译依赖、以及carrier本域三拍复位释放的首合法START边界。补齐公开合同后重跑同刺激A/B；未修改正确oracle迎合DUT，也没有用增加超时宣布修复。

精确命令、结果、源/TB/模型哈希、native日志见 [VALIDATION.json](VALIDATION.json)。全新checkout先执行测试目录的 `restore_baseline.py`，从固定4a08ae35恢复不透明基线，不依赖tmp保存唯一源码。

## 工程检查与本轮状态

指定本机TD2026.2完成原生read_design、同AL重开、共享模块/复位/DDR守卫对象层次检查。输入封印维持405项生产输入和158项冻结IP，258条工程依赖路径闭包检查通过。整个过程没有本机长综合或布局布线。

功能仿真PASS；原生展开/重开PASS；新综合、P&R、STA、bitgen及板级均NOT_RUN。按最新用户指令，不创建或发布本轮服务器请求。后续恢复编译时须使用本次明确源提交，不能复用4a08ae35旧综合网表。

## 下一次板测重点

- 复用匹配的RK应用、N2/CFG协议、HDR配方和原超时；UART仍为DJ/v3，解析器及其所有字段不变。
- 先按现场同顺序HE→去雾→彩色六轮，再首次进入HDR；另以新的冷轮直接彩色→HDR及重复HDR→SDR→HDR检查启动相位差。每笔等真实APPLIED和两眼新epoch画面后再切下一笔。
- 核对两眼SYS配方写完后的phase6→7、warmup进度和stable；随后四路capture_admit增长、PIX cfg_applied_epoch与USER ACTIVE推进、两眼合格产品到达。允许预热期不配对帧被丢弃，但真实SOURCE序号不得重编。
- 新bit仍卡住时保留完整UART/CSR、请求时序和实际帧记录，不以PHY_READY=1替代有效HDR帧或眼图训练完成。不要追加热重开或放宽稳定门槛。
- 本轮没有新的HDR实测FPS；之前波动和持续HDR30目标仍须同窗SOURCE—job—产品—退休对账，不以小几何通过宣称满幅达标。
