# FPGA—RK3576 PCIe接口与数据传输协议总结

> 项目：2026安路FPGA创新设计大赛——选题三“基于FPGA的图像采集压缩与智能预处理加速系统设计”  
> 应用方向：车载与便携智能终端  
> 整理日期：2026-09-14  
> 文档性质：团队接口设计基线。标记为“建议值”或“待确认”的内容仍需联调后冻结。

## 1. 结论摘要

团队当前PCIe接口方案合理，可以按以下结论继续开发：

1. RK3576作为PCIe Root Complex（RC），PH1A90 FPGA作为PCIe Endpoint（EP）。
2. 官方PCIe SGDMA工程可以作为EP、PCIe PHY、SGDMA、AXI-Stream、AXI-Lite BAR及Linux驱动的基线，但不能原样作为最终图像系统。
3. JPEG数据通过C2H0，以128位AXI-Stream送入SGDMA，再由SGDMA写入RK3576侧DDR。
4. FPGA应用逻辑不管理RK3576侧DDR地址。Linux驱动负责分配接收内存、DMA映射和SGDMA描述符；FPGA只管理自身DDR地址和slot。
5. 首版使用轮询完成DMA联调，暂不要求MSI/MSI-X；该选择不改变AXI-Stream数据握手机制。
6. FPGA侧协议规划4个JPEG slot：早期只启用1个，连续传输先实现2个乒乓缓冲，稳定后扩展到4个。
7. 建议每个slot的JPEG payload容量为16 MiB，另加64字节帧头。16 MiB是协议容量上限，不是持续传输时允许每帧都达到的大小。
8. 正在发送的slot必须禁止覆盖。缓存满时，可以覆盖最旧的`READY`帧，但不能覆盖`FILLING`或`SENDING`帧。
9. BAR编号、操作系统分配的BAR基址和寄存器偏移不能散落硬编码；双方用一份带版本号的协议文档和共享头文件统一。

## 2. 系统数据流

规划的数据流如下：

```text
摄像头
  │  官方FMC摄像头转接板上的MIPI CSI-2链路
  ▼
FPGA采集与ISP/智能预处理
  ▼
FPGA侧JPEG压缩
  ▼
FPGA DDR中的JPEG slot
  ▼
DDR读出器 + 64字节帧头
  ▼
C2H0 128-bit AXI-Stream
  ▼
官方SGDMA IP / PCIe EP
  ▼
PCIe x1
  ▼
RK3576 PCIe RC
  ▼
Linux驱动分配的RK侧DMA缓冲区
  ▼
上层图像/AI处理
```

摄像头协议本身是MIPI CSI-2；FMC是承载摄像头扩展板的物理连接器。开发板FMC引脚并非可任意替换的通用摄像头定义，使用其他FMC板前必须核对引脚和电压。

## 3. 官方SGDMA工程的可复用范围

### 3.1 已确认可复用的部分

官方异构例程已经采用以下角色和接口：

- FPGA作为PCIe EP；
- RK3576作为PCIe RC；
- 物理链路宽度配置为x1；
- PCIe用户时钟为125 MHz；
- SGDMA数据接口宽度为128位；
- 启用一个C2H通道和一个H2C通道；
- 数据面启用AXI-Stream；
- 控制面启用AXI4-Lite Master/User BAR；
- 普通描述符模式下，Linux驱动负责SGDMA描述符和RK侧DMA地址。

因此，官方工程适合作为以下内容的基线：

- PCIe EP及PHY配置；
- 链路训练、复位和用户时钟；
- SGDMA C2H0/H2C0；
- Linux PCIe/SGDMA驱动；
- BAR到FPGA用户AXI4-Lite寄存器的访问；
- MSI能力的保留，供后续升级。

### 3.2 不能直接沿用的应用部分

官方摄像头例程当前采用摄像头视频流加小容量FIFO后直送SGDMA，未实现本项目需要的：

- FPGA DDR帧缓存；
- 可变长度JPEG slot；
- slot所有权管理；
- JPEG帧头和元数据协议；
- 精确的尾拍`TKEEP`；
- 连续传输期间的完整帧保护；
- 满缓存时的可配置丢帧策略。

官方例程中的FIFO约为32 KiB，只适合吸收很短的瞬时反压，不能替代DDR帧缓存。最终工程应保留PCIe/SGDMA基础设施，替换或重构视频数据源部分。

## 4. PCIe链路与带宽判断

### 4.1 链路速率

软件和协议首先按“x1链路、运行时检测协商速率”设计，不在代码中假定PCIe 2.0或3.0。接板后使用：

```bash
lspci -vv
```

检查`LnkCap`和`LnkSta`：

- `5GT/s, Width x1`表示PCIe Gen2 x1；
- `8GT/s, Width x1`表示PCIe Gen3 x1。

以当前RK3576J内部PCIe 2.0 x1理解，理论单向有效数据上限约500 MB/s；官方测试工具给出的工程参考有效带宽约350～420 MB/s。最终数字必须在实板上测试。

### 4.2 FPGA内部AXI-Stream宽度

128位、125 MHz AXI-Stream的理论内部吞吐量为：

```text
128 bit × 125 MHz ÷ 8 = 2000 MB/s
```

因此内部AXI-Stream接口宽度不是PCIe x1链路的瓶颈。增加C2H通道数量不会增加x1物理链路总带宽，一个C2H0足以覆盖当前链路能力。

### 4.3 视频数据规模

未压缩RGB24的近似数据率：

```text
1920 × 1080 × 3 × 60 ≈ 373 MB/s
3840 × 2160 × 3 × 30 ≈ 747 MB/s
```

结论：

- 1080p60原始RGB24已经接近Gen2 x1实用带宽边缘；
- 4K30原始RGB24无法通过Gen2 x1持续传输；
- 将JPEG压缩放在FPGA侧是必要的，不只是附加功能。

若按350 MB/s实测带宽并保留约30%余量，1080p60连续模式建议把平均JPEG大小控制在约4 MiB/帧以内：

```text
4 MiB/帧 × 60帧/秒 ≈ 240 MiB/s
```

这里的约4 MiB/帧是平均带宽目标；16 MiB是单帧slot容量上限，两者不能混淆。

## 5. FPGA、SGDMA和Linux的职责边界

### 5.1 FPGA应用逻辑负责

- FPGA侧DDR地址和slot布局；
- JPEG写入、长度统计和超长检测；
- slot状态与所有权；
- 选择待发送帧；
- 构造帧头；
- 输出C2H0的`TDATA/TVALID/TKEEP/TLAST`；
- 在`TREADY=0`时保持数据和状态稳定；
- 帧序号、丢帧、溢出和错误计数；
- BAR用户寄存器的应用层定义。

### 5.2 SGDMA IP负责

- 从Linux配置的描述符中取得RK侧目标DMA地址；
- 接收FPGA的AXI-Stream；
- 将数据转换成PCIe Memory Write事务；
- 维护DMA通道状态；
- 提供`TREADY`反压；
- 产生完成状态或中断条件。

### 5.3 Linux驱动负责

- PCIe设备枚举及BAR映射；
- 分配或固定RK侧接收缓冲区；
- DMA映射，获得DMA地址或IOVA；
- 构造并提交SGDMA描述符；
- 启动C2H0；
- 轮询或通过MSI/MSI-X等待DMA完成；
- 获得实际传输长度；
- 校验帧头、长度、帧序号和可选CRC；
- 将RK侧内存中的JPEG交给上层AI模块。

### 5.4 FPGA不管理RK侧DDR地址

普通SGDMA描述符模式的数据路径为：

```text
FPGA DDR地址/slot（FPGA管理）
        ↓
AXI-Stream
        ↓
SGDMA
        ↓
RK侧DMA地址/IOVA（Linux驱动管理）
```

FPGA不应硬编码RK3576物理DDR地址。启用IOMMU时，设备使用的地址还可能是IOVA而非物理地址。

只有在启用描述符旁路、改为自定义DMA或其他AXI-MM架构时，FPGA才可能需要参与目的地址管理。当前官方工程的C2H描述符旁路宏未启用，不采用这种方式。

## 6. C2H0 AXI-Stream发送协议

官方SGDMA中，FPGA向主机发送数据的端口命名为`s0_axis_c2h_*`。对FPGA应用而言，它是一个AXI-Stream输出源。

### 6.1 关键条件

建议定义：

```text
start_allowed = user_rst_n
             && user_link_up
             && app_enable
             && c2h_running
             && ready_slot_exists
             && tx_idle

beat_fire     = TVALID && TREADY
frame_done    = TVALID && TREADY && TLAST
```

`start_allowed`不包含瞬时`TREADY`。选定完整帧后，AXI-Stream源应主动拉高`TVALID`，不能等待`TREADY`先拉高，否则可能形成握手依赖。

### 6.2 各信号含义和来源

| 信号 | 来源 | 含义 | Linux是否直接写入 |
|---|---|---|---|
| `user_rst_n` | PCIe/SGDMA子系统 | PCIe用户逻辑复位释放 | 否 |
| `user_link_up` | PCIe IP核 | PCIe链路训练完成 | 否 |
| `app_enable` | 自定义BAR控制寄存器 | 允许应用开始采集/发送 | 建议由Linux写入 |
| `c2h_running` | 建议由`c2h_sts_0[6]`派生 | C2H0通道处于运行状态 | Linux提交DMA后间接影响 |
| `TREADY` | SGDMA输出 | 当前拍是否可以被接收 | 否，属于硬件反压 |
| `TVALID` | FPGA应用输出 | 当前拍数据有效 | FPGA产生 |
| `TLAST` | FPGA应用输出 | 当前帧最后一拍 | FPGA产生 |
| `TKEEP[15:0]` | FPGA应用输出 | 当前128位中哪些字节有效 | FPGA产生 |

`user_link_up=1`只说明PCIe链路建立，并不说明Linux已经准备好DMA接收缓冲区。

`c2h_running=1`说明通道已启动，但也不保证每一拍都能接收。每一拍是否真正完成传输，只看`TVALID && TREADY`。

### 6.3 发送时必须遵守的规则

1. 发送开始时锁存`tx_slot_id、tx_base_addr、tx_total_length、tx_sequence`，整帧发送期间不能切换到更新帧。
2. 只有`TVALID && TREADY`时，DDR读地址、已发送字节数和CRC才能前进。
3. 当`TVALID=1 && TREADY=0`时，必须保持`TDATA、TKEEP、TLAST、TVALID`以及当前slot不变。
4. `TLAST`只能出现在“64字节帧头+实际JPEG payload”的最后一拍。
5. 最后一拍不足16字节时，必须生成精确的`TKEEP[15:0]`，不能始终置为全1。
6. 不依赖`TUSER`传递关键元数据，因为Linux驱动不一定向应用层保留`TUSER`；关键字段放入64字节帧头。
7. DDR读端与SGDMA之间建议加入小型FIFO或skid buffer。如果DDR UI时钟与PCIe `user_clk`不同，必须使用异步FIFO完成CDC。
8. 只有`frame_done`发生后，当前slot才能从`SENDING`释放。

### 6.4 `TREADY=0`不能说明具体原因

`TREADY`可能在帧间或帧中途拉低，原因包括：

- Linux尚未提交可用DMA描述符；
- SGDMA内部FIFO暂时满；
- PCIe流控信用不足；
- 描述符边界或内部调度；
- 链路复位或错误。

FPGA不需要根据`TREADY`推断具体原因来保证正确性，只需要遵守AXI-Stream保持规则。诊断时可结合：

- `user_link_up=0`：链路未建立或已掉线；
- `user_link_up=1`且`c2h_running=0`：通道没有运行；
- `c2h_running=1`且`TREADY=0`：运行中的暂时反压；
- FPGA自己的`tx_busy`和`bytes_sent`：判断是否停在帧中途。

## 7. JPEG slot设计

### 7.1 建议容量

FPGA侧DDR容量约为256 MiB。建议协议规划：

- `SLOT_COUNT = 4`；
- `MAX_PAYLOAD = 16 MiB`；
- `HEADER_LENGTH = 64 B`；
- JPEG slot占用约64 MiB，另外预留少量对齐和描述信息空间。

阶段使用方式：

| 阶段 | 实际启用slot | 目的 |
|---|---:|---|
| 固定测试数据 | 1 | 打通PCIe、SGDMA和协议 |
| 单帧JPEG | 1 | 验证长度、帧头、TLAST和JPEG完整性 |
| 连续传输首版 | 2 | 乒乓缓冲 |
| 稳定连续版本 | 4 | 吸收Linux调度和PCIe短时抖动 |

16 MiB是1080p首版的协议建议上限，不是JPEG格式的数学最坏上限。若后续正式支持4K，应根据编码器质量范围和实测最大码流重新评估16 MiB是否足够，必要时提升为32 MiB或明确拒绝超长帧。

### 7.2 slot状态机

每个slot至少有以下状态：

| 状态 | 含义 | 是否允许覆盖 |
|---|---|---:|
| `FREE` | 没有有效帧 | 是 |
| `FILLING` | JPEG编码器正在写入 | 否 |
| `READY` | 完整帧已写入，等待发送 | 满缓存时可作为丢弃对象 |
| `SENDING` | C2H发送器正在读取 | 绝对不允许 |
| `ERROR` | 当前slot存在超长或其他错误 | 按策略回收 |

正常状态转换：

```text
FREE → FILLING → READY → SENDING → FREE
```

发布帧时必须先完成payload和元数据写入，最后再把状态改为`READY`。这样发送器不会看到只写了一半的JPEG。

### 7.3 满缓存与覆盖策略

允许“发送最新帧、覆盖最旧帧”，但必须满足：

- 优先使用`FREE` slot；
- 没有`FREE`时，只能选择最旧的`READY` slot覆盖；
- 覆盖前先将旧slot从`READY`改为`FILLING/INVALID`并增加`drop_count`；
- 永远不覆盖`SENDING`；
- 永远不覆盖仍在写入的`FILLING`；
- 如果没有可覆盖的`READY`，只能丢弃新输入帧。

建议提供两种可配置模式：

- 顺序模式：发送最旧的`READY`帧，正常情况下尽量不丢帧，适合比赛指标测试；
- 低延迟模式：发送最新的`READY`帧，同时释放并统计比它更旧的等待帧，适合车载实时预览和AI。

低延迟模式下若选择最新帧，必须同时丢弃更旧的`READY`帧，不能随后再发送旧帧，否则会造成`frame_sequence`倒退。

### 7.4 “Linux读取期间暂停覆盖slot”的准确含义

Linux不会直接锁住FPGA DDR，也不需要主动发出“暂停覆盖”命令。准确要求是：

> 当FPGA发送器认领某个slot后，将其标记为`SENDING`；即使`TREADY`中途拉低，也不允许JPEG写端覆盖该slot，直到最后一拍握手完成。

如果发送前半帧后覆盖当前slot，Linux会收到“旧帧前半部分+新帧后半部分”的撕裂JPEG。

普通流式SGDMA模式下，最后一拍被SGDMA接收后，RK侧已经拥有或正在完成其内部传输的数据副本，FPGA slot可以按首版策略复用。Linux后续AI处理的是RK侧内存，不再占用FPGA slot。

若将来要求DMA错误后重传，可增加`WAIT_ACK`状态，让Linux完成DMA并校验CRC后通过BAR确认消费；首版不要求该机制。

## 8. 建议的帧数据格式

建议每次C2H传输对应一帧，数据格式为：

```text
[固定64字节帧头][payload_length字节JPEG payload]
```

多字节字段统一使用小端格式。以下布局为协议草案，可在双方协议评审时调整，但冻结后必须带版本号：

| 偏移 | 长度 | 字段 | 说明 |
|---:|---:|---|---|
| `0x00` | 4 | `magic` | 固定魔数，用于帧同步和错误检测 |
| `0x04` | 2 | `protocol_version` | 协议版本 |
| `0x06` | 2 | `header_length` | 当前固定为64 |
| `0x08` | 4 | `frame_sequence` | 单调递增，允许Linux发现丢帧 |
| `0x0C` | 4 | `payload_length` | JPEG有效字节数，不含帧头 |
| `0x10` | 2 | `width` | 图像宽度 |
| `0x12` | 2 | `height` | 图像高度 |
| `0x14` | 1 | `pixel_format` | JPEG解码后的像素格式约定 |
| `0x15` | 1 | `compression` | JPEG类型/编码模式 |
| `0x16` | 1 | `quality` | JPEG质量参数，没有则置0 |
| `0x17` | 1 | `flags` | bit0可定义为`FRAME_VALID`，其余保留 |
| `0x18` | 8 | `timestamp_ns` | 可选采集时间戳，没有则置0 |
| `0x20` | 4 | `status` | 本帧状态位 |
| `0x24` | 4 | `error_code` | 本帧错误码，正常为0 |
| `0x28` | 2 | `slot_id` | FPGA源slot编号，仅用于诊断 |
| `0x2A` | 2 | `reserved0` | 置0 |
| `0x2C` | 4 | `payload_crc32` | 可选JPEG CRC32，未启用则置0 |
| `0x30` | 16 | `reserved1` | 置0，供后续扩展 |

`frame_ready`更适合作为FPGA内部slot状态及BAR中的`READY_MASK`，而不是已发送帧头中的动态所有权字段。为满足“每帧有效”语义，帧头可设置`flags.FRAME_VALID=1`；真正用于发送前判断的是BAR/内部的slot `READY`状态。

Linux接收缓冲区应至少能容纳：

```text
HEADER_LENGTH + MAX_PAYLOAD
```

流式C2H建议启用EOP/`TLAST`结束机制，让驱动返回实际传输长度。Linux还应检查：

```text
actual_dma_length == header_length + payload_length
payload_length <= max_payload
frame_sequence符合预期
magic和protocol_version正确
可选CRC正确
```

## 9. BAR控制面协议

### 9.1 BAR访问路径

Linux控制FPGA应用寄存器也是通过PCIe：

```text
Linux readl()/writel()或受控mmap
        ↓
RK3576 PCIe RC
        ↓
PCIe Memory Read/Write TLP
        ↓
FPGA EP的BAR译码
        ↓
m_axil_* AXI4-Lite
        ↓
FPGA用户寄存器
```

`user_link_up`不是Linux写入的寄存器，而是PCIe IP产生的链路状态。`app_enable`是自定义控制位，建议由Linux通过用户BAR写入。`c2h_running`来自SGDMA通道状态，Linux提交并启动DMA后间接影响它。

### 9.2 建议的寄存器集合

当前先约定寄存器语义，不在各自代码中分散写死偏移。建议至少包含：

| 符号名 | 方向 | 用途 |
|---|---|---|
| `DEVICE_MAGIC` | FPGA→Linux | 识别正确设备/逻辑版本 |
| `PROTOCOL_VERSION` | FPGA→Linux | 协议兼容检查 |
| `CAPABILITIES` | FPGA→Linux | 支持的格式、CRC、中断等能力 |
| `SLOT_COUNT` | FPGA→Linux | 当前实现的slot数量 |
| `MAX_PAYLOAD` | FPGA→Linux | 单帧payload容量上限 |
| `HEADER_LENGTH` | FPGA→Linux | 帧头长度 |
| `CONTROL` | Linux→FPGA | `APP_ENABLE`、`SOFT_RESET`、模式选择 |
| `STATUS` | FPGA→Linux | 链路、C2H、TX busy和全局错误 |
| `SLOT_READY_MASK` | FPGA→Linux | 哪些slot为`READY` |
| `SLOT_SENDING_MASK` | FPGA→Linux | 哪些slot正在发送 |
| `PRODUCER_SEQUENCE` | FPGA→Linux | 最新产生的帧序号 |
| `CONSUMED_SEQUENCE` | FPGA→Linux | 最近成功发送的帧序号 |
| `DROP_COUNT` | FPGA→Linux | 被丢弃/覆盖的完整帧数 |
| `OVERFLOW_COUNT` | FPGA→Linux | JPEG超长或无slot次数 |
| `DMA_ERROR_COUNT` | FPGA→Linux | 发送超时/链路异常次数 |
| `LAST_ERROR` | FPGA→Linux | 最近一次错误码 |

如果实现逐slot元数据寄存器，还可增加每个slot的`SEQUENCE、PAYLOAD_LENGTH、WIDTH、HEIGHT、STATUS`。但首版已有in-band帧头时，不必复制所有字段，BAR主要用于启动、能力发现和诊断。

### 9.3 BAR地址规则

- FPGA逻辑只解码BAR内偏移，不知道Linux给BAR分配的绝对地址；
- Linux通过PCIe枚举和驱动动态获得BAR基址；
- 调试脚本中的固定物理地址只能临时使用，不能作为正式协议；
- 用户BAR与SGDMA配置BAR职责分离：用户BAR服务应用寄存器，配置BAR由SGDMA驱动管理；
- 双方应共享同一份寄存器定义和协议版本，避免各自维护不同常量。

## 10. 轮询、MSI和MSI-X

轮询与MSI/MSI-X解决的是“Linux CPU如何知道DMA已完成”，不是AXI-Stream数据传输本身。

- 轮询：Linux驱动反复检查SGDMA完成状态；实现简单，但占用更多CPU；
- MSI：PCIe设备以消息形式向CPU报告中断；
- MSI-X：提供更多可独立屏蔽和路由的中断向量，多通道时更有优势。

无论选择哪一种，FPGA数据面始终遵守：

```text
只有TVALID && TREADY时，当前拍才完成传输。
```

官方部署脚本当前使用`poll_mode=1`，表示驱动采用完成状态轮询并跳过MSI/MSI-X初始化。它不等于用户程序必须先反复读取`frame_ready`，也不等于FPGA可以忽略`TREADY`。

建议：

1. 首版保持IP中的MSI能力，但Linux使用轮询完成固定数据和单帧JPEG联调；
2. 功能稳定后切换MSI，减少CPU占用；
3. 当前只有一个C2H通道，没有立即使用MSI-X的必要。

## 11. 推荐启动与停止顺序

### 11.1 启动

1. FPGA和RK上电，PCIe完成链路训练；
2. Linux使用`lspci -vv`确认速率和x1宽度；
3. 加载SGDMA驱动并动态映射BAR；
4. Linux读取`DEVICE_MAGIC/PROTOCOL_VERSION/CAPABILITIES`；
5. Linux准备至少一个足够大的C2H接收缓冲区并提交DMA；
6. SGDMA C2H0进入运行状态；
7. Linux通过用户BAR写`APP_ENABLE=1`；
8. FPGA开始采集、压缩、写slot并发送完整JPEG帧。

最终连续版本建议Linux持续预提交多个RK侧接收缓冲区，使C2H0尽量不断流。Linux/AI处理RK侧已完成缓冲区，与FPGA slot生命周期解耦。

### 11.2 停止

1. Linux写`APP_ENABLE=0`，禁止产生新的待发送帧；
2. FPGA完成或按协议终止当前帧；
3. Linux等待`TX_IDLE`或DMA超时；
4. Linux停止C2H通道并释放DMA缓冲区；
5. 必要时执行应用软复位。

## 12. 分阶段实施计划

### 阶段0：验证官方基线

- 尽量不改官方PCIe工程；
- `lspci -vv`确认设备、链路速率和x1宽度；
- 确认设备节点和BAR可访问；
- 运行H2C/C2H大块数据测速；
- 记录持续吞吐量、短时最低吞吐量和错误率。

### 阶段1：固定测试数据

- FPGA产生确定性测试数据；
- 使用64字节帧头；
- 单slot；
- 测试长度至少包括：1、15、16、17、最大值减1、最大值及随机长度；
- 验证最后一拍`TKEEP`、`TLAST`和实际DMA长度；
- 对Linux收到的数据计算CRC/SHA并比对。

### 阶段2：单帧JPEG

- 从ROM或FPGA DDR发送一张已知JPEG；
- 验证SOI/EOI、长度和CRC；
- Linux保存并解码图像；
- 人为延迟Linux接收，验证`TREADY`反压不会破坏帧。

### 阶段3：双缓冲连续传输

- 实现2个slot乒乓；
- 一边JPEG写入，一边DDR读出/C2H发送；
- 统计帧序号、丢帧、超长和DMA错误；
- 验证发送中的slot不会被覆盖。

### 阶段4：4-slot与低延迟策略

- 扩展为4个slot；
- 实现顺序模式和最新帧模式；
- Linux持续预提交多个DMA接收缓冲区；
- 验证1080p60长期运行、延迟、吞吐量和丢帧率。

### 阶段5：中断与性能优化

- 从轮询切换MSI；
- 测量CPU占用和端到端延迟；
- 根据实测调整JPEG质量、平均码率和slot数量；
- 只有出现明确的多向量需求时再考虑MSI-X。

## 13. 异常处理建议

| 异常 | FPGA侧动作 | Linux侧动作 |
|---|---|---|
| `payload_length > MAX_PAYLOAD` | 不发布`READY`或标记`ERROR`，增加溢出计数 | 读取错误计数并记录 |
| 所有slot均忙 | 按模式覆盖最旧`READY`或丢弃新帧 | 通过序号和计数获知丢帧 |
| `TREADY`短时为0 | 保持当前拍和slot状态 | 无需特殊处理 |
| `TREADY`长期为0 | 保持数据，达到超时阈值后进入错误恢复 | 检查描述符、驱动和链路 |
| `user_link_up`中途掉线 | 中止当前发送，不记成功，slot进入`ERROR`或回收 | 重新枚举/重置驱动 |
| DMA长度不匹配 | 记录错误，不把该帧交给AI | 丢弃缓冲区并记录诊断 |
| CRC错误 | 可记录并继续下一帧 | 丢弃帧并统计 |

首版对链路中途断开可以直接丢弃当前帧，不必自动重传；自动重传需要Linux ACK和更复杂的slot保留协议。

## 14. 双方当前需要确认的四个问题

### 14.1 官方SGDMA工程能否直接作为EP基线

可以作为EP和SGDMA基础工程，但不能把其现有摄像头直通应用直接当作最终实现。保留PCIe/SGDMA/驱动，新增或替换DDR slot、JPEG帧协议和发送控制。

### 14.2 FPGA侧能提供几个缓存slot

协议规划4个；固定测试数据和单帧阶段用1个，连续传输第一版用2个，最终启用4个。

### 14.3 单帧JPEG最大可能长度

首版协议建议限定`MAX_PAYLOAD=16 MiB`。超过上限的帧必须报告错误并丢弃，不能跨slot写入。该值需要在JPEG编码器、分辨率和质量参数确定后通过压力图像实测复核；正式4K支持时重新评估。

### 14.4 Linux读取期间能否暂停覆盖该slot

可以保证不覆盖，但不是Linux直接锁定DDR。FPGA发送器将当前slot标记为`SENDING`，直到`TVALID && TREADY && TLAST`完成才释放；满缓存时只能覆盖最旧的`READY` slot。

## 15. 尚未冻结的协议事项

以下内容需要FPGA和Linux双方共同评审后冻结：

- 用户BAR编号及寄存器具体偏移；
- `magic`数值和协议版本初值；
- `status/error_code`位定义；
- JPEG像素格式、色彩空间和质量字段定义；
- 是否启用CRC32及其多项式、初值和覆盖范围；
- Linux一次C2H调用的缓冲区大小和超时；
- 轮询接口是驱动内部完成轮询，还是额外提供用户态状态查询；
- 最终使用2个还是4个活跃slot；
- 顺序模式与低延迟模式的切换方式；
- 链路/DMA异常后丢帧、重试或复位策略；
- 4K版本的`MAX_PAYLOAD`和可持续帧率。

## 16. 联调验收清单

- [ ] RK3576枚举到FPGA EP；
- [ ] `lspci -vv`显示正确的协商速率和`Width x1`；
- [ ] Linux驱动可动态映射用户BAR和SGDMA配置BAR；
- [ ] Linux能读出正确的设备魔数、协议版本和能力；
- [ ] Linux写`APP_ENABLE`后FPGA状态变化正确；
- [ ] 固定测试数据逐字节一致；
- [ ] 1、15、16、17等非整拍长度的`TKEEP`正确；
- [ ] `TLAST`对应实际帧末尾；
- [ ] 单帧JPEG可以保存并正确解码；
- [ ] `actual_dma_length == 64 + payload_length`；
- [ ] 人为制造`TREADY`停顿时，输出数据和DDR地址保持稳定；
- [ ] 发送中slot不会被JPEG写端覆盖；
- [ ] 缓存满时只覆盖`READY`，不覆盖`FILLING/SENDING`；
- [ ] `frame_sequence`可以准确反映丢帧；
- [ ] 超长帧、DMA超时、链路断开均有计数和错误状态；
- [ ] 长时间1080p60测试达到目标吞吐量、延迟和丢帧率；
- [ ] 轮询版本稳定后，再比较MSI版本的CPU占用和延迟。

## 17. 官方工程证据路径（相对工作区）

以下路径用于换电脑后继续核对，均相对于本项目工作区：

- 竞赛题目：`doc/2026安路FPGA赛题.pdf`
- PCIe异构教程：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/米联客2026版异构AFC03教程-PCIE篇.pdf`
- 工程顶层：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/uisrc/01_rtl/imx415_pcie_top.v`
- 编译功能宏：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/uisrc/01_rtl/para_def.vh`
- SGDMA子系统端口：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/uisrc/03_ip/sgdma/sgdma_subsys.v`
- SGDMA应用状态逻辑：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/uisrc/03_ip/sgdma/sgdma_app/src/sgdma_app.v`
- Linux SGDMA核心驱动：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/deploy/sgdma_drv/anlogic_pci_lib.c`
- Linux SGDMA字符设备：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/deploy/sgdma_drv/cdev_sgdma.c`
- BAR控制字符设备：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/deploy/sgdma_drv/cdev_ctrl.c`
- 部署脚本：`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/deploy/pcie_setup.sh`

## 18. 文档验证边界

本文件总结的是已阅读的官方资料、现有工程接口和团队讨论形成的架构决策。当前尚未对拟新增的DDR slot/JPEG发送RTL执行编译、AST、可读性、注释、命名、profile、testbench或TD工具链验证；相关状态均为“未运行”。当接口冻结并开始实现RTL后，应分别进行仿真、反压测试、TD综合布局布线及实板带宽验证。
