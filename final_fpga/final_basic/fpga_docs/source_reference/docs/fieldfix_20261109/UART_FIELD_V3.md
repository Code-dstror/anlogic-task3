# 本轮只读 UART：DJ/v3

业务 BAR/CFG/AJPG/ARAW 不变。OB/v2、115200 8N1、每轮 OB29B＋DJ68B、两域224bit握手快照与SYS配置覆盖均保留。
DJ 版本从2变3，复用原PIX页两个FS计数位置和保留高16位；删除两个16bit物理FS计数器，不新增队列、追踪RAM或控制回路。
使用本版 tools/uart_observer.py，仍可离线解旧DJ/v1/v2；v3不再输出已失去含义的pixel.fs。

## 字节格式与有效性

DJ 0..5=`44 4a 03 01 44 00`；6..7序号小端；8fresh、9reset_n（bit0 DFI、bit1 PIX）；10..37 DFI224bit；38..65 PIX224bit；66..67 CRC16小端。CRC16/CCITT-FALSE，poly1021、initFFFF，覆盖前66B。
只使用fresh&reset_n有效的页。DFI、PIX、SYS配置并非同瞬间快照，不可拿包接收时间当真实事务时戳。

DFI页和PIX的capture_admit/target epoch/sensor SYS/原flags位置均与[DJ/v2说明](../fieldfix_20261108/UART_FIELD_V2.md)相同。

| PIX位偏移 | 内容 |
|---:|---|
| 0..31 | PIX配置引擎已发布的cfg_applied_epoch（替代旧两眼FS16计数）；注意其向USER回传/ACTIVE复制还有延迟 |
| 32..95 | 四路16bit capture_admit，顺序CAM0 L/S、CAM1 L/S；SDR则CAM0/CAM1/0/0 |
| 96..159 | 旧两个SYS配置32bit，由SYS FREEZE沿覆盖 |
| 160..175 | 原pixel_flags |
| 176..207 | 采集端当前target epoch（原pixel.epoch） |
| 208..223 | CFG事务及静默标志，定义如下 |

cfg_flags低位：0实时frame_accept，1source_ready，2response_active，3response_space，4remote_fault，5remote_applied，6remote_sent，7remote_pending，8frame_apply_eligible；11..9是PIX引擎状态（0IDLE、1WAIT_IDLE、2PREPARED、3WAIT_FRAME、4BOOT_BARRIER、5FAULT）。12cfg_pipeline_quiet、13physical_source_quiet、14maintenance_quiet、15native_pipeline_quiet。
这些是公开诊断的当前状态，不把短脉冲声明成事件日志。请求/响应编号和32字ACTIVE仍从既有BAR记录；没有新增USER→PIX CDC或业务读写地址。

## 故障区分

- WAIT_IDLE 且quiet不齐：旧帧排空尚未完成，比较native/maintenance/physical三条资格，再结合DFI bank/BEGIN拒收/负FINISH。
- WAIT_FRAME 且remote_sent=1、remote_applied=0：等完整远端ACK；target epoch只是其中一个域，不可代替whole ACK。
- WAIT_FRAME、remote_applied=1、eligible=1：等待真实CAM0新配置采集边界；两眼准入计数能帮助确定是否有输入。不能用采样时frame_accept=0证明从未来过脉冲。
- PIX applied epoch已推进、USER ACTIVE未推进：继续看response_active、response_space与同会话BAR响应；正常会有短暂跨域/复制延迟，长期不一致另行留证。
- 去雾目标已内部生效但未确认时，RK可以持有两条待确认记录，并因此停止补DMA槽。不能把后续产品停顿直接当作去雾数学模块死锁。

计数仍在RUN上升清零并计入同沿事件，关RUN后保持；模式切换不清。模数/漏样限制沿用v2。只有UART页输出，诊断不能反馈主系统 READY、复位、准入或所有权。
