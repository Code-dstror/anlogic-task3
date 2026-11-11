# 本轮只读 UART：DJ/v2

针对 seed92 的 HDR 不对称、CFG 首帧等待和 RAW 早期缺号，替换旧 DJ/v1 的首作业冻结窗口。旧窗口长期停在 epoch0，不能说明当前 HDR 工作状态。本版保留 OB/v2、115200 8N1、每轮 OB29B＋DJ68B；DJ 版本明确升到2，业务 BAR/CFG/AJPG/ARAW 格式不变。

`camera_field_diagnostics` 只输出给 UART 的页数据，没有向准入、READY、复位或槽管理返回的输出。使用已有两域224bit快照和发送器，未增加环形历史或 RX 控制。新的短计数器替代首作业身份、阶段事件和截止计时寄存器；不保留两套观测器。两眼相机配置字段在 SYS 域冻结，未把多位 I²C 状态直接跨到 PIX。

## Wire 与时钟边界

DJ 0..5字节为 `44 4a 02 01 44 00`，6..7轮次小端，8为fresh mask，9为reset_n mask（bit0 DFI、bit1 PIX）；10..37是DFI224bit，38..65是PIX224bit，66..67是CRC16/CCITT-FALSE小端。CRC覆盖前66字节，poly1021、initFFFF、无反射/xorout。DFI/PIX分别握手冻结，并非同一瞬间；SYS配置字段在 UART FREEZE 沿取样，跟两域快照又不是同一时刻。停钟/复位时不得使用相应无效页作当前证据。

## DFI页（位偏移）

| 偏移 | 位数 | 含义 |
|---:|---:|---|
| 0 / 32 | 各32 | 每眼最近真实 job TAKE 的 SOURCE序号，尚未TAKE为0；序号本身允许0，不用0替代valid证明 |
| 64 / 96 | 各32 | 当前DFI配置epoch/session |
| 128 / 144 | 各16 | CAM0/CAM1 job握手计数；RAW为record offer接受，JPEG为diag job valid/ready |
| 160 / 168 | 各8 | CAM0/CAM1实际BEGIN负答复次数，按当前HDR或stored SDR路径选择 |
| 176 / 184 | 各8 | CAM0/CAM1未完成HDR bank超时回收次数；同眼同拍多个bank折合一次；SDR为0 |
| 192 / 200 | 各8 | 各眼负FINISH发生的周期数；同眼L/S同时失败折合一次 |
| 208 | 8 | 4个HDR bank，各2bit，依次cam0bank0/1、cam1bank0/1；FREE0、BUILD1、READY2、OWNED3，stored SDR为0 |
| 216 | 8 | bit0RAW、1HDR、2RUN、3ticket recovery、4processing fault、5bridge fault、6read quiet、7HDR owner empty |

短计数按2^8或2^16回卷；应用RUN上升清零且包括同沿事件，RUN关闭后保持。模式切换不清零，以稳定epoch窗口作增量。8bit计数跨较长断流可能多次回卷，不能从余数恢复真实总数。拒收不一定是错误，也可能是有限容量已满；不能用拒收计数代替输入CRC。

## PIX页

| 偏移 | 位数 | 含义 |
|---:|---:|---|
| 0 / 16 | 各16 | CAM0/CAM1可信物理FS计数 |
| 32 / 48 / 64 / 80 | 各16 | HDR为CAM0 LONG、CAM0 SHORT、CAM1 LONG、CAM1 SHORT的实际capture SOF准入；SDR为CAM0、CAM1、0、0 |
| 96 / 128 | 各32 | CAM0/CAM1传感器配置SYS快照，见下文；由发送器覆盖保留区 |
| 160 | 16 | bit0 HDR请求、1双目、2RAW、3cfg_pause、4/5两眼mode_running、6/7两眼HDR stable、8/9两眼config_done、10/11两眼config_error、12/13两眼identity fault、14/15两眼receive fault |
| 176 | 32 | PIX捕获配置epoch |
| 208 | 16 | 保留0 |

SYS配置32bit：warmup[31:24]，寄存器序号[23:16]，配置状态[15:12]，clock_locked[11]，abort[10]，held source_fault[9]，pair_event[8]，pair_ok[7]，config_written[6]，stable[5]，error[4]，write_valid[3]，write_ready[2]，write_done[1]，I²C error[0]。终止NACK时序号和错误保持，便于区别源资格故障；瞬态I²C进度是SYS取样，不声称记录所有ACK事件。

## 解码与定位

使用本工程 `tools/uart_observer.py --input <原始bin> --pixel-layout stereo`；单目用 `mono`。可继续解旧DJ/v1。分片只收到单字节 `D` 时也保留，下一片 `J` 到达后正常组帧，CRC失败仍拒绝。

- HDR慢眼：先核对四路实际准入，再看每眼BEGIN拒绝、负FINISH、bank BUILD超时、job和RK记录；不能再把旧版raw_admit两槽误读成两眼。半组拒收修复应避免迟到peer造成持续BUILD/超时放大，真实满载仍可能拒收。
- CFG超时：查看两眼config_error及SYS source_fault/NACK/index/phase，结合原CFG BAR的REQ/RESP/ACTIVE/ERROR；不能仅靠OB某一位猜阶段。
- RAW缺号：对比每眼准入、BEGIN负答复、负FINISH与last SOURCE及主机lease时间，区分满槽拒收、坏SOURCE和在途尾部。没有逐帧证据时保留未知，不改源序号掩盖缺号。

OB双目布局沿用原硬件：PIX level bit11=CAM1 config_error、bit6=CAM1 PHY_READY、bit5=CAM1 config_done、bit4=CAM0 config_error。它们不是单目布局的HDR stable/mode/delay。旧版现场所有原始bin保持，不重写原证据。
