# 修复保留与逐步优化

修改前已用真实远端分支和祖先关系确认 `eade457d7477110605f90eb5abc08420d8936642` 在云端。
当时远端HEAD为`de1efb72c172f0d4666ebbe43f4efed0ace02438`，生产文件与回退基线完全一致。
[核查记录](ROLLBACK_BASELINE.json) · [eade生产封印](EADE_SOURCE_SEAL.json)

## 历史修复

静态保留审计PASS。405个RAW R2输入全部在融合工程保留，结合实际TOP、参数和约束核对14项故障链。
没有发现已交付修复漏合入。RAW早期缺号仍未唯一归因，同owner单/双目软切仍是RK方案；未把两者写成新RTL修复。
旧bit板级状态和当前融合资格分开；没有复跑未改变的全量回归。
[逐项修复、源码与证据边界](FIX_RETENTION.md)

## 已采用：熵码字64位分级对齐

仅修改`jpeg_entropy.v`的码字数据对齐，按位内和整字节两级构成64位追加值，保留原容量门、
有效位、状态、DC预测器、restart、FF00、pad、取消和帧身份。原72位额外切片被删除。
精确源SHA为`c6f2e10a8208e500c98154d3e7647f2d4d11a8ed3e7df9fd1f94a09b488a77c7`。

| 同设置局部载体 | 原始gate Slice | 同AL重开 Slice | 整体setup估计 | 说明 |
| --- | --- | --- | --- | --- |
| 直接注册READY，SYN16 | 1860→1741 | 1844→1724 | +2.309→+2.365ns | 原count关键路径改善1.245ns，直接READY路径回退0.888ns |
| 含生产READY组合关系，SYN4 | 1983→1744 | 1980→1738 | +2.356→+2.384ns | 最差READY返回+4.054→+3.967ns，最大单类回退0.139ns |

两载体FF/ERAM/DSP各自保持一致；后者局部减少242 Slice。不能将两个载体的收益相加或直接
从整机扣减。候选新网表还需复核实际生产READY连线和物理时序。所有本机单臂均设置170秒进程
看门狗加终止清理余量；原超时/不完整报告保留并区别于同AL后续补读。
[全部候选、数据路径与原件](AREA_RESULTS.md)

独立作者新写数学与协议oracle：11个直接熵事务、4个完整编码器事务通过，三个成功JPEG
逐字节匹配独立黄金并完整解码。基线和候选的输入输出握手周期、字节、KEEP/LAST、SOURCE、
RESULT及异常前缀trace SHA完全相同。完整编码器拆为低→高成功及负SOURCE→恢复两个短序列，
负帧与恢复保持同一次复位，每进程不超过56秒。原并发/长序列墙钟中止记录未抹除。
[独立黑盒报告](BLACKBOX.md)

整体read_design和同AL重开46.750秒通过。新设计封印
`d6d0a4d05b7a9f2a8465bc3a1e3c413af09415b3505195eeba2d069cb36dabed`，408个生产输入、253注册、156冻结IP。
本阶段无IP/SDC/接口或传感器配方改动。修正源清单生成器的旧运行参数描述：从实际AL读取显式
Strategy/UserParams，`hold_fix_iteration`实际一直为10，未改原生设置；服务器请求覆盖另计。

## 已采用：PIX原始源数据资格与ASR分离

5个eade布局报告的PIX最差路径都是F3下降沿释放进入数据/READY资格，4ns预算。
仅在`private_raw_isp_borrow4`复用已有R3释放链，给RAW/SOURCE READY及payload enable提供
同域数据资格；F3继续用于原ASR、cleanup及adapter，没有新增寄存器或SDC例外。
实测候选SHA为`7a1ef673db77bc3f5b961f717e208c9180aa742d0a6dd51c851ab8cf875228ba`。

SYN4同载体原始/重开均1294→1223 Slice、1467→1316 LUT，1551 FF、ERAM/DSP=0均不变。
F3→RAW ingress数据原为4ns预算、+0.742ns；候选该F3数据路径消失，R3路径用8ns预算、+4.514ns。
整体setup估计+0.742→+1.593ns。剩余F3 adapter CE仍按4ns检查；未取消本域min/ASR检查。
[路径与面积原件](../../fpga_prj/verification_archive/experiments/reset_data_qual_r2_20261110/README.md)

新独立黑盒只看公开端口：两臂各5笔成功、1笔取消、2次停钟恢复，1589行公开trace相同。
16×4与32×8两个合法14bit/external-ISP profile涵盖身份、尾承诺、stale SOURCE、两种post drain
阻挡和取消后恢复。冷启动及高/低停钟均F3释放、R4首次可用，所有成功事务到真实STATUS与pool_idle。
该叶不证明ISP数值、10bit非生产profile或满幅吞吐。
[独立RAW源短门](RAW_SOURCE_BLACKBOX.md)

两项合入后的整体read_design/同AL重开53.125秒、原生层次14.469秒均通过。再复跑已有独立
真实ISP/JPEG/DDR/native产品normal序列，首帧、SLVERR负终态和同会话恢复通过；这是组合回归，
与本轮全新作者的两个独立短门分列。当前封印
`bbac5912e69e5198c31dccd6894e0b135a5fd08952bebb40591476e79a490597`。
[组合产品结果](../../tmp/blackbox_fusion_product_optimization_r2_combined/summary.json)

## 已采用：DFI ring数据资格与ASR分离

实际Placed报告另一共性为ring F3进入egress READY和写静默回授。候选在`jpeg_frame_ring`
默认关闭的独立数据资格接口上，只把START/DATA/RESULT READY与写静默接到原R3；
`ddr3_jpeg_store`生产实例启用该接口，F3仍给ASR、AXI、全局记录静默与退休使用。
没有删掉真实B、写ACK、slot身份或READY/读尾/RETIRE条件。

完整FIFO XML/官方约束闭包下SYN4两臂PASS：raw2778→2752 Slice、reopen2774→2747，
LUT少33，3188FF/5ERAM/0DSP不变。本域setup估计+0.513→+0.990ns。
原F3经egress READY的路径转R3；真实FIFO读计数R3路径+5.443ns，保留的全局marker仍有F3路径。
RAM CE虽然命中引脚，但gate计时器不接受为有效终点，保留物理复核缺口，不把它写为PASS。
[完整原生证据与原失败](../../fpga_prj/verification_archive/experiments/ring_data_qual_r3_20261110/RESULTS.md)

新独立黑盒两臂1411个DFI采样逐项相同，10 START、9成功ACK、1失败ACK、8正常退休，
六槽、代次复用、长/短尾、延迟B、失败B后恢复、读写并发及停钟R4均覆盖。SAFE是下游模型前提，
不作为真实PCIe板级资格。[独立ring门](RING_RESET_BLACKBOX.md)

最终生产只改4份RTL（entropy、private RAW owner、ring、DDR包装），IP/SDC保持原字节。
新封印`df8064e9bd11af7c9fcf1e2b76169547d9d61d7b9b5ed8c26204ef864e0fee7e`。
新整体read_design/同AL重开53.625秒、层次14.437秒通过；用新生成的实际DDR包装产品夹具
复跑首帧/晚B/SLVERR/同会话恢复，18.812秒通过，JPEG数值和真实退休通过。
[组合产品回执](../../tmp/blackbox_fusion_product_optimization_r3_combined/summary.json)

## 排除与后续物理复核

AC幅值阈值改写增大面积，未采用。72位固定切片合并的面积收益较小且路径回退，完整编码器
未在原时限内完成，保留实验。JPEG packer KEEP阈值载体不省Slice且增加LUT，同样不采用。
[KEEP对照](../../fpga_prj/verification_archive/experiments/packer_keep_r2/README.md)

实际`eade457d`综合报告已校验并留存；后续5个种子的Placed报告证明基线装入到放置，setup仍有负值，
没有hold/removal明细。其主要热点是原始源和ring的F3释放进入半周期数据回授，并非本次熵核。
PIX和DFI分离均已按上述证据采用，仍须在新源物理结果中核对setup/hold/recovery/removal、
真实FIFO RAM CE以及保留的marker和adapter CE路径。
[同源综合原件](eade_synthesis/INDEX.json) · [5种子Placed分析](PLACED_BASELINE.md)

`eade457d`的20种子批次不变。新本地源的整机SYN/P&R/四类物理STA/bitgen/板级均为NOT_RUN，
局部估计及旧Placed结果不转移为新源物理通过。

最后一轮packer可达状态小试删除两处不可达分支，四组独立黑盒通过，LUT122→104而Slice仍117。
数据使能路径有最大0.668ns估计回退，未采用。生产packer不变。
[最后一轮实验](../../fpga_prj/verification_archive/experiments/packer_reachable_r4_20261110/README.md) · [独立短测](PACKER_BLACKBOX.md)

用户要求北京时间22:40后收尾并提交80个各4线程full种子；新批次一次SYN4共享，旧eade20种子
保持固定源。实际发布和接收状态见[新构建记录](../SERVER_OPT_BUILD_20261110.md)。
