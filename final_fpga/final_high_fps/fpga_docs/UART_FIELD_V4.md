# DJ/v4 只读 UART 公开合同

生产 SYS 时钟 25 MHz，`UART_DIV=217`，115200 8N1，线上低位先发，空闲高。
每轮先发原 OB/v2 29B，再发同序号的 DJ/v4 76B。DJ 的前 66 字节沿用 DJ/v3 的字段，
版本和长度按本表。计数和事务观察只驱动 UART 数据。

| 字节偏移 | 内容 |
| --- | --- |
| 0–5 | `44 4a 04 01 4c 00` |
| 6–7 | 本轮序号，无符号小端 16 位 |
| 8、9 | fresh、reset_n 各一字节，bit 0 DFI，bit 1 PIX，高位为零 |
| 10–37 | DFI 224 位快照，低位在先 |
| 38–65 | PIX 224 位快照，低位在先 |
| 66–67、68–69 | CAM0、CAM1 可信物理 FS 各 16 位，无符号小端 |
| 70–73 | 保留零 |
| 74–75 | CRC16/CCITT-FALSE 小端，poly `0x1021`、init `0xffff`，覆盖 0–73 |

DFI 页的位偏移 0/32 是两眼最近的成功作业接受序号，各 32 位；64/96 为 epoch/session，各 32 位；
128/144 为作业握手计数，各 16 位；160/168 为 BEGIN 负答复，176/184 为配对过期，192/200 为负 FINISH，
每项 8 位；208 起 8 位是四个 2 位 bank 状态；216 起 8 位是 DFI flags。

PIX 页 0–31 为 PIX 配置引擎的已发布 epoch。32–95 为四路 16 位准入计数，HDR 顺序 CAM0 L/S、CAM1 L/S，
SDR 顺序 CAM0/CAM1/0/0。96–159 为 SYS 冻结时的两眼传感器配置。160–175 是 PIX flags。
176–207 是捕获端 target epoch。208–223 为 CFG 状态和 quiet flags。

CFG flags 的位 0–8 依次为 frame_accept、source_ready、response_active、response_space、remote_fault、
remote_applied、remote_sent、remote_pending、frame_apply_eligible。位 11–9 为 PIX CFG 状态，
0 IDLE、1 WAIT_IDLE、2 PREPARED、3 WAIT_FRAME、4 BOOT_BARRIER、5 FAULT。位 12–15 依次为
cfg_pipeline、physical_source、maintenance、native_pipeline 的 quiet。

PIX FS 与 PIX 页同一次快照。两眼可信 FS 仅在实际事件接受且身份有效时计数。
模数计数在各自 RUN 上升的采样沿清零并计入该沿事件，停止 RUN 后保持，模式切换不中途清除。
DFI 与 PIX 各有自己的观察时钟和 fresh/reset_n 状态，SYS 配置在发送前另行冻结。
使用各页 `fresh && reset_n` 判断本轮有效性。页中的瞬时位和包到达时间不能作为硬件事务时间戳。

## 独立短测接口

使用 [UART 与计数器公开端口](../fpga_prj/verification_archive/verification_reference/UART_FIELD_V4_PORTS.vh)。
可用 `uart_status_observer` 和 `camera_field_diagnostics` 相连，生产 RTL 与另外两个快照模块不透明编译。
编译四个模块 `uart_status_observer`、`camera_field_diagnostics`、`uart_observer_snapshot`、`cfg_diag_snapshot`。
`CFG_DIAG_ENABLE=1`、`JOB_PAGE_ENABLE=1`、`CFG_FRAME_VERSION=4`、`JOB_SYS_CONFIG_ENABLE=1`，RX 与 trace 关闭。
可缩短 `UART_DIV`、报告间隔与快照超时，`UART_DIV` 至少 2。驱动独立 SYS/PIX/DFI/USER 时钟，先共同断言
观察器复位并保持业务 reset payload 低，再释放并注入不对称 FS、捕获准入、target/applied epoch 和 CFG flags。
通过公开 TX 解出完整 8N1 字节，检查已接受的事件增量、CRC、停钟时的 fresh 降级和时钟恢复。
SDK 解码独立覆盖 v2/v3/v4 混流分片及坏 CRC 后下一合法帧。

旧字段详见 [DJ/v2](../../camera_raw_r2/docs/fieldfix_20261108/UART_FIELD_V2.md) 和
[DJ/v3](../../camera_raw_r2/docs/fieldfix_20261109/UART_FIELD_V3.md)。解码入口为
`python -B tools/uart_observer.py --input <capture.bin> --pixel-layout stereo`，从本工程根运行。
