# 当前会话交接记忆：安路 FPGA 赛题 3 与 Ubuntu Codex

> 生成日期：2026-09-13
>
> 用途：将本文件复制到 Ubuntu 22.04 虚拟机，在新的 Codex CLI 会话中作为项目背景和工作交接材料。
>
> 注意：本文不包含 Clash 订阅地址、节点密码、ChatGPT 登录令牌或其他敏感凭据。

## 1. 用户目标与分工

- 参加嵌入式芯片与系统设计竞赛的安路 FPGA 赛道。
- 选择的是赛题 3。
- 用户负责 RK3576/Linux 部分。
- 队友负责 FPGA 部分。
- 后续需要重点完成 Linux 与 FPGA 的接口定义、驱动/用户态链路、推理和系统联调。

原始 Windows 工作区：

```text
D:\安路\03_MLK_AFH03_AFC03
```

赛题 PDF：

```text
D:\安路\嵌赛FPGA赛道_赛题\安路.pdf
```

进入 Ubuntu 后，上述 Windows 路径可能不可用。需要从 VMware 共享目录、U 盘或其他方式把必要文件传入，但不要假设路径保持不变。

## 2. 已查看的厂商资料与初步结论

Windows 原工作区内曾查看以下资料：

```text
03_course\07_异构方案\AFC03_IMX415_PCIE_X1\米联客2026版异构AFC03教程-PCIE篇.pdf
03_course\07_异构方案\415_mipi\米联客2026版异构AFC03教程-MIPI篇.pdf
```

对现有示例的初步观察：

- PCIe V4L2 示例偏向固定长度原始图像传输；已有驱动中曾发现 RGB24、每像素 3 字节及固定帧大小等硬编码。
- MIPI 虚拟传感器示例曾发现 YUYV、1920×1080、60 FPS、4 Lane 等固定配置。
- RKNN 示例使用 Python/OpenCV，曾使用 `/dev/video73`、1280×720、30 FPS，并只使用一个 NPU Core。
- 这些示例适合作为板卡启动、驱动和数据通路的参考基线，但不能直接当作赛题 3 的最终方案。

先前讨论形成的技术倾向：

- 如果 FPGA 输出的是可变长度 JPEG 压缩帧，优先考虑通过 PCIe 传输，而不是直接套用固定长度原始帧 V4L2 示例。
- Linux 侧应明确区分：底层 PCIe/DMA 接收、帧边界管理、JPEG 解码、RKNN 推理、结果显示或回传。
- 上述判断仍需要进入 Ubuntu 后结合完整赛题要求、板卡 BSP、驱动源码和 FPGA 队友方案重新验证，不应视为已经冻结的架构。

## 3. Ubuntu 虚拟机当前状态

虚拟机环境：

```text
VMware
Ubuntu 22.04 Jammy
X11 会话
```

### 3.1 Clash Verge

已安装：

```text
Clash Verge Rev 2.5.1 amd64
/usr/bin/clash-verge
/usr/bin/verge-mihomo
```

安装曾通过以下信息确认成功：

```text
install ok installed
Version: 2.5.1
```

APT 末尾出现的 `_apt` 无法读取本地 Deb、脱离沙盒提权读取的 `N:` 提示不是安装失败。

### 3.2 Clash 主界面花屏解决方案

问题原因判断为 VMware 虚拟显卡与 WebKitGTK DMA-BUF 渲染不兼容。

下面的启动方式已验证能修复彩色斜线、空白和控件缺失：

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 /usr/bin/clash-verge
```

已经创建用户级兼容启动项：

```text
~/.local/share/applications/clash-verge-compatible.desktop
```

其关键内容应类似：

```text
Name=Clash Verge（兼容模式）
Exec=env WEBKIT_DISABLE_DMABUF_RENDERER=1 /usr/bin/clash-verge %u
```

以后从 Ubuntu 应用菜单启动“Clash Verge（兼容模式）”。如果界面仍像旧版本，应先执行：

```bash
pkill -x clash-verge
```

因为关闭窗口后旧进程可能仍在托盘后台。

### 3.3 订阅导入问题及最终解决方法

已确认的问题：

- 主界面花屏解决后，点击“订阅 → 新建”仍会卡住；
- 增加 `WEBKIT_DISABLE_COMPOSITING_MODE=1` 也没有解决该弹窗；
- 这是当前 Ubuntu 22.04/X11/Clash Verge 2.5.1 下的 WebKit 界面问题，不是订阅内容本身的问题。

最终有效方法：

1. 不使用“新建”弹窗；
2. 在终端中以隐藏输入方式读取订阅 URL；
3. 使用 `curl` 和 `User-Agent: clash.meta` 下载为 YAML；
4. 将 YAML 文件直接拖到 Clash Verge 的订阅页面；
5. 成功出现订阅卡片并选中节点；
6. 代理已经正常工作，Ubuntu 可以访问互联网。

订阅配置文件包含节点密码，不能提交到项目 Git，也不能粘贴给 Codex。

完整的 Clash/Codex 安装排障记录另存于 Windows 工作区：

```text
Ubuntu22.04_ClashVerge与CodexCLI_安装配置记忆.md
```

## 4. Codex CLI 当前状态

- Codex CLI 已在 Ubuntu 22.04 内成功安装。
- 已成功通过 ChatGPT 账户登录。
- 可以使用以下命令检查：

```bash
codex --version
codex login status
```

登录凭据可能位于：

```text
~/.codex/auth.json
```

该文件等同密码：不得提交 Git、不得复制进工程、不得发送到聊天或 Issue。

推荐从具体工程根目录启动：

```bash
cd "$HOME/work/anlogic-task3"
codex --sandbox workspace-write --ask-for-approval on-request
```

不要从 `$HOME` 根目录直接启动 Codex，以免工作区包含大量资料包和个人文件。

日常不建议使用：

```bash
codex --dangerously-bypass-approvals-and-sandbox
```

即使在虚拟机内，该模式也可能误删工程、用户目录、登录凭据或 VMware 共享文件。需要安装软件、加载内核模块或修改系统配置时，再逐次批准相应操作。

## 5. 原始资料目录策略

用户说明：厂商资料包通常直接解压在 `~` 下，而且资料中可能带有教程，因此目前不打算移动这些文件。

已决定：

- `~` 下的原始资料保持原位；
- 原始资料原则上只读，不直接在其中开展长期开发；
- 新建独立工程仓库；
- 必要时在工程的 `local_refs/` 中建立指向原资料的符号链接；
- `local_refs/` 不提交 Git；
- 确定要修改某个厂商示例后，只复制“最小必要代码子集”到正式工程，并记录来源和改动。

建议工程根目录使用纯 ASCII 路径：

```text
~/work/anlogic-task3
```

纯 ASCII 路径能减少交叉编译脚本、Makefile、第三方工具和 Windows/Linux 协作中的路径兼容问题。

符号链接示例：

```bash
mkdir -p "$HOME/work/anlogic-task3/local_refs"

ln -s "$HOME/某个资料目录" \
  "$HOME/work/anlogic-task3/local_refs/vendor-course"
```

如果 Codex 的沙盒不能读取符号链接指向的工程外目录，应让它发起一次针对该目录的读取权限申请，而不是扩大为整个系统的无限权限。

## 6. 拟定的工程组织原则

建议 Linux 和 FPGA 使用同一个 Git 仓库：

- `linux/`：用户负责；
- `fpga/`：队友负责；
- `interface/`：双方共同维护，是最重要的接口合同；
- `tests/protocol/`：双方共同维护，用相同测试向量验证协议；
- `docs/`：记录赛题要求、架构、决策和联调日志；
- `local_refs/`：本机资料链接，不进入 Git。

第一阶段只创建最小骨架：

```text
anlogic-task3/
├── README.md
├── .gitignore
├── docs/
├── interface/
├── fpga/
├── linux/
├── tests/
└── local_refs/
```

暂定的完整方向如下，但还没有实际创建，也不应在架构确认前一次性铺满全部空目录：

```text
anlogic-task3/
├── README.md
├── .gitignore
├── docs/
│   ├── requirements.md
│   ├── architecture.md
│   ├── development-plan.md
│   ├── bringup-log.md
│   └── decisions/
├── interface/
│   ├── README.md
│   ├── protocol.yaml
│   ├── generated/
│   │   ├── fpga_protocol.vh
│   │   └── linux_protocol.h
│   └── test_vectors/
├── fpga/
│   ├── README.md
│   ├── rtl/
│   ├── sim/
│   ├── constraints/
│   ├── project/
│   └── scripts/
├── linux/
│   ├── README.md
│   ├── kernel/
│   │   └── pcie_fpga/
│   ├── dts/
│   ├── userspace/
│   │   ├── common/
│   │   ├── pipeline/
│   │   └── tools/
│   ├── tests/
│   ├── configs/
│   ├── deploy/
│   └── scripts/
├── models/
├── tests/
│   ├── protocol/
│   ├── sample_frames/
│   ├── expected/
│   └── performance/
├── tools/
├── local_refs/
├── build/
├── out/
└── logs/
```

建议 `.gitignore` 至少包含：

```gitignore
/local_refs/
/build/
/out/
/logs/
```

## 7. Linux/FPGA 接口需要尽早确定的内容

`interface/` 应由双方共同评审，至少需要明确：

- FPGA 到 RK3576 的物理/逻辑通道；
- PCIe BAR 的用途划分；
- DMA 缓冲区、描述符或环形队列布局；
- 帧头魔数和协议版本；
- `frame_id`；
- JPEG 或其他负载的实际字节长度；
- 图像宽度、高度和数据格式；
- 时间戳；
- 帧完成、中断和错误标志；
- 地址、长度及缓存对齐要求；
- 大小端；
- 超时、丢帧、队列满和复位恢复流程；
- 寄存器地址、位定义、复位值和读写属性；
- 最大帧大小及异常帧处理。

长期建议以 `interface/protocol.yaml` 或其他结构化文件作为单一事实来源，再生成：

```text
interface/generated/fpga_protocol.vh
interface/generated/linux_protocol.h
```

这样能避免 Linux 和 FPGA 手工维护两套常量后逐渐不一致。是否立即采用自动生成，需要结合团队时间和现有工程决定。

## 8. 建议进入 Ubuntu 后的第一批操作

### 8.1 收集环境信息，暂不修改原始资料

```bash
pwd
uname -a
lsb_release -a
codex --version
codex login status
find "$HOME" -maxdepth 2 -type d -printf '%p\n' | sort
```

最后一条可能输出较多；不要把包含个人隐私或订阅信息的目录内容直接发送到公开位置。

### 8.2 找到实际资料目录

重点寻找：

- RK3576 BSP、内核源码和交叉编译工具链；
- AFC03/AFH03 板卡资料；
- PCIe、MIPI、V4L2、RKNN 示例；
- 镜像、设备树、驱动和根文件系统构建脚本；
- 赛题 PDF 和厂商教程。

先只建立“资料路径清单”，不要立刻复制几百 GB 内容，也不要修改原始资料。

### 8.3 确认后再创建最小项目骨架

建议先让 Codex 只读分析目录和赛题，再决定最终骨架。若确认采用上述方案，可执行：

```bash
mkdir -p "$HOME/work/anlogic-task3"
cd "$HOME/work/anlogic-task3"
git init
```

之后再创建必要文件和目录。

## 9. 给 Ubuntu 内 Codex 的首条建议提示词

将本文件复制到 Ubuntu 后，可进入保存本文件的目录并启动 Codex，然后发送：

```text
请完整阅读“当前会话交接记忆_安路赛题3_UbuntuCodex_2026-09-13.md”。

我们参加嵌入式芯片与系统设计竞赛安路 FPGA 赛道赛题3。我负责
RK3576/Linux 部分，队友负责 FPGA 部分。厂商资料目前直接位于我的
Ubuntu 用户主目录下，不要移动、删除或修改原始资料。

本轮先只读工作，不创建工程、不修改文件：
1. 确认 Ubuntu、内核、Codex 和代理环境；
2. 帮我定位赛题 PDF、RK3576 BSP、交叉编译工具链和相关示例；
3. 列出 PCIe、MIPI、V4L2、RKNN 相关源码和文档路径；
4. 对照赛题3验证交接文件中的技术判断；
5. 给出最小工程骨架的调整建议；
6. 列出需要向 FPGA 队友确认的接口问题。

不要读取或输出 Clash 订阅、节点密码、~/.codex/auth.json、SSH 私钥等
敏感文件。若需要执行 sudo、安装软件、加载模块或修改系统配置，先说明
目的并请求我的明确批准。
```

## 10. 尚未完成的工作

- Ubuntu 内的正式工程目录尚未创建；
- `~` 下资料的准确路径清单尚未形成；
- 尚未确定最终采用 PCIe 字符设备、V4L2，还是二者分层共存；
- JPEG 帧协议、寄存器表和 DMA 队列尚未冻结；
- FPGA 队友的当前 RTL、数据格式和 PCIe 设计进度尚未同步进仓库；
- Linux BSP、内核版本、交叉编译方式和部署方法仍需确认；
- RKNN 模型、输入尺寸、预处理和性能目标仍需对照赛题确认；
- 尚未建立可重复的 FPGA/Linux 联合测试向量。

新会话应从“只读盘点环境和资料”开始，而不是立即编写最终驱动。
