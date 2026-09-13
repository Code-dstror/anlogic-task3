# PCIe JPEG 帧协议 v0.1（DRAFT）

- 状态：**DRAFT，未冻结**
- 日期：2026-09-13
- 适用范围：RK3576（PCIe RC）与 FPGA（PCIe EP）间的第一版 JPEG 接收接口。

## 1. 边界、证据与术语

本文将内容分为三类：

- **官方源码事实**：课程包 Linux 源码可直接证实。`anlogic_pci.ko` 枚举并建立 SGDMA 字符设备；其 C2H `read()` 通过 `sgdma_xfer_submit()` DMA 到用户页并返回完成字节数。SGDMA 有轮询和 MSI/MSI-X/IRQ 两种驱动模式，课程脚本采用 `poll_mode=1`。现有 V4L2 示例固定 RGB24、固定帧长，不能直接作为 JPEG 接口。
- **本项目建议**：为实现 JPEG 所提出的 ABI，须经 Linux 与 FPGA 双方确认和实机验证。
- **TBD**：没有实机或 RTL 证据，不能定案的参数/行为。

本协议不规定 PCIe 2.0 或 3.0、链路速率、BDF、BAR 物理地址、实际 `/dev` 节点名、BAR 编号、DMA 通道号、slot 数量或最大帧长。均须由枚举、驱动 probe、BAR resource 和实测确认。

## 2. 数据流与第一版范围

```text
MIPI 传感器
  → FPGA 采集 / 三项预处理 / JPEG 编码
  → FPGA 帧封装（DRAFT 头 + JPEG payload）
  → PCIe EP AXI-Stream C2H → SGDMA
  → RK3576 用户态（动态发现 PCI 设备、BAR、C2H 字符设备）
  → 协议校验与缓冲管理 → JPEG 解码
  → 图像预处理 → RKNN 推理 → 带 frame_sequence 的结果
```

**本项目建议**：第一版仅使用 SGDMA 字符设备及用户态接收库/服务；不加载或修改固定 RGB24 的 V4L2 包装层。可轮询 `frame_ready`/状态并发起 C2H 接收。MSI/MSI-X 与 events 节点仅作为后续优化候选。若有效载荷被实测为兼容 JPEG，后续可提供 V4L2 MJPEG capture 适配，但不改变本协议作为底层合同。

## 3. 帧记录草案（本项目建议）

一个逻辑帧为 `header || payload`，payload 为完整 JPEG 码流，要求以 `FF D8` 开始、`FF D9` 结束。默认推荐“一 slot 一逻辑帧、一帧一 C2H 完成边界”；SGDMA 的实际 EOP/tlast 与该边界是否一致为 **TBD**，必须实测。

所有多字节字段为**小端**（little-endian）。字节流 JPEG 本身不适用端序转换。字段偏移以字节计，v0.1 的 `header_size` 暂定 64；DMA 起始、slot stride、header 与 payload 的对齐粒度均为 **TBD**，实现至少应支持 64-bit 字段自然对齐，且以 SGDMA 对齐查询/实测为准。

| 偏移 | 大小 | 字段 | DRAFT 定义 |
|---:|---:|---|---|
| 0x00 | 4 | `magic` | ASCII `JPV0`；具体常量冻结前为 DRAFT。 |
| 0x04 | 2 | `protocol_version` | `0x0001` 表示本草案版本。 |
| 0x06 | 2 | `header_size` | 字节数；v0.1 建议为 64，Linux 须先校验范围再解析。 |
| 0x08 | 4 | `flags` | bit0=CRC 有效；其余保留为 0，语义 TBD。 |
| 0x0c | 4 | `frame_sequence` | FPGA 单调递增的无符号序号，回绕按模 2^32 处理。 |
| 0x10 | 4 | `payload_length` | JPEG 有效载荷字节数，不含 header/padding，且不大于协商 `max_frame_length`。 |
| 0x14 | 2 | `width` | 解码前图像宽度，单位像素；具体有效范围 TBD。 |
| 0x16 | 2 | `height` | 解码前图像高度，单位像素；具体有效范围 TBD。 |
| 0x18 | 4 | `encoding` | v0.1 预留枚举；`JPEG` 的数值、baseline/progressive、采样格式和质量参数均 TBD。 |
| 0x1c | 4 | `reserved0` | 写 0；接收端忽略。 |
| 0x20 | 8 | `timestamp` | 采集或编码完成时间戳；时钟源、单位、纪元和跨端同步均 TBD。 |
| 0x28 | 4 | `crc32` | 当 flags.bit0=1 时，为双方确认算法得到的 payload CRC；算法/初值/覆盖范围 TBD。 |
| 0x2c | 20 | `reserved1` | 写 0，供后续版本扩展。 |

接收端必须：先验证 `magic/version/header_size`，再验证长度和 slot 容量，最后在 CRC 启用时校验 CRC，并检查 SOI/EOI。保留字段非零仅记录为兼容性告警，除非后续版本另行规定。

## 4. 缓冲方案比较与推荐

| 方案 | 优点 | 风险/代价 | 结论 |
|---|---|---|---|
| 固定容量 slot 承载可变 JPEG | 单次提交可得到完整 header+payload；状态机和回收简单；有稳定帧边界。 | 未用满的 slot 有空间浪费；需处理超长帧。 | **v0.1 推荐（DRAFT）**。slot 数、slot 容量、stride、对齐和最大帧长均 **TBD**。 |
| header 与 payload 两次 DMA | 元数据可先到；payload 可按真长申请。 | 两次 DMA 的配对、竞态、超时、覆盖和帧号一致性更复杂；依赖未验证的触发顺序。 | 后续候选，不作 v0.1 首选。 |
| 连续环形缓冲区 | 空间利用率高，可连续流化。 | wrap、部分记录、producer/consumer 内存可见性和恢复复杂；需要更严谨的描述符/水位线合同。 | 性能阶段再评估。 |

推荐布局是 FPGA 逻辑 producer 写入一个可用 slot，写完 header 和 payload 并完成校验字段后，再以状态/索引发布 READY。Linux 只对 READY slot 发起 C2H 读，检验完后明确回收。DMA 目标缓冲区的分配方式、一次 read 是否可精确收至 EOP、以及 slot 数据存放于 FPGA 哪种存储均为 **TBD**；不得由本协议假设 SGDMA 会自动维护这些 slot。

### 4.1 三个架构未决问题（DRAFT）

#### 长度发现：DMA 前如何知道 `payload_length`

若 `payload_length` 只位于待 DMA 的帧头内，Linux 在发起该帧 DMA 前并不知道安全的传输长度。以下均是待双方确认的候选，而非 v0.1 已选 ABI：

| 候选 | 优点 | 未决风险 |
|---|---|---|
| BAR 提供每-slot 长度，Linux 再按长度 DMA | Linux 可预先按真实长度分配/提交。 | 每-slot metadata 寻址、发布顺序、长度与 payload 一致性及 BAR 可见性 TBD。 |
| 固定 DMA 整个 slot | 不需要先获知长度，接收路径简单。 | 空间/带宽浪费；Linux 仍须随后验证 header 长度，且需确认 EOP、padding 和整 slot DMA 可行。 |
| header 和 payload 分两次 DMA | 先得到 header 再按真长接 payload。 | 两个 DMA 的帧配对、覆盖、超时和状态认领更复杂；SGDMA/RTL 是否支持所需边界 TBD。 |
| SGDMA 返回实际完成长度 | 可利用 C2H 完成长度。 | 只有当 FPGA 的 EOP/tlast 与一帧严格对应、驱动配置/实测能可靠终止传输时才成立；目前不得假设。 |

#### 多 slot metadata：如何区分每个 READY slot

单组 `FRAME_READY`、`PAYLOAD_LENGTH` 和 `FRAME_SEQUENCE` 只能表达一个当前视图，不能完整表达多个 slot 的独立 metadata。候选为：

| 候选 | 优点 | 未决风险 |
|---|---|---|
| 每-slot 独立 BAR metadata 表 | 同时可见多个 slot，Linux 可按索引读取。 | BAR 空间、表项原子发布、跨时钟域同步和读写权限 TBD。 |
| `SELECTED_SLOT` 寄存器窗口 | BAR 占用小，复用长度/序号窗口。 | 选择与读取的原子性、并发访问、选择切换时机和锁定语义 TBD。 |
| FPGA 内存中的 descriptor ring | 可扩展且适合连续队列。 | 内存访问方式、descriptor 格式、DMA/CPU 可见性、wrap 和恢复合同 TBD。 |

必须冻结每-slot metadata 的完整字段、地址/索引方式、发布次序和 Linux 读取后的复核规则；slot 内帧头仍是 payload 的最终自描述证据。

#### 状态所有权：谁写状态，何时数据可见

`EMPTY`、`WRITING`、`READY`、`READING` 的现有表仅是建议状态模型，不是已确认的写入权限表。双方必须逐状态明确：FPGA 或 Linux 哪一侧可写、另一侧如何认领、是否允许写回退、以及谁负责最终回收。特别是：

1. FPGA 必须在 payload 与该 slot metadata 完整可见后，才发布可被 Linux 观察到的 `READY`。
2. Linux 必须在不再 DMA、解析或解码该 slot 后，才发布可被 FPGA 观察到的 `EMPTY`/回收信息。
3. FPGA 写入域、PCIe/BAR 域与 Linux CPU/DMA 观察域之间的跨时钟域同步、寄存器/内存顺序、barrier、重读或握手方案均为 **TBD**；不得将软件读写顺序当作硬件可见性保证。

未确认前，Linux 不得基于单个全局状态寄存器假设多 slot 可安全并行，也不得允许 FPGA 覆盖 `READY` 或 `READING` slot。

## 5. 状态机、所有权与可见性（本项目建议）

| 状态 | 所有者 | 允许动作 | 转移 |
|---|---|---|---|
| `EMPTY` | FPGA 可取得；Linux 已放弃 | FPGA 选择该 slot 开始写。 | FPGA：`EMPTY → WRITING` |
| `WRITING` | FPGA | 写 header/payload/CRC；Linux 不读取。 | 完整写入并发布：`WRITING → READY`；失败：回收为 `EMPTY` 并记错。 |
| `READY` | Linux 可取得，FPGA 不得改写 | Linux 读 metadata 后对对应记录做 DMA。 | Linux 成功认领：`READY → READING`；复位/丢弃按恢复流程回收。 |
| `READING` | Linux | DMA、解析、CRC/JPEG 校验与解码；FPGA 不得覆盖。 | Linux 完成或判错：`READING → EMPTY`。 |

发布顺序为“slot 内容先完整可见，再更新 `payload_length/frame_sequence` 镜像、producer 索引和 `frame_ready`”；回收顺序为“Linux 不再使用该 slot，再更新 consumer 索引/回收 doorbell”。寄存器读写的原子性、跨时钟域同步、内存屏障、索引编码（单调计数或环形模数）、乱序处理与寄存器写 1 清除语义均由 FPGA RTL 和 Linux 驱动实机共同确认，当前 **TBD**。

## 6. BAR 寄存器草案（本项目建议，非官方定义）

BAR 编号、映射地址、寄存器宽度和真实可用大小由 PCIe 枚举决定；以下仅定义建议的用户控制窗口内 32-bit 偏移。读写属性以表为准，`RO/RW/W1C` 的实现细节均待 RTL 确认。

| 偏移 | 寄存器 | 属性 | DRAFT 用途 |
|---:|---|---|---|
| 0x00 | `PROTOCOL_VERSION` | RO | 协议主/次版本。 |
| 0x04 | `CAPABILITY` | RO | 支持 CRC、轮询通知、IRQ、slot 模式、可选 MJPEG 等位图；bit 分配 TBD。 |
| 0x08 | `MAX_FRAME_LENGTH` | RO | 最大 JPEG payload 字节数。 |
| 0x0c | `SLOT_COUNT` | RO | 可用 slot 数。 |
| 0x10 | `SLOT_STRIDE` | RO | slot 间距（字节）；TBD。 |
| 0x14 | `PRODUCER_INDEX` | RO | FPGA 已发布 READY 的生产索引/计数。 |
| 0x18 | `CONSUMER_INDEX` | RW | Linux 已回收的消费索引/计数。 |
| 0x1c | `FRAME_READY` | RO | READY 可用性/数量或位图；精确定义 TBD。 |
| 0x20 | `PAYLOAD_LENGTH` | RO | 当前/选定 slot 的有效载荷长度；slot 选择机制 TBD。 |
| 0x24 | `FRAME_SEQUENCE` | RO | 当前/选定 slot 的帧序号。 |
| 0x28 | `ERROR_STATUS` | RO/W1C | 粘滞错误：超长、覆盖、编码、DMA/链路等；bit 分配 TBD。 |
| 0x2c | `RESET_CONTROL` | WO/RW | 请求数据路径复位；值、作用域、完成条件 TBD。 |
| 0x30 | `INT_STATUS` | RO/W1C | 帧就绪、错误、复位完成等中断状态。 |
| 0x34 | `INT_ENABLE` | RW | 上述中断使能；v0.1 可置零。 |
| 0x38 | `INT_ACK` | WO/W1C | 中断确认；与 `INT_STATUS` 的关系 TBD。 |

若硬件最终采用每-slot metadata 表，`PAYLOAD_LENGTH/FRAME_SEQUENCE` 应扩展为按 slot 索引访问的窗口；不得让 Linux 以全局镜像替代 slot 内 header 的最终真实性检查。

## 7. 异常、丢帧、背压与恢复

| 情形 | v0.1 建议处理 |
|---|---|
| 超长帧 | FPGA 不发布 READY，递增错误计数并丢弃该帧；Linux 若发现 `payload_length` 超容量，同样丢弃并回收。最大值 TBD。 |
| magic/version/header 错误 | Linux 丢弃 slot、记录原始字段和统计；连续阈值 TBD 后请求重新同步。 |
| 序号跳变 | 记录 gap/duplicate/out-of-order；允许启动、复位和 32-bit 回绕造成的不连续；其他跳变计入 drop。 |
| CRC 错误 | 若 CRC 有效，丢弃、不解码、不送 RKNN；回收 slot，保留计数。CRC 算法冻结前只可标为未验证。 |
| JPEG SOI/EOI 错误 | 丢弃，不送解码器/RKNN；记录协议或编码错误。仅 SOI/EOI 不能替代完整 JPEG 解码校验。 |
| FPGA 覆盖未读帧 | 违反所有权；置粘滞错误，Linux 停止接收并执行重新同步。禁止静默覆盖 `READY/READING`。 |
| Linux 消费过慢 | 使用下节选定的丢帧策略；记录队列深度、高水位、丢弃原因和 sequence gap。 |
| PCIe 复位/设备下线 | 中止在途 DMA，所有本地 slot 标无效；重新发现设备/BAR/节点，重新读取版本与 capability，清空索引后再启动。禁止复用旧 BDF/BAR/FD。 |
| 超时/重新同步 | 无 READY 或 DMA/状态停滞超时阈值均 TBD。停止提交、读取状态/错误；若无进展，执行双方约定的软复位或重新枚举流程，从已确认 EMPTY 基线重新开始。 |

背压策略比较：

| 策略 | 特性 | v0.1 取向 |
|---|---|---|
| 阻塞/暂停 FPGA 上游 | 尽量不丢帧，但会把背压传播到编码/采集链路，可能需要帧缓存。 | 仅硬件确认可安全暂停后使用。 |
| 丢弃最新帧 | 保留较早队列内容，端到端延迟可能上升。 | 不推荐实时推理默认使用。 |
| 丢弃最旧未读 READY 帧 | 优先低延迟，但若覆盖 READY 则须显式撤销所有权和计数。 | 不在 v0.1 默认采用，除非状态机扩展。 |
| 不覆盖，只在无 EMPTY 时丢弃当前新帧 | 所有权简单、不会破坏 Linux 正在读取的数据；可能产生 sequence gap。 | **v0.1 推荐（DRAFT）**：FPGA 在无 EMPTY 时丢当前新帧并计数，Linux 通过序号/状态观测。 |

## 8. 分阶段实现与验收门

1. **固定测试数据 DMA**：确认 RC/EP 枚举、动态 BAR/节点发现、C2H 完成长度与基础错误读数；不假定 PCIe 代际。
2. **单帧 JPEG**：发送一帧含 DRAFT header 的已知 JPEG；校验 header、长度、SOI/EOI、解码结果。
3. **多 slot 连续传输**：实现 `EMPTY/WRITING/READY/READING`、回收、序号、超长和消费慢统计。
4. **JPEG 解码**：对合法与损坏帧分别验证解码、丢弃和资源释放。
5. **RKNN 推理**：建立 decoded image 到模型输入，并以 `frame_sequence/timestamp` 关联结果。
6. **中断与性能优化**：比较轮询与经实测可用的 MSI/MSI-X/events；测量吞吐、CPU、延迟、丢帧与恢复。
7. **可选 V4L2 MJPEG**：只有在 JPEG 兼容性、`bytesused`、帧边界和错误语义被正确实现后评估；不得伪装为 RGB24。

## 9. FPGA 队友必须确认的问题

1. 实际 PCIe IP 的 EP 配置、Vendor/Device ID、BAR 数量/大小/用途、C2H 通道、AXI-Stream 位宽与时钟域是什么？
2. 真实协商的 PCIe speed/width、复位/PERST# 时序、链路重训与 RC/EP 上电时序如何测得？（不要预设 2.0 或 3.0。）
3. JPEG 是否是标准可解码 JPEG？其编码模式、采样格式、质量、SOI/EOI、最大/典型长度和最坏延迟是多少？
4. header、payload 和 `tlast/EOP` 的严格发生顺序是什么？一帧可否跨 descriptor/read？C2H 实际完成长度能否可靠对应一帧？
5. slot 存储位置、容量、数量、stride、DMA 对齐、首地址/访问模型和所有权跨时钟域同步如何实现？
6. `frame_ready`、producer/consumer 索引、slot metadata 窗口、写清除和 memory ordering 的 RTL 定义是什么？
7. 无 EMPTY 时是否安全暂停上游？若不能，是否接受“丢当前新帧且绝不覆盖未读 slot”的默认策略？各类丢帧计数在哪里导出？
8. CRC 算法/覆盖范围、timestamp 时钟源/单位、frame sequence 初值/回绕和复位语义如何冻结？
9. MSI/MSI-X/user IRQ 是否由该 IP/RTL 支持、哪一事件触发、如何确认/去重？第一版轮询时应如何屏蔽？
10. PCIe 复位、SGDMA 错误、编码失败、超长、错误 EOP 和 FPGA 内部复位后，哪些寄存器/状态会清零，Linux 的重新同步入口是什么？
