# PCIe C2H 实施状态（2026-09-14）

> 历史里程碑记录：下文综合、时序和 bitstream 结果只对应当时的测试顶层，
> 不能作为 2026-09-15 新 `pcie_video_transport` 封装的实现证据。
> 今晚的新封装以仿真验收；真实 SGDMA 最小事务闭环已另行通过，但完整
> PCIe 枚举/板级验证仍未完成。最新边界见
> [封装接入合同](pcie_video_transport_integration.md) 与
> [功能仿真报告](pcie_functional_simulation_attempt.md)。

## 本次交付

- TD 目标工程为 `PH1A90SEG324-2`，顶层为 `pcie_c2h_test_top`。
- 集成官方 PH1A PCIe Gen2 x1 Endpoint、官方 SGDMA、官方 PLL，以及官方
  Soft FIFO 3.0。FIFO 的存储、读写指针和跨时钟逻辑均未手写；
  `axis_frame_fifo_ip` 仅负责 AXI-Stream 握手和字段打包。
- 实现 128-bit C2H0 64 字节帧头发送器、固定测试源、H2C0 检查器、
  AXI4-Lite 用户寄存器和共享协议代码生成。
- 厂商依赖以最小快照纳入仓库，并保存来源、版本和 SHA-256 清单；
  错误的 PH1A90SBG484 / Gen3 x4 同名 IP 未加入工程。
- 增加行为仿真、官方 FIFO 联合仿真、TD 同步/构建/导出和门级仿真脚本。

## 已实际通过

- 共享协议 Verilog/C 头文件生成。
- 厂商快照 SHA-256 校验：31 个文件一致。
- ModelSim 纯 RTL 自检：帧头、payload、`TKEEP/TLAST`、随机反压、
  AXI4-Lite 通道次序/`WSTRB`/高位别名、H2C 多错误统计通过；边界测试
  包含 1、15、16、17、16 MiB-1 和 16 MiB。
- ModelSim + TD PH1 官方 Soft FIFO 3.0 联合仿真通过。
- TD 工程同步、综合、布局布线、时序分析和 bitstream 生成通过；
  运行器退出码为 0，未生成新的 `*.error.f`。
- 最终时序：setup WNS 0.116 ns、TNS 0；hold WNS 0.021 ns、TNS 0。
- 布局布线后功能网表在 ModelSim 中完成 2 us 展开/复位冒烟测试。

## 换机后本机复验

- 2026-09-15 将可选的 `03_MLK_AFH03_AFC03/` 官方资料恢复到本机工作区后，
  已按 `SOURCE_ORIGIN.md` 记录的原始路径反向核对受审快照：PCIe/SGDMA
  25/25 个文件与官方工程字节一致，Soft FIFO 3.0 的 6/6 个文件与本机 TD
  6.2.168116 IP depot 字节一致。复验命令为
  `tools/verify_vendor_hashes.ps1 -CompareOfficialSource`；该目录仍不是构建依赖
  并继续由 Git 忽略。
- 本机 ModelSim 为 `D:/App/modelsim/win64`，版本为 SE-64 2020.4；TD 为
  `E:/APP/Anlogic/TD_6.2.1_Engineer_6.2.168.116`。三条 ModelSim 脚本现可
  从各本地盘的常见安装目录自动探测这两个工具，仍保留环境变量和显式参数
  作为最高优先级覆盖。TD 同步脚本还会在关闭工程后把 `.al` 根路径恢复为
  `Path="."`，避免换机同步写入本机绝对路径。
- 修复 vendor 子树继承 `eol=lf` 导致克隆后 14 个厂商文本快照不再保持原始
  CRLF 字节的问题；这些文件均以“恢复 CRLF 后 SHA-256 必须等于既有清单”
  为写入条件，最终 31 个厂商文件校验全部通过。
- 共享协议重新生成后无 Git 差异；纯 RTL 最大边界/随机反压测试和 PH1 官方
  Soft FIFO 联合仿真均再次通过。
- TD 工程同步、全量综合、布局布线、bitstream 和 routed 网表/SDF 导出再次
  通过。最终 setup WNS 为 0.116 ns、TNS 为 0；hold WNS 为 0.021 ns、TNS
  为 0，报告置信度为 Routed，STA coverage 为 99.29%。
- 布局布线后功能仿真再次以 0 errors 运行至 2 us。严格 SDF 仿真成功加载
  SDF，但再次得到 568 个上电未知态窗口错误和 8 个厂商硬 IP SDF/`specify`
  路径警告，因此严格 SDF 项仍保持失败。

## 未通过或尚未完成

- 严格 SDF 仿真未通过。SDF 成功加载，测试平台运行至 2 us 并结束，
  但 TD 6.2.168116 的 PH1 受保护 PCIe/ERAM 模型在约 2.7 ns 上电未知态
  窗口报告 568 个 `$setup`/未知 RAM 时钟错误。因此脚本保持非零退出，
  本项不记为通过。另有 8 条硬 IP SDF 路径与受保护模型 `specify` 路径
  不匹配，已降为可见警告，未被静默删除。
- 可读性技能的严格交付门禁未通过（4729 个格式错误、36 个严格警告），
  主要来自该门禁要求的制表符缩进和固定双语文件头；RTL 编译、自检及
  综合结果不受此项影响，但后续应分批统一风格。
- 换机后用当前技能运行时复跑严格交付门时，目录级运行超过 20 分钟、
  `c2h_frame_tx.v` 单文件运行超过 5 分钟仍未发布报告，均已人工终止。因此
  本机没有新的 AST/可读性报告，继续保留上一条失败结论，不能记为新通过。
- 当前 ModelSim 环境没有 RK3576 Root Complex BFM，未验证 PCIe 枚举、
  描述符执行或真实 DMA。
- TD 子运行日志仍包含官方 PCIe IPC SDC 的实例作用域警告，以及 ERAM
  异步复位警告。项目约束沿用官方板级例程的派生时钟和异步时钟组；
  最终 TD 原生时序报告无 setup/hold 违例。
- TD Hierarchy Navigation 中的多个 `<hidden>` 已核实为厂商受保护 IP 的正常
  展示：`soft_fifo.v` 从文件开头进入 `pragma protect`，`sgdma_ip_all.enc.v`
  在公开的 `sgdma_ip` 端口壳之后进入 `pragma protect`。TD 能综合其加密内容，
  但不会公开内部模块名；这不是 RTL 丢失、字符集错误或环境变量故障。不要
  修改、解密或重复加入这些厂商文件；只有厂商提供未加密 RTL 才会显示完整
  内部层次。
- `<hidden>` 与 PCIe IPC SDC 警告是两个独立现象。后者来自
  `al_ip/PH1_LOGIC_PCIE.sdc` 中未匹配当前综合网表层次的 `get_pins/get_regs`
  目标，当前构建仍无 `*.error.f` 且最终时序收敛，但这些失效 exception 不能
  当作已经生效。修复前应先用与快照生成器一致的 TD/IP 版本重导出 per-IP
  SDC，或在自研目录维护经过层次核验的 scoped SDC；不得直接篡改厂商快照。

## 换机继续

1. 安装带 PH1 许可证的 TD 6.2.168116 和 ModelSim 2020.4。脚本会先读取
   `TD_ROOT`、`MODELSIM_BIN`，再检查 `PATH` 和各盘常见安装目录；自动探测
   失败时再显式传参。详细命令见仓库根目录 `README.md`。
2. 先执行厂商 SHA 校验和共享协议生成，再执行行为仿真及官方 FIFO 联合仿真。
3. 运行 TD 同步脚本后再构建。工程文件只引用仓库相对源路径，官方大例程目录
   `03_MLK_AFH03_AFC03` 不属于构建依赖。
4. 下一阶段先上板用 `lspci -vv` 验证 Gen2 x1、BAR 和设备 ID，再完成固定帧
   C2H、已知 JPEG、双缓冲和 4-slot；不得仅凭 `user_link_up` 判定 DMA 缓冲可用。

生成的 Runs、日志、报告、网表、SDF、bitstream 和 ModelSim 工作库均被
`.gitignore` 排除，可以由仓库内脚本重新生成。
