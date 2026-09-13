# MLK-AFH03-AFC03（RK3576）首次上电与 Linux 基线检查清单

## 适用范围与执行边界

适用对象：`MLK-AFH03-AFC03-2GB LPDDR4X+32GB EMMC`（AFC03 核心板 + AFH03 底板）。赛题 3 要求 FPGA 采集 MIPI CSI、完成三项硬件预处理和 JPEG/LZ77 压缩，并经 MIPI 或 PCIe 向 RK3576 传输、由 NPU 本地运行目标检测；本清单只建立**首次上电和 Linux 只读基线**，不把课程示例中的具体视频节点或参数当作赛题要求。

本轮禁止：修改官方资料、安装软件、烧写系统、修改设备树、运行部署脚本、加载/卸载内核模块。所有板端命令均为只读查询；命令缺失时记录“命令不存在”，不要安装替代工具。

## 资料依据及使用方法

| 资料 | 具体页码/位置 | 本清单中的用途 |
|---|---|---|
| `docs/requirements/task3-requirements.md` | §1 R1--R7、§2、§5 Q1/Q5 | 判定赛题 3 的基线范围；其逐页原始依据为 `local_refs/problem/安路.pdf` PDF 页 17--18、24--25。 |
| `docs/hardware/platform-baseline.md` | §2--§5 | 已核对的板卡资源、PCIe/MIPI 限制及待确认风险；其下列官方手册页码是本清单的硬件依据。 |
| `01_硬件手册/MLK-AFH03-AFC03硬件使用手册.pdf` | PDF 页 5--6、24、29--31、38、43--44、55 | 板级供电、接口、串口、网口、摄像头、按键、内部 MIPI/PCIe。 |
| `01_硬件手册/MLK-AFC03核心板硬件使用手册.pdf` | PDF 页 5--6、9、11、15--16 | 指定内存/eMMC、核心板输入和复位/上电时序。 |
| `01_start/01_start_linux/01_prepare/2_PuTTY安装与使用.pdf` | PDF 页 10--11 | 官方 RK 串口接法（Type-C）及 1,500,000 baud、观察 U-Boot/Kernel 日志。 |
| `01_start/01_start_linux/02_test_board/1_Linux出厂系统测试.pdf` | PDF 页 1--2（目录）、4（系统启动） | 官方资料将出厂系统启动作为首项测试。 |
| `03_course/07_异构方案/AFC03_IMX415_PCIE_X1/米联客2026版异构AFC03教程-PCIE篇.pdf` | PDF 页 1、4--5 | 课程示例存在 PCIe/MIPI 异构链路、`/dev/video73` 和部署脚本；仅用来决定检查项目，不能执行其中烧写、`pcie_setup.sh`、安装或自启动步骤。 |

> 页码均指 PDF 阅读器的物理页码。没有明确页码的 Word 文档未作为依据；附近存在同主题 PDF 时优先使用 PDF。

## 1. 上电前实物准备

逐项确认实物状态并拍照记录，不连接或接通电源前完成接线。

- [ ] 开发板：AFH03 底板和 AFC03 核心板已装配牢固；核对核心板丝印、RK3576J、PH1A90SEG324，以及实物内存/eMMC 标称容量。资料标称 2 GB LPDDR4X、32 GB eMMC，但手册说明具体容量型号随销售情况变化，仍须以实物和系统枚举复核（核心板手册 PDF 页 5、9、11）。
- [ ] 电源：受稳压的 **12 V DC、额定不低于 3 A** 电源，供 AFH03 底板使用（组合手册 PDF 页 6）。不得把核心板单独的 5 V@3 A 输入规格误接到底板；核心板规格见核心板手册 PDF 页 6。
- [ ] 电源插头及极性：插头型号、内/外极性及与板上两个 DC-12V 接口的对应关系为**待确认**。已读硬件手册只写“2 路 DC-12V”及外部 12 V 输入，未给出极性（组合手册 PDF 页 55）；须以实物丝印和正式原理图确认，不能猜测。
- [ ] USB 数据线：一根支持数据的 Type-C 线，用于 RK 的 Type-C 串口；可另备一根用于后续受控的固件恢复排障，但本次不进入烧写（组合手册 PDF 页 24；PuTTY 教程 PDF 页 10）。
- [ ] 3.3 V USB 转 TTL：仅作为**备用**调试器。板载 RK 调试接口 J3 已是 Type-C 转串口，且信号为 3.3 V（组合手册 PDF 页 24），优先使用它；若必须接 TTL，接前须以原理图/实物确认连接器针脚，并交叉连接 TX↔RX、共地 GND，绝不把 5 V TTL 接入。J3 的实际针位映射为**待确认**。
- [ ] 网线：RJ45 网线及已知可用的交换机/DHCP 或隔离测试主机；板有两路千兆网口（P1/P2，组合手册 PDF 页 29）。
- [ ] 摄像头/FMC 扩展板：仅在机械、供电和接口已确认后接入。J8/J9 是接到 RK3576 的两路 4-lane CSI，包含 3.3 V/I2C/MIPI/时钟（组合手册 PDF 页 30--31）；赛题要求 FPGA 直接采集，因此 FPGA 侧传感器接入/FMC 转接方案仍是**待确认**，不可将 RK CSI 接口视为已经满足赛题要求。
- [ ] 其他必要配件：散热片/风扇（按环境温度与实物配置）、防静电措施、显示器和 HDMI 线（可选，仅观察）、记录启动日志的主机、标签纸/相机；如计划后续调 FPGA，另备专用 FPGA Type-C JTAG 线，但 JTAG 不支持热插拔（组合手册 PDF 页 43）。

## 2. 从硬件资料逐项确认

| 检查项 | 已确认结论 | 上电前动作 / 未明项 |
|---|---|---|
| 底板电源 | AFH03 底板输入 12 V@3 A，有两个 DC-12V 接口与一个 12 V ON/OFF 三脚电源开关（组合手册 PDF 页 6、55）。 | 断电检查电源额定值、插头和开关位置；两个输入口能否并用及开关方向丝印都须按实物确认。 |
| 电源极性 | 资料未写出 DC 插座中心正/负或端子针脚极性。 | **待确认**：只接受实物丝印/正式原理图的明确证据；未确认不得插电。 |
| RK 调试串口 | J3 为板载 Type-C 转串口；`UART_RXD`/`UART_TXD` 分别为 RK 输入/输出，IOSTANDARD 均为 3V3（组合手册 PDF 页 24）。 | Type-C 线接主机；无需、也不应向 J3 外加 5 V。J3 外露针脚排列未在该页给出，若不用 Type-C 则待确认。 |
| FPGA 串口/JTAG | FPGA 串口 J30 是 1.8 V；FPGA JTAG 也是 1.8 V，且不支持热插拔（组合手册 PDF 页 24、43）。 | 本清单不使用它们做 RK 启动日志；不要把 3.3 V TTL 接到 FPGA 串口。 |
| 官方 RK 串口速率 | 1,500,000 baud（PuTTY 教程 PDF 页 10）。 | 主机串口设置 1500000、8N1、无流控；若无可读输出，先复核线缆/端口/速率，不能凭猜测改板。 |
| 按键 | `SARADC_VIN1_KEY/RECOVERY`（RECOVER）、`SARADC_VIN0_BOOT`（BOOT）、`RESET_L`（复位）、`PWRON_L`（开关机）以及其他按键（组合手册 PDF 页 38）。 | 正常首次启动不按 RECOVER/BOOT；RESET 仅用于已记录的无响应恢复，不作为首选；具体按键位置以丝印确认。 |
| 固件下载口 | 完整 Type-C 的 `TYPEC0_OTG` 可下载固件（组合手册 PDF 页 24）。 | 本次不接入烧写流程、不按 BOOT/RECOVER。 |
| 上电时序 | 核心板输入为 5 V；RK 完成上电后通过 `VCC_3V3_S0` 使能 FPGA 第一级，故 RK 先于 FPGA 上电（核心板手册 PDF 页 15--16）。 | 不从其他接口反向供电；上电后观察是否有异常发热、异味、冒烟或异常电流，异常立即断开 DC 输入并保留记录。 |

安全核对：使用稳压、低纹波电源；不得改动核心板元件（组合手册 PDF 页 4，硬件手册“注意事项”）。确认模块、FMC、摄像头、USB 与网线均无金属异物和受力；板载 JTAG 不热插拔。首次只接“电源 + RK 串口”，先取得基线，再逐一增加网线、相机或扩展板。

## 3. 首次启动策略

1. [ ] 在断电状态连接 RK Type-C 串口，启动本地主机的日志记录；设置 1,500,000 baud、8N1、无流控。
2. [ ] 不按 BOOT、RECOVER 或烧录键，按实物确认的开关接通 12 V。若 eMMC 已有出厂 Linux，优先直接从现状启动。
3. [ ] 从加电前开始完整保存串口原始日志，直至出现登录提示并完成一次登录。日志必须保留 BootROM（若输出）、U-Boot 和 Kernel 全段；官方教程也明确上电时可观察 U-Boot 与 Kernel 启动信息（PuTTY 教程 PDF 页 11）。
4. [ ] 在确认出厂系统正常、分区布局与镜像版本均已取证前，**不烧写** boot/eMMC/FPGA，也不执行课程里的 `pcie_setup.sh`、`insmod`、安装、网络同步或自启动操作。PCIe 课程示例的相关动作在 PDF 页 4--5，仅作风险提示。
5. [ ] 成功登录后，执行第 4--5 节的只读命令并保存输出。先不插摄像头/FMC 也可完成系统基线。
6. [ ] 若无法启动：保留完整首次日志，记录电源、开关、接线和 LED 状态；只进行非侵入性排查（电源规格/极性、串口端口与速率、开关、插座接触、BOOT/RECOVER 是否误按）。确认出厂系统确实不能启动后，另行建立并获批准的烧写排障步骤；本清单到此为止。

## 4. 首次登录后：只读 Linux 基线命令

先在主机将每条命令的标准输出和错误输出分别存档；不重定向到板端、不改任何文件。以下命令不依赖固定 `/dev/video*` 编号。

```sh
# 身份、系统与内核
date -Is
uname -a
cat /etc/os-release
cat /proc/version
cat /proc/cmdline

# 板型 / 当前设备树（NUL 结尾属性须去除 NUL）
tr -d '\0' < /proc/device-tree/model; echo
tr -d '\0' < /proc/device-tree/compatible; echo

# CPU、内存与 eMMC；lsblk 不存在时也只记录错误，不安装
lscpu
cat /proc/cpuinfo
free -h
cat /proc/meminfo
lsblk -o NAME,MAJ:MIN,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,PARTUUID,MOUNTPOINTS
cat /proc/partitions
findmnt
mount
cat /proc/cmdline

# 分区表（只读；对实际已发现的 eMMC 块设备执行，勿假定名称）
find /sys/class/block -maxdepth 1 -type l -printf '%f\n' | sort
for d in /sys/class/block/mmcblk*; do
  [ -e "$d" ] || continue
  printf '\n== %s ==\n' "$(basename "$d")"
  cat "$d/size" 2>/dev/null
  cat "$d/device/name" 2>/dev/null
done

# 网络接口、地址、路由；不执行 dhcp/ifup/ifdown/ping 压测
ip -br link
ip -br address
ip route
for n in /sys/class/net/*; do
  [ -e "$n" ] || continue
  printf '\n== %s ==\n' "$(basename "$n")"
  cat "$n/address" "$n/operstate" 2>/dev/null
done

# 视频 / media：无设备也须保存“无匹配”结果
find /dev -maxdepth 1 \( -name 'video*' -o -name 'media*' -o -name 'v4l-subdev*' \) -printf '%f\n' | sort
for n in /sys/class/video4linux/video*; do
  [ -e "$n" ] || continue
  printf '\n== /dev/%s ==\n' "$(basename "$n")"
  cat "$n/name" 2>/dev/null
  readlink -f "$n/device" 2>/dev/null
done
command -v media-ctl && media-ctl -p

# PCIe：lspci 不存在时记录该事实；不重新扫描、不 bind/unbind
command -v lspci && lspci -nnk
find /sys/bus/pci/devices -maxdepth 1 -mindepth 1 -printf '%f\n' | sort
for d in /sys/bus/pci/devices/*; do
  [ -e "$d" ] || continue
  printf '\n== %s ==\n' "$(basename "$d")"
  cat "$d/vendor" "$d/device" "$d/class" 2>/dev/null
  readlink -f "$d/driver" 2>/dev/null
done

# 已加载模块和启动错误（只读）
cat /proc/modules
dmesg -T
dmesg -T -l emerg,alert,crit,err,warn
```

备注：`dmesg` 若受 `kernel.dmesg_restrict` 限制，应记录权限错误而非更改 sysctl。`lscpu`、`lsblk`、`findmnt`、`ip`、`lspci`、`media-ctl` 是“若出厂镜像已有则运行”的工具；不存在时不得安装。`/dev/video73`、`/dev/video22` 等只可在实际枚举后记录，绝不预设。

## 5. 赛题 3 直接相关的只读检查

| 核对项 | 只读命令/判定 | 依据与记录要求 |
|---|---|---|
| 当前视频节点 | 执行第 4 节的 `/dev/video*`、`/sys/class/video4linux` 枚举；记录节点、驱动名称和是否存在。 | 课程曾使用 `/dev/video73`，但其为示例而非赛题要求（PCIe 教程 PDF 页 4）；赛题只要求 FPGA 采集和到 RK 的选定高速通道（`task3-requirements.md` §1 R2/R5，原始赛题 PDF 页 18）。 |
| PCIe1 是否由当前 DT 启用 | `find /proc/device-tree -type d -iname '*pcie1*' -print`；对找到目录逐一运行 `tr -d '\0' < <目录>/status`（缺少 `status` 通常表示默认 `okay`，但须记录为“属性缺失、需结合 DTS/内核确认”）；再比对 `dmesg -T | grep -Ei 'pcie|pcie1'`。 | 内部 RK--FPGA PCIe 物理连接存在，但资料对 2.0x1/3.0x1 表述冲突，角色、速度与 BSP 均待确认（组合手册 PDF 页 44；`platform-baseline.md` §3、§5 H1）。DT 节点存在不等于链路已训练。 |
| FPGA 是否被 PCIe 枚举 | `lspci -nnk` 和 `/sys/bus/pci/devices` 输出中，记录 BDF、vendor/device ID、class、driver。 | 只在实际识别到 FPGA 时填写“已枚举”；未出现不能以课程示例脚本补救。 |
| 是否已有 Anlogic/Milianke 驱动 | `cat /proc/modules | grep -Ei 'anlogic|milianke|pci'`; `find /sys/module -maxdepth 1 -mindepth 1 -printf '%f\n' | grep -Ei 'anlogic|milianke|pci'`; `dmesg -T | grep -Ei 'anlogic|milianke|pci'`。 | 记录模块名、版本（若 `/sys/module/<name>/version` 存在）和 dmesg 探测结果；不得 `modprobe`/`insmod`/`rmmod`。课程示例须执行脚本编译/安装/绑定驱动（PCIe 教程 PDF 页 4--5），本轮明确不执行。 |
| MIPI 与摄像头 media topology | `command -v media-ctl && media-ctl -p`；同时保存 `/dev/media*`、`/dev/v4l-subdev*`、`/dev/video*` 枚举及 `dmesg -T | grep -Ei 'mipi|csi|isp|rkcif|rkisp|camera'`。 | J8/J9 是 RK 的 CSI0/CSI1 摄像头接口（组合手册 PDF 页 30--31）；内部 FPGA→RK 为 FPGA DSI TX→RK CSI 的 4-lane 物理链路（组合手册 PDF 页 43--44），协议/驱动可行性待确认。 |
| RKNN 运行时与 NPU 驱动 | `find /usr /lib /opt -maxdepth 5 -type f \( -iname '*rknn*' -o -iname '*rknpu*' \) -print 2>/dev/null`; `find /sys/module -maxdepth 1 -mindepth 1 -printf '%f\n' | grep -Ei 'rknpu|npu'`; `dmesg -T | grep -Ei 'rknn|rknpu|npu'`; 对找到的模块执行 `cat /sys/module/<name>/version 2>/dev/null`。 | 记录“已发现路径/模块/版本”或“未发现”；不要安装 Python wheel 或运行模型。平台 NPU 标称 6 TOPS（核心板手册 PDF 页 5），不代表出厂系统已含 RKNN runtime。 |

为避免把 shell 管道错误当作硬件结果，建议每项使用以下形式保存：`命令原文、日期、退出码、完整标准输出、完整标准错误、操作者、板卡/电源/镜像标识`。PCIe1 的 `status` 循环可在发现路径后手工执行，例如：

```sh
# 将 <pcie1-dt-dir> 替换为上一命令实际输出的目录；仅读取属性
tr -d '\0' < <pcie1-dt-dir>/status; echo
```

## 6. 必须保存的证据包

- [ ] `serial-first-power-on.log`：从上电前开始的完整原始串口日志，覆盖 BootROM（若有）、U-Boot、Kernel、登录提示和首个登录时刻；不得剪裁报错。
- [ ] `linux-baseline-YYYYMMDD-HHMMSS/`：第 4、5 节每条命令的完整 stdout/stderr/退出码，以及工具缺失或权限受限的原始报错。
- [ ] `device-tree/`：`model`、`compatible`、`/proc/cmdline`、PCIe1 节点路径/`status` 属性、相关 PCIe/MIPI dmesg 行。若后续经批准导出完整 DTB，另存其 SHA-256；本轮不写出板端文件。
- [ ] `storage/`：`lsblk`、`/proc/partitions`、`findmnt`、`mount`、发现的 eMMC sysfs 名称/容量，及根文件系统来源（`/proc/cmdline`）。
- [ ] `firmware-version/`：`/etc/os-release`、`uname -a`、`/proc/version`、完整 `dmesg -T`；如日志/系统明确打印 U-Boot、ATF、BootROM、固件或 RKNN/NPU 版本，逐行原样保存并标明来源。未打印的版本标记“待确认”，不得推断。
- [ ] `hardware-photos/`：核心板及底板丝印、12 V 电源铭牌/插头极性证据、接线、开关位置、所接扩展板；敏感序列号可单独受控保存。

## 7. 首次检查结论记录（待填写）

| 项目 | 结果 | 证据文件 | 备注 |
|---|---|---|---|
| 出厂 eMMC Linux 可正常启动 | 待执行 |  |  |
| 实际内存 / eMMC 容量 | 待执行 |  |  |
| 板型 model / compatible | 待执行 |  |  |
| 已发现视频 / media 节点 | 待执行 |  | 不预设节点号。 |
| PCIe1 DT 状态 | 待执行 |  |  |
| FPGA 的 PCIe 枚举状态 | 待执行 |  |  |
| Anlogic/Milianke 驱动状态 | 待执行 |  |  |
| MIPI/media topology | 待执行 |  |  |
| RKNN runtime / NPU 驱动版本 | 待执行 |  |  |
| 电源插头极性和 DC 口确认 | 待确认 |  | 必须有实物丝印或正式原理图证据。 |
