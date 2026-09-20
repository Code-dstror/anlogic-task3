# PCIe 功能仿真尝试

## 验证目标与证据边界

本轮在 ModelSim 中尝试比 AXI 接口替身更完整的功能仿真，不运行 TD 综合或布局布线。
测试代码位于 `fpga_rtl/tb/`，不能作为生产设计源注册到 TD 工程。
不修改或解密厂商快照，不把模拟主机写入测试结果当作 DMA 引擎的执行结果。

| 层级 | 被测真实逻辑 | 通过后可以证明 | 不能证明 |
|---|---|---|---|
| 已有封装测试 | 自研帧入口/发送器；endpoint 是替身 | 字节封装、AXI 握手、控制透传及恢复 | 真实 SGDMA、PCIe 枚举和 DMA |
| 真实厂商模型探测 | 当前 endpoint、PCIe 硬核模型、SGDMA 与自研封装 | 按日志分别判断编译、展开、时钟/复位状态 | 无对端时不能宣称链路训练成功 |
| SGDMA 事务级测试 | 原始加密 `sgdma_ip`；测试台产生 CQ/RC、接收 RQ/CC | 实际观察到的寄存器访问、描述符读取、内存写入 | 绕过的 PCIe PHY/链路、配置枚举和真实 Linux |
| 完整 PCIe 主机联仿 | 真实 endpoint 与兼容 RC/BFM | 覆盖到的配置事务、BAR、描述符和数据传输 | 板上电气、RK3576 BSP/IOMMU/缓存一致性 |

## 已确认的输入资料

- 当前厂商 SGDMA：`fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/src_enc/sgdma_ip_all.enc.v`。
  其公开端口为 `sgdma_ip`，保护段包含 Mentor Graphics 仿真密钥声明；
  是否能运行以 ModelSim 实际结果为准。
- PH1 PCIe 硬核模型来自本机 TD 安装的 `sim_release/ph1/ph1_phy_pcie_v3.sv`。
- CQ/RQ/RC/CC 的帧布局以受审厂商 bridge 的公开 RTL 为依据。
- DMA 寄存器和描述符定义可从可选官方课程目录中的
  `deploy/sgdma_drv/anlogic_pci_lib.h` 与 `.c` 核对。
  这些文件只作来源核对，不能令已有仓库的常规仿真依赖可选课程目录。
- 当前 SGDMA 配置：PH1A、128-bit、C2H0/H2C0 各一、正常描述符模式，
  非 descriptor bypass；AXI4-Lite master 启用。

## 本轮结果

### 既有自研逻辑回归

本轮重新执行 `run_modelsim.ps1 -MaxCases` 和
`run_video_transport_modelsim.ps1`，均 PASS，编译与运行均无 error/warning。
覆盖帧头/数据、1/15/16/17/最大长度减一/最大长度、反压、AXI4-Lite
顺序与字节选通、H2C 检查器及封装故障恢复。封装回归仍使用 endpoint
替身，不能将它的结果并入真实 SGDMA 的覆盖范围。
厂商快照哈希检查 `tools/verify_vendor_hashes.ps1` 为 PASS（31 文件）。

### 真实硬核模型探测（2026-09-15）

运行 `fpga_rtl/tb/run_vendor_pcie_modelsim.ps1`，使用本机 ModelSim SE-64
2020.4 与 TD 6.2.168116 的 PH1 模型。实际编译和展开的是
`pcie_video_transport`、真实 endpoint、受保护 SGDMA 与 `PH1_PHY_PCIE_V3`，
不是 endpoint 替身。

- PH1 模型编译：0 error / 0 warning。
- 设计编译、展开运行：0 error / 1 warning；warning 来自厂商 MSI 模块的
  unsized concatenation，本轮未修改厂商代码。
- 运行 100 µs：`user_clk=0`、`user_rst_n=0`、`link_up=0`，通道状态为零。
- 结果为 **DIAGNOSTIC_NONPASS**，只证明模型能加载运行，不证明链路或 DMA。
  生产包装的 PLL 稳定等待为 22 位计数，约 33 ms，100 µs 尚未覆盖该等待；
  即使延长等待，仍缺少兼容的 Root Port 对端。
- 运行需要 `al_pcie_ip.txt`，脚本从受审快照复制到忽略的工作目录；
  测试台实例化了模型要求的 `PH1_PHY_GSR`。未强制内部 link/reset 状态。

日志位于 `tmp/modelsim/vendor_pcie_probe/` 下的 `compile_ph1.log`、
`compile_design.log`、`vendor_pcie_probe.log`。

### 完整链路仿真的缺口

本机官方课程资料中未找到可直接使用的 PCIe RC/BFM/VIP 或 PCIe 仿真脚本。
当前生成包装仅暴露串行管脚，未暴露 PIPE 接口；另一套 Gen3 x4、不同封装
的旧例程不能直接混入当前 PH1A90SEG324 Gen2 x1 配置。
公开官网检索也未找到可直接下载使用的匹配 RC 仿真包。
因此，**本轮尚不能验证链路训练和主机枚举**；后续需要厂商提供匹配的
Root Port 示例、VIP 或 SGDMA 完整仿真包，再接入本轮的事务检查器。

### 真实 SGDMA 事务测试

被测对象为真实加密 `sgdma_ip`；测试台代替主机在 CQ/RC 端口发包，在
RQ/CC 端口观察真实核的输出。没有替换 DMA 算法或强制内部状态，也未启用
descriptor bypass。当前目标是单描述符、单个 16 字节 C2H 包。

主机模型使用三个分离的总线地址：描述符 `0x00100000`、数据目标
`0x00200000`、完成记录 `0x00300000`。C2H streaming 描述符的 `src`
用于完成记录地址，`dst` 才是数据目标地址；末描述符设置 STOP/EOP/COMPLETED。

开发中修正了三个测试台问题，而不是修改厂商 DMA：

- RQ tag 在 `[103:96]`，不能把 `[71:64]` 的请求长度当作 tag；tag=0 合法。
- RC byte-enable 和 SOF sideband 需遵循当前厂商桥的输出布局。
- 驱动数据必须以时钟上升沿 `VALID && READY` 判断握手，不能在下一下降沿
  看到 READY 已撤回时误以为上一拍没有接受。

自检已 PASS；主代理在独立工作库 `tmp/modelsim/sgdma_transactions_independent/`
于 2026-09-15 20:45 再次编译、展开、运行，退出码 0，5500 ns 时 PASS：

- CQ 读取 DMA BAR1 偏移 `0x3000`，真实 CC 返回配置 ID `0x1fc30001`。
- CQ 编程 C2H0 的 `0x5080/0x5084/0x5088` 和 `0x1004`，真实核发出
  地址 `0x00100000`、长度 8 DWORD 的描述符 MRd。
- RC 返回 32 字节描述符后，真实核产生 `0x00200000` 的 MWr。
  逐位比对 128-bit 数据 `00112233445566778899aabbccddeeff` 与 `keep/last`。
- 真实核向 `0x00300000` 写回 `status=0x52b40001`、`length=16`，
  对两个 DWORD 及 `keep/last` 作自检。
- 编译 0 error / 0 warning；展开运行 0 error / 267 warnings，主要为保护模块
  内部连接宽度及未使用端口。警告没有被屏蔽，本轮不声明已消除所有警告。

日志为 `tmp/modelsim/sgdma_transactions/compile.log` 和
`sgdma_transactions.log`。**不能将事务级 PASS 表述为整个 PCIe 链路验证通过。**
独立复跑日志在上述 `_independent` 目录，未复用 worker 的已编译工作库。
特别是该测试没有把自研 in-band 帧入口、PCIe bridge 和硬核串在同一个带主机的
仿真中；没有验证 BAR0 到外部 AXI4-Lite 从设备的真实 SGDMA 路径、H2C DMA、
多描述符链、多拍/非整拍长度、事务级随机反压、复位中断或 MSI。
这些是后续扩展项，不因已有接口替身回归通过而自动获得覆盖。

## 静态门禁与功能验证分开记录

按照 `readable-verilog-generator` 技能执行的新 probe 严格门禁（含 testbench）
尚未通过。报告 `tmp/quality/vendor_probe.json`：`compile/ast/readability/comment/
naming/profile` 为 failed，`testbench` 为 passed，`toolchain` 为 not_requested。
其中包含 formatter 解析限制及严格模板/注释要求，不能当作 ModelSim 编译错误，
也不能因 ModelSim 运行成功而忽略该门禁。当前交付是可复现的功能仿真尝试与
诊断记录，不声明严格代码质量验收完成。未运行 TD 综合、布局布线或板级测试。
事务测试台也执行了同类严格门禁，报告 `tmp/quality/sgdma_transactions.json`，
同样未通过；ModelSim 编译运行结果仍以对应工具日志为准。

## 复现入口

在仓库根目录的 PowerShell 中运行：

```powershell
& fpga_rtl/tb/run_modelsim.ps1 -MaxCases
& fpga_rtl/tb/run_video_transport_modelsim.ps1
& fpga_rtl/tb/run_vendor_pcie_modelsim.ps1
& fpga_rtl/tb/run_sgdma_transactions_modelsim.ps1
```

前两个入口为已有自研逻辑回归；第三个正常终止也只输出
`DIAGNOSTIC_NONPASS`；第四个必须同时检查仿真日志与脚本结果。
所有新测试文件留在 `fpga_rtl/tb/`，没有加入 TD 的生产源清单。

## 2026-09-15 提交前复查

21:01 使用本机 ModelSim 再次执行 `run_modelsim.ps1 -MaxCases`、
`run_video_transport_modelsim.ps1` 和 `run_sgdma_transactions_modelsim.ps1`，
均 PASS。本次 SGDMA 复跑使用现有优化工作库，日志 warnings=0；这不抹去
前文独立全新工作库展开产生的 267 条警告，也不代表这些警告已被修复。
厂商 31 文件 SHA-256 校验通过，协议生成器输出与现有 C/Verilog 头文件一致。
本轮未跑 TD 综合、布局布线或板级验证。

仓库整理移除了可重建的旧 ModelSim 编译库与 Python 字节码，保留上述
PCIe 仿真日志、质量报告及 TD 报告。历史技能 smoke-run 报告移至忽略的
`tmp/cleanup_20260915_archive/`，没有删除报告内容；源脚本和技能测试夹具保留。
