# 2026-11-09：基于5bd布线报告的时序修正

源码已提交并推送 `8258220fdb54d8db8d9f9fd8b77b8185f0c7546d`。
32种子请求 `camera-raw-r2-timing-20261109-syn16-32s4t` 已发布且服务器回执 **ACCEPTED**：
一次16线程共享综合，复用结果的32个物理种子各4线程full。命令分支提交
`4499405b2cb5b628462cc40a3b9e8294d00144fb`，综合job后缀`5347d76f3e94e0f0-syn`。
此前能力快照过期拒绝记录保留；快照实际刷新后以同一ID/源码/参数重试，未绕过检查、未重复任务。
阶段结果和物理时序仍待回传，见 [派发记录](SUBMISSION.json)。

本轮只针对时序，不继续RAW打包等资源实验。在独立camera_raw_r2上保留昨晚已验证改动。
来源、12套完整报告和其余缺项见 [5bd基线](BASELINE_5BD.md)。旧源46个阶段DONE不等于46套完整报告；
本次固定回传提交只对已完整的12套作逐路径结论。5bd raw gate为63903/64320 Slice（99.35%），成本必须受控。

## 采用的修改

| 违例类型/原路径 | 修正与验证依据 |
|---|---|
| DFI同沿，配置schema/mode解码→高扇出调度/ticket，最差−0.702ns | 在原成功CFG commit沿登记1bit `o_active_hdr`，与ACTIVE tuple/session/epoch同时更新；失败、忙和复位语义保持，不用提前变动的pending mode。[公开合同与分析](DFI_CONFIG_SETUP.md) |
| DFI下降沿ASR→AXI/RAW数据资格，仅3.751ns预算 | 三个实际写仲裁器、ARAW formatter使用已有R3数据资格，状态ASR继续F3释放，首合法采样仍R4。真实小映射32条D/CE路径从半周期+2.243ns变成整周期+6.046ns；28条F3→ASR recovery保留。未增加同步器级数、业务流水或数据缓存。 |
| PIX bootstrap/准入和token→HDR SOURCE错误/有效资格 | 已匹配旧组的事件和SOURCE先按注册身份处理，再做新组分配。同拍许可、FAULT、时间戳仍按真实FS；旧SHORT可与新LONG错相，已发布SOURCE不撤回，负水印语义保留。[实验](../../experiments/timing_pix_20261109/README.md) |
| JPEG ingress本域removal，最差−0.046ns | 仅移除在VALID前由实际事务必定写入的数据寄存器ASR：START与冻结元数据/RESULT、START先清零的字节计数。active/context_sent/扩展所有权、索引、fault和capture_id控制复位保持。停钟复位仍立即撤回VALID，下一帧不得带入旧值。 |

固定时钟、DDR IP、128个0.350ns min guard与PIX/USER额外50ps hold不变。
新报告中两个DDR负路径即使去除guard仍可能真实hold为负，不能删除守卫凑PASS。
route原生`fix_hold high / hold_fix_iteration10 / post_route_opt ultra`保持；日志未表明10次预算耗尽，不能盲增。
观察器endpoint-only例外有同域覆盖、CAM1 Gray max7.500被IP7.700覆盖的既有问题均明确记录，
本次不凭猜测改跨域边界或虚构IO延迟。最终报告仍需检查scope、同域min和coverage，不能只看WNS摘要。

## PIX映射结果与工具边界

带实际bootstrap的两种载体在本机LUT映射超时（4线程、1线程及登记观测输出尝试），原件保留。
最后复用已完成的5bd叶载体，公共wrapper/SDC/Tcl SHA一致，候选opt_gate与重开成功（76.953秒）。
旧5bd基准为固定门网表，只读导入未重写；其旧外层退出看门狗记录仍保留。

| 同叶载体门级估计 | 固定5bd基准 | 候选 |
|---|---:|---:|
| LUT / FF / Slice | 2079 / 2459 / 1575 | 2095 / 2459 / 1572 |
| 载体SWNS | +2.530ns | +3.045ns |
| 全来源→两路SOURCE error最差 | +3.942ns | +4.046ns |
| 全来源→SOURCE valid最差 | +4.205ns | +4.697ns |
| admit→SOURCE error | +4.235ns，7级 | 对象非空，查询无路径 |
| admit→SOURCE valid | +4.498ns，7级 | 对象非空，查询无路径 |

只读定向查询两边均命中1个admit、8个error和2个valid寄存器；新无路径对应组合依赖移除，
不是删除对象或时序检查。两边时钟预算都是8ns、uncertainty0；旧DB时钟名PROBE_CLK、当前映射名PIX。
本载体不包含原bootstrap的真实高扇出/布线，不能外推整机余量或相加为整机面积。
原始路径在`tmp/timing_pix_20261109/leaf_scoped/`，首次report脚本的close_design命令错误另留日志。

## 不采纳的实验

HDR bank年龄核对确有独立违例，两个严格等价改写均未进入生产：逆变换把延迟转到stamp端并增113 Slice；
共享分段借位整体估计变差且增20 Slice。见 [完整对照](HDR_AGE_SETUP.md)。保持实时now比较和原边界，
不能把提前采now或放宽年龄合法性当时序修复。这一族及未修正的普通hold仍是新P&R需重点复核的风险。

## 本轮独立黑盒

均由新的无实现上下文作者编写，只读公开IO/合同，不读RTL、旧TB或内部状态；每例有墙钟及仿真watchdog。

- [DFI四组](../../src_fpga/simulation/blackbox_dfi_timing_20261109/README.md)：8个真实CONFIG请求/ACK，双层AW/W/B到响应，R3/F3/R4边界和停钟再断言，84B ARAW经真实product CDC/FIFO到USER DONE、SAFE及源端退休。
- [PIX九项](../../src_fpga/simulation/blackbox_pix_jpeg_20261109/README.md)：首组、旧/新交错、同拍FAULT/BAD/FE/deadline优先、已发布SOURCE保持、热身/无效时间、回卷与停钟复位后的健康组。
- JPEG同目录14项：真实CDC/FIFO和410字扩展RAM，七个停钟复位切点、新身份恢复、E1/E2/E4、源prefix早拒与stream晚判隔离。

27个不同用例/测试组通过；分批通过的输入哈希复核，所有原始FAIL与合同澄清保留，不重复累计重跑。
JPEG只送短字节流；没有多帧满幅长仿真。原生整机read_design、同AL重开和现有层次检查通过。
本轮不是板级验证；相机/DDR/PCIe物理与满幅持续性能未重测。

## 编译计划

用户授权一次16线程共享综合，复用结果的32个物理种子各4线程，full至bitgen；注册camera_raw_r2，自动触发关闭。
种子包含本次12套完整报告的所有种子及20个既有对照种子，不靠取消失败或选摘要幸运值替代修正。
提交前绑定源码、冻结IP、AL、测试与原生检查；发布状态单独记录。新综合/P&R/STA/bitgen/板级目前NOT_RUN。
