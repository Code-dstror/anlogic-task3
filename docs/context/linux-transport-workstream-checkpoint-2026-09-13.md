# Linux transport/system 工作流检查点

- 日期：2026-09-13
- 状态：**Current checkpoint**
- 工作流：**Linux transport/system**
- 基线：`main` `c558b49`；Linux HEAD `14749ec`

本文件把已验证的仓库事实、团队的 Proposed 决策、尚待硬件合同确认的
事项，以及推荐但尚未决定的后续动作分开记录。它不记录 SSH key、邮箱、
token 或其他凭据。

## 已验证事实

### Git 检查点

- GitHub 主仓库为 `Code-dstror/anlogic-task3`（Private）。
- `main`、`origin/main` 与 `backup/main` 当前均指向 `c558b49`；标签
  `checkpoint-c558b49` 也指向该解耦检查点。
- 当前 Linux 分支为 `feature/linux-transport`，HEAD 为 `14749ec`；
  `origin/feature/linux-transport` 同样指向 `14749ec`，即已同步。
- 创建本文档前，`git status --short` 无输出，工作区干净。
- 当前可见的远程分支只有 `origin/main`、
  `origin/feature/linux-transport` 与 `backup/main`；没有据此推断其他成员
  已 clone、建分支或开始实现。

### 已提交的公共基线

以下提交号由 `git log` 核对：

| 提交 | 已完成内容 |
|---|---|
| `f96ba7b` | Stage A 核心类型、接口、错误和 `RuntimeMetrics`（`feat: add Python pipeline core interfaces`） |
| `d2631eb` | `MockFileFrameSource`（`feat: add mock JPEG file source`） |
| `4b9483e` | `JpegPayloadValidator`（`feat: add JPEG payload validator`） |
| `b7ffec3` | `OpenCvJpegDecoder`（`feat: add OpenCV JPEG decoder`） |
| `c558b49` | 测试拆分与 workstream ownership（`refactor: split tests and define workstream ownership`） |

### 三人工作流边界

- FPGA owner：MIPI CSI、JPEG encoder、PCIe EP/SGDMA、slot/BAR/IRQ，以及
  FPGA reset。
- Linux owner：协议解析、`SequenceTracker`、`SgdmaFrameSource`、驱动与设备
  发现、恢复和板端部署。
- AI/application owner：从 `DecodedFrame` 开始，负责预处理、RKNNLite、YOLO
  后处理、`DetectionResult` 和输出。

目前只确认任务说明已发给另外两名成员；除非相应 Git remote branch 实际可见，
不得声称他们已 clone、建分支或开始实现。

### Linux 分支成果

`14749ec`（`feat: add sequence anomaly tracker`）新增：

- `linux/task3_pipeline/sequence_tracker.py`
- `tests/test_sequence_tracker.py`

它提供 `SequenceStatus`：`FIRST`、`IN_ORDER`、`DUPLICATE`、`GAP`、
`OUT_OF_ORDER`，并采用线性、非回绕语义。`FIRST`、`IN_ORDER` 与 `GAP`
推进高水位；`DUPLICATE` 与 `OUT_OF_ORDER` 不推进。异常只作诊断，不决定
payload 是否继续处理。输入接受任意大的非负 Python `int`（拒绝 `bool`）。

本检查点的全量离线测试为 78 项，且已通过。序号位宽、回绕、`stream_epoch`、
`reset_counter` 以及 FPGA reset 到 tracker reset 的映射仍为 TBD。

### AI 预处理交接基线

- `OpenCvJpegDecoder` 当前输出 `bgr24` 的 `DecodedFrame`。
- 官方 Python 脚本基线执行 BGR→RGB、640×640 letterbox，并增加 batch。
- Python 侧的目标输入表现为 RGB、NHWC、`uint8`、`(1, 640, 640, 3)`；交接时
  必须保留原图尺寸、ratio 和四边实际 padding。
- `.rknn` 内部 NCHW/`int8` 与上述 Python 输入之间的转换仍须在 RK3576 实机
  确认；不得将其写成已确认事实。
- `PreprocessedFrame` 与 `ModelInput` 仍是计划中的共享契约。

## 团队 Proposed 决策与初步 FPGA 回复

以下是 FPGA 队员的初步意图或预算，不是已由 RTL 或实机证据确认的 ABI：

- **Confirmed intent**：官方 SGDMA 工程作为 FPGA PCIe EP 基线并尽量复用；
  但尚未记录 PCIe 枚举或 DMA 实测证据。
- **Proposed**：FPGA DDR 中计划使用 4 个 slot。
- **Proposed**：首版目标为 1080p，每 slot 的 JPEG payload 上限暂定 16 MiB，
  另加固定帧头。
- **Proposed performance budget**：1080p60 时平均 JPEG 尽量控制在约
  4 MiB/帧，即约 240 MiB/s。
- **Proposed**：超限帧丢弃并上报错误。
- **TBD**：“管理等待数据并发送最新完整帧”尚未转换为明确的 slot 状态机和
  覆盖规则。

当前存在未解决冲突：原协议草案倾向无空 slot 时丢弃新帧；FPGA 回复可能倾向
淘汰旧 `READY` 帧以保留最新帧。未冻结前 Linux 不得实现任何具体覆盖策略，
尤其不得覆盖正在 DMA 的 slot。

## 硬件与协议 TBD

在 [FPGA 确认清单](../coordination/fpga-confirmation-checklist.md) 填写并经双方
评审前，至少需要确认：

- 4 slot 是 FPGA 内部队列还是 Linux 可见，Linux 如何领取并确认消费；
  `EMPTY`/`WRITING`/`READY`/`SENDING` 或 `READING` 的状态所有权。
- 队列满时丢新、丢最旧 `READY` 还是暂停上游；正在 DMA 的 slot 必须永不覆盖。
- Linux 在 DMA 前如何获得 `payload_length`；header+payload 是一次还是两次
  C2H transaction；`tlast`/EOP 的确切含义与帧边界关系。
- 固定 header 的字段、位宽、大小端和对齐；sequence 的位宽、分配时机，以及
  丢帧是否消耗 sequence。
- reset 后的 sequence 与 slot 状态、`stream_epoch`/`reset_counter`，以及 Linux
  的重新同步入口。
- 实际 PCIe generation/width 和可持续吞吐。
- 4 × 16 MiB 加帧头及对齐的 FPGA DDR 地址规划。

因此 Linux 当前不得写死 4 slots、16 MiB、BAR 偏移、header 布局或 sequence
位宽。`TransportRecordValidator` 等依赖固定 header 的实现，须待合同冻结后再
开始。

## 推荐但尚未决定的后续动作

- 可独立推进的候选任务包括 `MockCorruptFrameSource`、错误注入测试，以及无
  硬件 pipeline orchestration；目前尚未选择其中任何一个作为下一任务。
- 不直接修改 AI/application 或 FPGA 私有模块。共享契约改动必须独立提交并由
  相邻工作流评审。
- `official_package`/`local_refs` 保持只读且不进入 Git；禁止 force push。

## 新聊天恢复步骤

1. `cd ~/work/anlogic-task3`
2. 在切换任何分支前执行 `git status --short`。
3. 如果有任何输出，立即停止；不得执行 `git switch`、`git pull`、`reset`、
   `checkout`、`stash`、删除或覆盖操作，先报告现有修改。
4. 只有工作区干净时，执行 `git switch feature/linux-transport`。
5. 再次执行 `git status --short`，确认分支切换后仍然干净。
6. 如果第二次检查有任何输出，立即停止并报告产生的修改；不得执行 `git pull`
   或任何其他会改变仓库状态的命令，禁止自动 `stash`、`reset`、`checkout`、
   `clean`、删除或覆盖这些修改。
7. 只有第二次检查也为空时，执行 `git pull --ff-only origin feature/linux-transport`。
8. 核对当前分支和 HEAD。
9. 阅读 `AGENTS.md`、`docs/coordination/workstream-ownership.md` 和本文档。
10. 运行完整测试。
11. 检查最新 FPGA 回复后，再选择下一项原子任务。
