# DFI JPEG ring 复位与数据资格提案

固定融合源 `eade457d7477110605f90eb5abc08420d8936642` 的五个已放置种子在 DFI
均观察到从 ring F3 释放发出的负 setup。DFI 周期 7.502 ns，下降沿到正缘预算 3.751 ns。
种子 1、5 终点为真实 ordered token FIFO 的读缓冲 CE。种子 2–4 的物理网包含
`i_pair_product_quiet`，终点为 HDR owner 或正常 SDR replay 状态。s1 的路径经过
`o_token_ready`，同一物理单元的别名还包括 metadata gate。逻辑上 START、DATA、
RESULT 的三个 READY 都能到达这个 token CE 锥。
[五种子放置原件](../../docs/optimization_r2_20261110/PLACED_BASELINE.md)

## 建议的最小切口

在 `jpeg_frame_ring` 末尾加入默认关闭的 `SEPARATE_DATA_RESET` 参数和
`i_data_reset_n` 端口。模块内部只为下表四项选取数据复位。生产
`ddr3_jpeg_store.g_ring_store.u_record_owner_reset` 换用既有
`reset_release_sync_data(DATA_RESET_COPIES=0,FALLING_RELEASE=1)`，同一实例
的 F3 输出照常提供原 reset，R3 接新的数据资格。零复制分支直接取原三拍链末级。
现有 SDC 的 SYS25 → 此实例 `release_pipe[*]` 选择保持同名，R3 的本域数据路径正常计时。

| `i_rst_n` 当前用途 | 处理 |
| --- | --- |
| `o_start_ready`、`o_jpeg_tready`、`o_result_ready` | 数据资格使用 R3。保留所有 START 分配、DDR/config、输入和 RESULT 条件。 |
| `o_write_quiescent` | 只换 reset 因子。保留无恢复故障、写空闲、无待接受写回执、staged 空、FIFO/输入空和无待处理 START。 |
| `fifo_sr_done`、`fifo_rr_done` | 当前两者均为 `i_rst_n`，ring staging 是同钟 16 字。仅在前两行重写的布尔式中合并两个重复 reset 因子。全局记录静默仍沿用两标志。外部 token FIFO 的实际双域复位及完成信号沿用。 |
| `o_record_quiescent` | 保留 F3 和完整的 reader、选择、请求、写回执、退休响应、slot pending、cold dirty、输入和请求资格。 |
| `o_ready_valid`、`o_read_complete`、`o_req_ready`、`o_retire_ready` | 保留 F3 和原有有效性、仲裁及身份边界。 |
| AXI AW/W/B/AR/R 和读载荷 VALID | 保留 F3，所有 burst 和响应继续按实际握手推进。 |
| timestamp RAM 写、cold bank 复位与读 CE、所有异步复位时序块 | 保留原 F3 连接。两个 identity RAM 的写仍由真实 START 拥有。 |

对默认关闭的参数，前两行代回 `data_reset_n=i_rst_n`，合并的 `i_rst_n` 与原布尔式
相同。对生产启用的参数，R3 之前两个释放都低。R3 采样仍见旧低值。随后到 F3 之间
DATA 和 RESULT 因写 owner 空闲保持低。空闲 START credit 和写静默证明可在这个半拍
区间提前变高。其直接消费者如下。

- START 经本域 record metadata gate 的 reservation 与 take，或单槽 credit 的 sink
  寄存器。跨 PIX 的 grant 由原 CDC 握手带出。DATA、RESULT 经 DFI egress 进入本域
  token buffer 消费，FIFO source reset 和跨域指针保持既有路径。
- 写静默经 `full_raw_store` 的 DFI 配置状态、HDR owner `release_ready/clear_slots`
  及 Stereo slot retire。normal 路径的 slot-local 条件、ticket 和 read quiet 保持。
  `raw_region_quiet` 进入全局证明时仍与 F3 的 `record_ring_quiescent` 相与。
- 写静默还进入 RAW ticket 的 DFI recovery 和 operation-complete，返回 PIX 的事件
  仍由既有寄存器和 FIFO 发布。UART 从 DFI 寄存器采样。直接消费者均按 DFI 正缘成交。

F3 之后 R3/F3 同时为高，第一合法采样仍为 R4。两路异步断言来自同一三拍链，协调
reset 可在停钟时进入原复位。公开对照比较正缘的成交、输出和静默证明。半拍内的
START/写静默电平属于启用参数的已知变化，接线应限于已核对的同域采样消费者。

## 局部原生 A/B

先用真实六槽 `jpeg_frame_ring`、`jpeg_ring_cold_bank`、存储叶和真实
`ordered_frame_egress`。ring 取生产 `CAMERA_COUNT=2`、`SLOT_BYTES=16MiB`、
写结果和 tag 开启、MASK 关闭。使用生产 egress 的 CONTEXT、写 tag 和流式 extension
配置。输入出口使用窄寄存字段，保持同设置两臂。token FIFO 可接现有
`axis_frame_fifo_ip` 与原字节 147×512 注册 IP，以读回真实 FIFO CE。START 路径
保留 metadata gate 的已保留资格组合关系；在局部载体以寄存 reservation 字段代表
外围状态。写静默使用同域观察端点和 HDR `release_ready` 的生产组合关系，避免带入
完整 slot 目录和 RAW 数据。资源原件中 ring、egress、token FIFO 各约 1036、511、
566 logic LUT，完整 HDR owner 单独约 1690 logic LUT。它们是整机层次口径，只用于
确定载体规模。综合若达到 180 秒预算，保留原失败并用 real ring + real egress 和
局部 FIFO 握手端点作为更小载体，明确实际覆盖范围。

TD 6.2.3.210850，PH1A90SEG324-2，DFI 7.502 ns、波形 0.229/3.980 ns，SYN4
面积优先、partition、`add_map_lut_struct on`、`min_control_set 2`。每臂独立
AL/Runs，显式 `--td-root`，180 秒墙钟上限。比较原始／重开面积和 timing。分别取
F3/R3 到 egress/token CE、写静默观察 D/CE、ring slot D/CE、复位 ASR 的对象数、
路径与预算，记录残留全局记录静默和本地读/写路径。物理比较仍用同源新工程。

## 独立黑盒边界

向新作者提供公开端口、合法 profile 和不透明清单。以真实 ring 加真实 egress
或公开 DFI 事务接到真实 ring，DDR 使用有限 AW/W/B/AR/R BFM。逻辑 DRAM 使用同
版本模型。短小输入可使用固定生产槽地址和稀疏 BFM 存储，持续传输长度另记。

- 冷启动和停 DFI 时的协调复位。记录 R4 首次合法 START，比较两臂正缘的
  START/DATA/RESULT READY、实际成交、写静默和全局静默。写静默在 pending START、
  已承诺 burst、未接受写回执和恢复要求存在时维持低。
- 首个合法 START 冻结 camera/session/epoch/capture/quality、非零 writer tag 和
  generation。DATA 每非尾拍全 KEEP，尾拍低位连续非零 KEEP。STALL 下 AXI 和所有
  已发布数据/身份稳定。用多于一 burst 的小帧，暂停 AW/W 与最终 B；即使 RESULT
  已成交，也要等真实成功 B 和完整字节对账才有成功 writer ACK 和 READY。
- 负 B 与其后合法恢复。负帧完成实际已承诺的 AXI 数据，未成功的写回执带原身份，
  不提交 READY。接受负回执前写静默为低。追加合法帧完成完整写读事务。
- READY 描述符及 payload 在反压下稳定，读末拍真实握手后进入 read-complete。
  独立区分 ring 写回执、READY、读末拍、下游真实 SAFE/主机 ACK 与 RETIRE。
  ring 仅接收 RETIRE，测试将 SAFE 作为下游已完成的独立驱动条件。读取在途的
  匹配 RETIRE 返回 BUSY，已读完后的错 generation 返回 STALE。匹配退休及 held
  response 成交后，确认槽可重新使用且 generation 递增。若要证明真实 SAFE，
  另由含实际记录和 host transport 的系统门给出证据。
- 写者空闲时允许已提交、待 claim 或正在读的记录存在。此时写静默与全局记录
  静默应区分。比较实际采样和字节、身份、终态，明确综合、仿真和物理的范围。
