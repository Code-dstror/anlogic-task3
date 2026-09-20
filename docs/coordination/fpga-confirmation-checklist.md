# FPGA → Linux transport 精确确认清单

- 状态：**Awaiting FPGA owner confirmation**；本文不是已接受协议或 ADR。
- 目的：集中记录 Linux 接收端、FPGA 数据路径和联调必须共同冻结的合同，并让 FPGA owner 逐项提供精确答案、版本关联和可复现证据。
- 职责边界：按[工作流职责边界](workstream-ownership.md)执行。FPGA owner 负责 PCIe EP、SGDMA、slot/BAR/IRQ、FPGA 协议与 reset 实现；Linux owner 消费已确认合同并实现 transport。本文不重新分配职责。
- 填写规则：仅 FPGA owner 或双方评审后可改变单项状态；未确认时不得以课程示例、推测或目标参数代填。
- 关联：[最新 Linux checkpoint](../context/linux-transport-workstream-checkpoint-2026-09-14.md)、[PCIe JPEG 协议草案](../../interface/pcie-jpeg-protocol-v0.1.md)、[Linux MVP roadmap](../plans/linux-mvp-roadmap.md)、[ADR 0003](../decisions/0003-linux-lifecycle-runner-event-policy.md)。协议草案中的字段、状态名和寄存器仅为 DRAFT，不能因被引用而成为本清单的确认答案。

## 状态词与非冻结规则

| 状态 | 定义 | 对 Linux 的含义 |
|---|---|---|
| `TBD` | 尚未给出可实现的精确答案。 | 不得猜测或实现固定硬件行为。 |
| `Proposed` | 候选设计、目标或预算。 | 不允许 Linux 代码据此写死常量、布局、状态机或恢复行为。 |
| `Confirmed` | FPGA owner 已给出精确答案，关联 RTL、bitstream、IP 或寄存器/头部规范版本，精度足以让 Linux 无需猜测地实现。 | 可解除相应“开始实现”门禁，但仍须按版本核对。 |
| `Tested` | 在 `Confirmed` 基础上，已在 MLK-AFH03-AFC03/RK3576 实机验证，并附可复现命令、日志、dump、测试条件和版本。 | 对依赖实际硬件行为的集成/发布项，`Confirmed` 之外还须达到此状态。 |

- `Confirmed` 不等于 `Tested`；文档整体状态也不能替代每个 Question ID 的独立状态。
- 任何仍为 `TBD` 或 `Proposed` 的字段不得进入固定真实 FPGA ABI 的 `TransportRecordValidator`、真实 `SgdmaFrameSource` 或自动恢复的固定实现。
- 如果 `Confirmed` 答案关联的 RTL、bitstream、IP、寄存器表或 header 规范版本变化，该问题必须退回 `TBD`（待复核）；旧证据不能自动适用于新 bitstream。
- 精确合同达到 `Confirmed` 后可以解除相应开始实现门禁；需要硬件行为保证的项目必须在系统集成/发布前达到 `Tested`。
- 示例状态名（如 `EMPTY`、`WRITING`、`READY`、`READING`）只用于说明必须由 FPGA owner 提供实际等价值；它们不是既定 FPGA 实现要求。

## 填写规则与证据位置

每一项均为独立可填写项：`当前状态` 初始为 `TBD`，回答初始为 `TBD`。回答不得只写“支持”“应该可以”或“参考官方工程”；必须给出精确字段和证据。没有精确版本/证据的口头结论仍是 `TBD` 或 `Proposed`。

原 P0/P1/P2 表保留既有 Question ID 和优先级，以保持已有讨论可追踪。下方“精确确认补充”以带后缀的稳定子问题 ID 扩展其回答要求；每个子问题都包含当前状态、FPGA owner 必须提供的精确答案、Linux 为什么需要、所需版本/证据，以及初始为 `TBD` 的回答位置。

## P0：Linux 接收程序设计前必须确认

| 编号 | 优先级 | 问题 / 为什么需要确认 | FPGA 队友回答 | 当前状态 | 对 Linux 实现的影响 |
|---|---|---|---|---|---|
| P0-01 | P0 | **摄像头到 FPGA 的物理连接是什么？** 板载 J8/J9 已知接 RK CSI，不能据此假定 FPGA 已有传感器入口。 | （待 FPGA 队友填写） | TBD | 决定采集链路是否可实施、何时能有真实输入及调试边界。 |
| P0-02 | P0 | **传感器型号、MIPI lane、时钟、I2C、复位和供电如何连接与配置？** 这些决定 FPGA CSI/IP 与传感器初始化，现无实机确认。 | （待 FPGA 队友填写） | TBD | 决定 Linux 可期待的分辨率/格式元数据、启动顺序和联调测试条件。 |
| P0-03 | P0 | **FPGA 图像处理和 JPEG 编码职责/流水顺序是什么？** 赛题要求三项硬件预处理和硬件压缩，但具体输入输出未冻结。 | （待 FPGA 队友填写） | TBD | 决定 Linux 解码后的颜色处理、模型前处理及可报告的处理边界。 |
| P0-04 | P0 | **JPEG 是否标准可解码；色度抽样、quality、最大长度与帧结束语义是什么？** 可变长度接收和解码正确性依赖这些信息。 | （待 FPGA 队友填写） | TBD | 决定解码器兼容性、接收 buffer 上限、SOI/EOI/EOP 校验与错误处理。 |
| P0-05 | P0 | **FPGA 是否作为 PCIe EP？** 当前只是官方课程 Linux 路线和项目候选，不可替 RTL 配置作结论。 | （待 FPGA 队友填写） | TBD | 决定 RC 枚举、驱动绑定、复位和 BAR 访问模型。 |
| P0-06 | P0 | **SGDMA IP、C2H 通道、BAR 和 DMA 能力是什么？** 官方驱动可探测引擎，但不能证明当前 FPGA 工程的 IP 配置。 | （待 FPGA 队友填写） | TBD | 决定动态发现、C2H 提交方式、是否能用 EOP/实际完成长度及控制窗口 ABI。 |
| P0-07 | P0 | **Linux 在 DMA 前如何获得每帧 `payload_length`？** 若长度只在 DMA 内部 header，Linux 无法安全决定 DMA 请求长度。 | （待 FPGA 队友填写） | TBD | 必须在“BAR 每-slot 长度、整 slot 固定 DMA、两次 DMA、由 SGDMA 实际完成长度界定”中冻结可实现方案。 |

## P1：连续多帧联调前必须确认

| 编号 | 优先级 | 问题 / 为什么需要确认 | FPGA 队友回答 | 当前状态 | 对 Linux 实现的影响 |
|---|---|---|---|---|---|
| P1-01 | P1 | **slot 存储位置、数量、容量、stride 和对齐是什么？** 这些是连续接收内存分配和 DMA 范围的依据。 | （待 FPGA 队友填写） | TBD | 决定 buffer 池、容量检查、DMA 大小及吞吐/延迟估算。 |
| P1-02 | P1 | **每个 slot 的 metadata 布局是什么？** 单组全局长度/序号不足以描述多 slot。 | （待 FPGA 队友填写） | TBD | 决定解析地址、每帧关联、错误检查及多帧并发。 |
| P1-03 | P1 | **producer/consumer 索引格式、初值、回绕和可见性是什么？** 双方对同一 slot 的认领必须无歧义。 | （待 FPGA 队友填写） | TBD | 决定队列推进、重复/漏帧检测和复位后初始化。 |
| P1-04 | P1 | **`EMPTY/WRITING/READY/READING` 的每次状态转换由 FPGA 还是 Linux 写？** 所有权不能由一侧猜测。 | （待 FPGA 队友填写） | TBD | 决定 BAR 写入、DMA 认领、完成回收和错误路径。 |
| P1-05 | P1 | **跨时钟域同步和数据可见顺序如何保证？** metadata/状态先于 payload 或过早回收会造成读到半帧或覆盖。 | （待 FPGA 队友填写） | TBD | 决定寄存器读取顺序、barrier/重读策略、超时与一致性测试。 |
| P1-06 | P1 | **无 EMPTY slot 时采用何种丢帧或背压策略？** 实时性、数据完整性和所有权取舍必须明确。 | （待 FPGA 队友填写） | TBD | 决定 sequence gap 的诊断解释、统计项、队列深度和恢复策略；不将 gap 自动等同于 Linux 丢帧。 |
| P1-07 | P1 | **轮询、MSI/MSI-X 和中断确认方式是什么？** 第一版允许轮询，但 IRQ 能力与 ack 语义不能臆测。 | （待 FPGA 队友填写） | TBD | 决定事件循环、CPU 开销、BAR `INT_STATUS/ACK` 使用及优化计划。 |
| P1-08 | P1 | **最小复位与重新同步合同是什么？** 必须明确 PCIe 链路复位后的状态、FPGA 复位后的 slot 初始化、Linux 进程重启时的重新同步、stale `READY/READING` slot 清理、producer/consumer 索引重置、驱动/设备重新打开和协议版本重新读取流程。 | （待 FPGA 队友填写） | TBD | Stage F 真实 SGDMA 接入和最小恢复验收的入口条件；未确认前只能保留接口/占位实现，不得宣称真实接入完成或验收恢复流程。 |

## P2：性能优化和验收前确认

| 编号 | 优先级 | 问题 / 为什么需要确认 | FPGA 队友回答 | 当前状态 | 对 Linux 实现的影响 |
|---|---|---|---|---|---|
| P2-01 | P2 | **timestamp 的来源/单位/纪元、CRC 算法/覆盖范围、序号回绕规则是什么？** 指标和完整性统计需要共同口径。 | （待 FPGA 队友填写） | TBD | 决定端到端延迟计算、CRC 校验与 sequence 解析。 |
| P2-02 | P2 | **错误状态和错误计数有哪些、如何清除/读取？** 没有稳定错误 ABI 无法定位丢帧、编码或链路故障。 | （待 FPGA 队友填写） | TBD | 决定日志、健康检查、错误分类和测试报告字段。 |
| P2-03 | P2 | **高级恢复优化如何实现？** 在 P1-08 最小合同之上，确认自动重连、多级超时、详细错误计数、故障注入和不中断推理的热恢复策略。 | （待 FPGA 队友填写） | TBD | 决定高级健康检查、自动化恢复、故障演练和性能/可用性优化；不阻塞 Stage F 的最小真实接入。 |
| P2-04 | P2 | **可提供哪些测试图、固定 JPEG、变长 JPEG 和错误注入能力？** 需要可复现数据覆盖协议与解码异常。 | （待 FPGA 队友填写） | TBD | 决定单元/集成测试向量、错误路径验收和问题复现。 |
| P2-05 | P2 | **有哪些 FPGA 性能计数器及其定义？** R7 需要帧率、延迟、资源/压缩等可追溯数据。 | （待 FPGA 队友填写） | TBD | 决定采集统计接口、报告口径和瓶颈定位。 |
| P2-06 | P2 | **FPGA bitstream、工程和协议版本如何交付与标识？** 无版本对应无法复现 Linux/FPGA 联调结果。 | （待 FPGA 队友填写） | TBD | 决定兼容性检查、部署记录、bug 报告和回归测试矩阵。 |

## 确认记录

每项确认至少附：回答日期、回答人、FPGA 工程/bitstream 版本、关联 RTL/IP 配置或寄存器表版本、实机证据位置。若答案改变，保留旧记录并新建修订，不静默覆盖。

## 精确确认补充

以下各表不替 owner 作答；所有 `FPGA owner response` 初始为 `TBD`。每行的“所需版本/证据”必须随回答提供，不能以口头地址、课程示例或未实测候选替代。

### A. PCIe 身份与枚举

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P0-05a | TBD | Vendor ID、Device ID、Subsystem Vendor/Device ID、class code、endpoint/function 数量；Linux 需要可靠绑定与身份核验。不得填写未经确认的示例数值。 | PCIe IP/RTL、bitstream 版本；`lspci -nnvv` 或等价实机记录。 | TBD |
| P0-05b | TBD | BDF 是否可变、Linux 应依据哪些稳定属性发现设备、目标 PCIe Gen/lane width 与实际协商值。对每个实际可用身份属性，说明其来源（PCIe identity/config-space 字段、Device Serial Number、BAR 只读 board/device identifier、物理 slot/topology、device-tree/platform 映射、外部部署配置或其他 FPGA 实际机制；均为待确认类别而非既定存在）、精确字段/位置、width/format/endianness（适用时）、唯一性范围、PERST#/FLR/hot reset/FPGA reset/reboot 后稳定性、SGDMA 初始化前可读性及 RTL/bitstream/board revision 关系。还须给出匹配 cardinality 合同：零匹配、恰好一个匹配和多个设备具有相同基础 PCIe 身份时的准确结果；多匹配时的额外稳定 selector、来源、匹配规则、无法唯一匹配时的失败结果，且禁止静默选择任意第一个 BDF。若硬件没有区分同型号多板的唯一属性，必须记录限制、是否需要 Linux 部署配置或物理拓扑 selector；在外部 selector 合同确定前不得标为 `Confirmed`。Linux owner 实现后续发现/匹配逻辑，本文只要求双方可依赖的合同。 | Discovery/cardinality 规范；`lspci`/kernel log/BAR identity dump 或等价记录；reset/re-enumeration 前后身份观测。`Tested` 须覆盖零/一/多匹配；无多板实物时必须记录未测试限制，且不得把该场景标为 `Tested`。证据须证明 BDF 改变时不会选择错误设备，并关联 bitstream。 | TBD |

### B. BAR 与寄存器 ABI

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P0-06a | TBD | 每个 BAR 的 index、size、32/64-bit、prefetchable 属性；每个寄存器区与 DDR/window 的 offset、size、alignment。Linux 需要动态发现后安全寻址。 | 版本化 BAR/register map 或生成源，关联 RTL/bitstream。 | TBD |
| P0-06b | TBD | 每个可访问寄存器的访问宽度、endianness、RO/RW/W1C/读清除等副作用、reset value、保留位写规则；mmap 支持和禁止/受限区域。不能只回答“支持 BAR”。 | 版本化寄存器表；访问/reset 实测记录（适用时）。 | TBD |

### C. Frame header / record

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P0-04a | TBD | 是否有 header、固定或版本化；实际 magic/version/header length/payload length；byte-level 字段表（名称、offset、width、endianness、合法范围、reset/invalid value），包括 sequence/timestamp/flags/error/stream ID（若存在）。Linux 需要无猜测解析。 | 版本化 header/record 规范与 RTL/bitstream 版本。 | TBD |
| P0-04b | TBD | payload length 是否包含 header、padding、EOI 或尾部数据；header、payload、记录总长度的 alignment/padding；CRC/checksum 的算法、初值、覆盖范围、存放位置。 | Header 规范与 normal/boundary/error golden byte dumps。 | TBD |
| P0-04c | TBD | 完整帧发布顺序、有效/提交标志和 torn-read 防护；正常帧、边界长度帧、错误帧的 golden byte dump。当前不得假设任何固定 header 格式。 | RTL 时序/状态说明、dump 生成命令和 artifact。 | TBD |

### D. DDR slot 状态机

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P1-01a | TBD | slot 数量、每个基地址、stride、capacity、alignment。Linux 需要正确的 buffer/DMA 范围和容量计算。 | RTL/memory map 与 bitstream 版本。 | TBD |
| P1-02a | TBD | 每 slot metadata 的完整布局、地址/索引方式、版本和发布规则。Linux 不能用单一全局长度/序号代替多 slot metadata。 | Byte-level metadata/descriptor 表和 RTL 版本。 | TBD |
| P1-04a | TBD | 实际状态值、合法转换、每个状态的写入方与生效条件。`EMPTY/WRITING/READY/READING` 仅是示例，必须给出实际等价值。 | 状态机图、寄存器表、RTL 版本和并发测试证据。 | TBD |
| P1-05a | TBD | FPGA 何时发布 READY 或等价状态；Linux 如何选择下一完整 slot、何时归还；并发写/读如何防 torn header/payload。 | 发布/回收 ordering、CDC/barrier 说明和 trace。 | TBD |
| P1-06a | TBD | slot 满时的精确规则、“始终发送最新完整帧”的精确算法、绝不能覆盖的状态。Linux 需要区分 FPGA 丢帧与 Linux 队列策略。 | 状态机/overflow 规范和压力日志。 | TBD |
| P1-06b | TBD | 超限、overflow、覆盖、丢弃的可观测错误 ABI：状态位、计数器、IRQ、清除方式及 slot/sequence 关联。 | Error/register 规范、RTL 版本和错误注入证据。 | TBD |

### E. SGDMA

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P0-06c | TBD | SGDMA IP、官方工程（若适用）、RTL commit、bitstream 版本；C2H/H2C channel 数量和用途。Linux 不得从课程驱动推断当前 IP。 | IP 配置、RTL/bitstream 与实机 probe 日志。 | TBD |
| P0-06d | TBD | Linux driver 名称/版本与预期字符设备、ioctl、mmap 或其他 ABI；descriptor ownership，若 Linux 可见则给 byte-level 格式。 | Driver/kernel 版本、ABI/header 引用和受控实机日志。 | TBD |
| P0-06e | TBD | DMA address width、IOMMU/物理地址要求、scatter-gather、alignment、boundary、最小/最大长度、短传输、completion、timeout、错误返回、slot 地址到 DMA source 映射、cache coherency/barrier。 | SGDMA/RTL 规范、driver ABI 与 DMA 测试证据。 | TBD |

“官方 SGDMA 工程可作为基线”只能作为 `Proposed/Untested`，不能作为 SGDMA 能力已实测的证据。

### F. 长度发现、读取顺序与 IRQ

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P0-07a | TBD | Linux 在 DMA 前从哪个稳定寄存器、slot header 或 completion 获知 payload length；不得只回答“可获得长度”。 | Metadata/descriptor 规范与发布证据。 | TBD |
| P0-07b | TBD | slot state、header、payload、IRQ、DMA start/completion、ack、slot return 的严格顺序，每步稳定条件与竞态/不可用帧判定。 | 时序/状态机、RTL 版本和 trace/dump。 | TBD |
| P1-07a | TBD | INTx/MSI/MSI-X、vector 数/用途，frame-ready/DMA-complete/overflow/fatal 区分，status/mask/ack/clear 寄存器及语义。 | IRQ/register 规范、RTL/bitstream 和 `/proc/interrupts` 或等价证据。 | TBD |
| P1-07b | TBD | 中断合并、丢中断风险、ack 与 slot return 顺序、polling fallback 条件。 | Driver/IP 设置、压力日志和已知限制。 | TBD |

### G. Producer/consumer index、sequence、timestamp 与 epoch

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P1-03c | TBD | producer index 和 consumer index 是否都存在；各自所在 BAR/register/header/共享内存位置、byte offset、width、encoding、endianness、初始值、每种 reset 后的值、所有者/写入方、推进单位、slot index/单调计数器或其他表示、回绕模数与规则。还必须定义 producer == consumer 如何区分 empty/full 或等价状态，索引与 slot state/frame sequence 的关系，FPGA 发布索引与 slot/header/payload 的可见顺序，Linux 更新 consumer 后 FPGA 何时可重用 slot，memory ordering/barrier/原子访问，以及 reset/recovery 重新同步。frame sequence 不等于 producer/consumer index，不能替代 slot ownership/index 合同。Linux 需要安全推进、回收和重同步。 | 版本化寄存器表；至少一段 producer/consumer 推进与回绕的实机 trace/log；关联 RTL/bitstream。 | TBD |
| P1-03a | TBD | frame sequence 是否存在、位宽、初始值、递增规则、回绕模数；成功帧、编码失败、超限丢弃、slot overflow 是否消耗 sequence。frame sequence 不等于 producer/consumer index，不能替代 slot ownership/index 合同。 | Header/register 规范、RTL/bitstream 和 sequence trace。 | TBD |
| P1-03b | TBD | camera/FPGA/PCIe reset 后的 sequence 行为；stream_epoch/reset_counter 是否存在、宽度和更新时机。当前非回绕 `SequenceTracker` 不能推断这些答案。 | Reset/sequence 规范和 reset trace。 | TBD |
| P2-01a | TBD | timestamp 时钟源、单位、频率、起点、位宽、回绕；Linux 区分 gap、wrap、reset、新 stream 的准确规则。 | Header/register 规范、golden dump 与实机 trace。 | TBD |

### H. Reset、恢复与错误

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P1-08a | TBD | PERST#、FLR、hot reset、FPGA internal reset、camera reset 的支持矩阵，以及各自对 PCIe function、BAR、slot、SGDMA、IRQ、sequence、timestamp、error counter 的影响和是否重新枚举。 | 版本化 reset matrix 与每类 reset 实机记录。 | TBD |
| P1-08b | TBD | Linux 可触发哪些 reset、准确 API/寄存器和安全前置条件；恢复顺序、每步完成条件/timeout、旧 slot/completion 是否残留。 | Recovery procedure、RTL/bitstream 与受控恢复日志。 | TBD |
| P2-02a | TBD | JPEG encode failure、payload oversize、slot overflow、DMA/PCIe error、camera loss 的寄存器位、计数器、IRQ、sticky/clear 语义；是否关联 sequence/slot；Linux 能否读取最后完整帧。 | Error ABI、RTL/bitstream 和错误注入日志。 | TBD |
| P2-03a | TBD | 硬件 recoverable/fatal 定义、自动恢复边界与故障处置。此项遵循 [ADR 0003 的 Deferred 边界](../decisions/0003-linux-lifecycle-runner-event-policy.md)。 | Recovery/reset 规范和可复现故障恢复记录。 | TBD |

### I. 性能、容量、版本与证据

| Question ID | 当前状态 | FPGA owner 必须提供的精确答案 / Linux 为什么需要 | 所需版本/证据 | FPGA owner response |
|---|---|---|---|---|
| P2-04a | TBD | 正常、边界长度、错误 header/record golden byte dumps；固定/变长 JPEG 与可复现错误注入。 | 生成命令、输入条件、artifact 路径、header/RTL 版本。 | TBD |
| P2-05a | TBD | JPEG 最大值、平均值、分位数和测试场景；最大 payload 与平均 payload 必须分开。 | 原始命令/日志、画面条件、bitstream/RTL/IP/driver/kernel 版本。 | TBD |
| P2-05b | TBD | negotiated PCIe link、持续 C2H 吞吐、CPU、延迟、丢帧率、测试持续时间，以及 slot 深度满足最差情况的计算依据。性能证据不阻塞最初接口代码，但系统集成/验收前必须补齐。 | 原始 trace/log、计算依据和版本绑定。 | TBD |
| P2-06a | TBD | FPGA 工程、RTL、bitstream、IP、协议/header/register specification、driver/kernel 的版本标识和交付方式。 | Commit/hash/version、artifact 与变更记录。 | TBD |

## Current proposals — not implementation contracts

来源：[Linux transport checkpoint（2026-09-14）](../context/linux-transport-workstream-checkpoint-2026-09-14.md)。下列内容均不是 `Confirmed` 或 `Tested`，不得写入 Linux 固定实现：

- **Proposed/Untested**：官方 SGDMA 工程可能作为 FPGA PCIe EP 基线，尚无实测证据。
- **Proposed**：4 个 DDR slot。
- **Proposed**：1080p 单 slot JPEG payload 上限暂定 16 MiB，另加固定 frame header。
- **Proposed target**：平均 JPEG 尽量不超过约 4 MiB/帧；1080p60 约 240 MiB/s。
- **Proposed**：超限丢弃并上报错误。

以下仍为 `TBD`：精确 slot 状态机、覆盖策略、长度发现、header、sequence 位宽/回绕、stream epoch/reset counter、reset 映射、BAR/IRQ、PCIe/SGDMA 实测吞吐，以及超限错误的精确上报 ABI。

## 三道实现门禁

| Gate | Required Question IDs / domains | Minimum status before implementation | Required artifacts | Current result |
|---|---|---|---|---|
| Fixed-hardware-ABI `TransportRecordValidator` | P0-04a--P0-04c、P0-07a--P0-07b、P1-02a、P2-01a、**P2-05a**、P2-04a：byte-level header/record、offset/width/endianness、length/alignment、最大 payload、version/magic、完整性/发布/torn-read、CRC（若有）、golden dumps。 | `Confirmed`，其中 **P2-05a 至少为 `Confirmed`** 才能固定实际最大 payload。必须定义 payload、slot capacity、header、padding、DMA 限制各自上限及 validator 校验对象；明确最大值是否仅计 JPEG payload、是否排除 header/padding、等于上限是否有效和超过上限的准确错误语义。**Proposed 的 16 MiB 不能解除本 gate。** | Header/record spec、RTL/bitstream 关联、normal/boundary/error dumps；系统集成前须有等于确认上限及超过上限的错误/丢弃记录。若无法生成实际最大样本，必须记录未测试限制，不得声称边界为 `Tested`。 | **Blocked** |
| Real `SgdmaFrameSource` | P0-05a、P0-05b、P0-06a、P0-06b、P0-06c、P0-06d、P0-06e、P0-07a、P0-07b、P1-01a、P1-02a、**P1-03c**、P1-04a、P1-05a、P1-06a、P1-06b、P1-07a、P1-07b、P1-08a、P1-08b、P2-02a：PCIe identity/discovery、BAR ABI、producer/consumer index、slot 状态机、长度/read ordering、SGDMA/descriptor/completion ABI、IRQ/polling、错误与版本。 | `Confirmed`，其中 **P1-03c 至少为 `Confirmed`**；索引可见性、回绕和 reset 等硬件行为在系统集成前为 `Tested`。 | 枚举、BAR/ABI、DMA/IRQ、producer/consumer 推进记录和版本绑定。 | **Blocked** |
| Automatic recovery | **P0-05a、P0-05b**、P1-03a、P1-03b、P1-03c、P1-08a、P1-08b、P2-02a、P2-03a：PCIe identity/discovery（包括 P0-05b 的零/一/多匹配 cardinality、消歧与 ambiguity-failure 合同）、reset 矩阵、sequence/epoch/producer-consumer index、重新枚举、安全恢复、timeout、recoverable/fatal、旧 slot/completion。 | `Confirmed`：稳定 PCIe function identity、reset/re-enumeration 后 BDF 是否变化及 Linux 应依据的发现/多设备消歧规则、设备消失/重新出现/可重新访问完成条件，且关联实际 PCIe identity/register/bitstream 版本；集成/发布前为 `Tested`。 | 至少一次触发重新枚举的 reset/recovery：记录 reset 前后 BDF/identity、Linux 以已确认规则重新定位正确设备、`lspci`/kernel log 或等价可复现证据，以及版本绑定；遵循 [ADR 0003](../decisions/0003-linux-lifecycle-runner-event-policy.md)。 | **Blocked** |

> **ADR 0003 v1 Deferred boundary — Automatic recovery gate is not implementation authorization.** 此 gate 只是未来自动恢复设计的必要输入条件。即使所有 FPGA 问题达到 `Confirmed`/`Tested`，也只能使状态变为“Ready for separate recovery design decision”，不自动授权修改 `FrameLifecycleRunner` v1、自动 discovery、PCIe/SGDMA reconnect、FPGA reset、重试循环或 `SequenceTracker.reset()`。ADR 0003 继续有效：v1 不执行自动恢复；`RECOVERABLE_DISCONNECT`/`FATAL_ERROR` 仍终止当前阶段；不得伪造 reconnect；device discovery、PCIe/SGDMA reconnect、reset 和 stream epoch 仍为 Deferred。真正开始未来自动恢复实现前，必须新建或接受明确的后续 ADR/设计决策，定义 supervisor/runner API 与责任边界、retry/backoff/timeout、metrics ownership、旧 slot/completion 与 sequence epoch 的处理，并明确修改或取代 ADR 0003 的哪些条款。

Fixed-hardware-ABI `TransportRecordValidator` gate 只阻塞：在生产代码中写死真实 FPGA header/record 常量、绑定具体 FPGA byte-level ABI、宣称能校验真实 FPGA transport record，或默认启用真实 header/CRC/version 规则。它**不阻塞** [roadmap Stage C](../plans/linux-mvp-roadmap.md)允许的 mock validator、configurable validator、经显式配置传入布局/上限的实验实现、feature flag 隔离且不宣称真实 FPGA ABI 的路径，以及硬件协议无关的测试/接口骨架。这些路径仍不得把 `Proposed`/`TBD` 值作为默认真实硬件常量、声称已匹配 FPGA，或绕过本 gate 进入板端默认部署；这与[checkpoint 的禁止写死边界](../context/linux-transport-workstream-checkpoint-2026-09-14.md)一致。

这些门禁与[真实 transport 阶段的 roadmap 条件](../plans/linux-mvp-roadmap.md)一致；它们不改变 Linux/FPGA/AI 的既有职责边界。

## FPGA owner 回答模板

对每个 Question ID 复制以下模板填写。若答案改变，保留旧记录并按新版本重新确认/测试。

```text
Question ID:
Status: TBD / Proposed / Confirmed / Tested
Exact answer:
RTL commit:
Bitstream version/hash:
SGDMA/IP version:
Register/header specification reference:
Driver/kernel version (if applicable):
Evidence command:
Evidence log/dump/artifact:
Test platform and conditions:
Known limitations:
Owner:
Date:
```

未回答或信息不足时保持 `TBD`；FPGA owner 不得仅为完成表格而把 `TBD` 升级为 `Proposed` 或 `Confirmed`。`Proposed` 仍不能解除 Linux 实现门禁；`Confirmed`/`Tested` 仍必须满足前文规定的版本和证据要求。“支持”“应该可以”“参考官方工程”等模糊表述不能替代 `Exact answer`、版本关联和证据；仅有候选设计时必须填写 `Proposed`，不得标记为 `Confirmed` 或 `Tested`。
