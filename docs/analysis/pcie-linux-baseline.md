# 官方 PCIe Linux 数据链路基线

## 范围、证据等级与结论边界

本文件只分析课程包 `AFC03_IMX415_PCIE_X1` 的 Linux 侧示例，作为赛题 3 的**可复用基线**，并不把课程示例参数升级为赛题要求。赛题要求的是 FPGA 向 RK3576 稳定传送**压缩图像帧**，PCIe/MIPI 二选一；未规定 RGB24、1080p、设备节点或 PCIe 代际，[需求基线](../requirements/task3-requirements.md) 第 2 节已有明确说明。

标记含义：

- **[事实]**：可直接由下列官方源码、脚本、设备树或教程 PDF 确认。
- **[推断]**：根据代码控制流做出的工程解释，须用板上实测确认。
- **[未知]**：资料未给出或资料彼此冲突，不能据此定案。

文中“源码:行”均相对于 `local_refs/official_package/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/deploy/`；设备树行号相对于其文件。官方资料在本次分析中只读，未执行其中脚本、未编译或加载模块。

## 1. 完整数据流与角色

```text
IMX415 / FPGA 视频流水
  └─ FPGA PCIe Endpoint 的 AXI-Stream C2H 输入 + 用户 BAR 寄存器
       ├─ PCIe x1 链路 ──> RK3576 PCIe1 Root Complex（枚举、分配 BAR）
       ├─ anlogic_pci.ko：PCI ID 绑定、映射 BAR、建立 SGDMA 引擎/字符设备
       │    ├─ /dev/*_c2h_0：直接 DMA read/ioctl
       │    └─ 导出的 sgdma_xfer_submit() / user BAR 指针
       └─ milianke_v4l2.ko：取得同一 PCI 设备和 C2H0
            └─ vb2 连续 DMA buffer ← SGDMA C2H DMA ← FPGA 流
                 └─ /dev/videoN → V4L2/OpenCV/GStreamer → RGB 转换、YOLO RKNN 推理
```

- **[事实]** V4L2 包装层说明数据经 `sgdma_xfer_submit -> C2H` 直接写入 vb2 buffer，无中转缓冲和 memcpy（`v4l2_drv/milianke_v4l2_zerocopy.c:3-12,461-507`）。它使用 C2H channel 0、`write=false`、端点地址 0（同文件:462-464）。
- **[事实]** 应用程序通过 OpenCV V4L2 打开视频节点、读帧、BGR→RGB、letterbox 后调用 RKNN 推理（`rk3576_yolov5s_pcie.py:222-259`）。教程 PDF 也把它描述为“FPGA 预处理 + PCIe/MIPI + RK3576 AI”的课程链路（PDF 第 1 页；可由 `pdftotext` 文本第 4-14 行定位）。
- **[事实]** RK3576 `pcie1` DTS 节点是 standard PCI host 形式（`device_type = "pci"`）、拥有 MSI/sys/pmc/msg/legacy/err 中断并配置 x1、`max-link-speed = <2>`（`dts/rockchip/rk3576.dtsi:4293-4338`）；覆盖文件直接注释该端连 “Anlogic FPGA Endpoint”（`dts/rockchip/rk03/pcie.dtsi:85-89`），延迟 rebind 脚本也称“FPGA EP”（`pcie1_rebind.sh:2-4,19`）。
- **结论 [事实]**：本官方示例中 **RK3576 是 PCIe RC（Root Complex/Host），FPGA 是 EP（Endpoint）**。FPGA 端具体 PCIe IP 配置、BAR/SGDMA RTL 实现不在给定 Linux 源码中，故不可由此进一步确认。

## 2. 枚举、PCI ID、驱动匹配与 BAR

### 2.1 PCI ID 与模块依赖

- **[事实]** `anlogic_pci.ko` 仅以 `PCI_DEVICE(0x1edb, 0xabcd)` 注册 PCI ID table，并以 `MODULE_DEVICE_TABLE(pci, ...)` 供内核匹配（`sgdma_drv/anlogic_pci_drv.c:48-61,296-300`）。`pcie_setup.sh` 同样以 `lspci -d 1edb:abcd` 查找（`pcie_setup.sh:192-202,234-237`）。
- **[事实]** `milianke_v4l2.ko` 不是 PCI bus driver；模块初始化时 `pci_get_device(0x1edb, 0xabcd, NULL)` 查找已枚举设备，并从已绑定的 SGDMA driver data 取得 SGDMA handle 和 user BAR。故它必须在 `anlogic_pci.ko` 成功加载后加载（`v4l2_drv/milianke_v4l2_zerocopy.c:39-41,750-775`；`sgdma_drv/anlogic_pci_drv.c:148-183`）。
- **[推断]** 若同一 ID 出现非 FPGA 设备，脚本的“任意 lspci 第一项”回退（`pcie_setup.sh:196-202,246-249`）可能选错设备/BAR；实际部署应坚持 ID+BDF 校验。

### 2.2 BAR 用途、地址与寄存器

| 项目 | [事实] 课程代码所示用途 | 来源 |
|---|---|---|
| user BAR（脚本称 BAR0） | FPGA 视频/相机控制、状态和尺寸寄存器；V4L2 通过 `anlogic_get_user_bar()` 取得内核 ioremap 指针 | `anlogic_pci_drv.c:162-183`; `milianke_v4l2_zerocopy.c:770-789` |
| config BAR | SGDMA 驱动创建 `*_control` 节点时使用 `config_bar_idx` | `anlogic_pci_cdev.c:469-480` |
| SGDMA register BAR | 诊断脚本称 BAR1，并读 H2C0/C2H0 控制/状态偏移；驱动具体选择由 IP 的 BAR 枚举决定 | `diag_regs.sh:20-24` |
| BAR 物理基址 | RK3576 setup 优先从 `/sys/bus/pci/devices/0000:$BDF/resource` 第一行动态取得；RK3588 分支和诊断脚本仍含 `0xf0200000` 固定回退 | `pcie_setup.sh:17-26,244-264`; `test_1080p.sh:5-13`; `diag_regs*.sh:3` |

视频 user-BAR 已命名寄存器如下。含义以 V4L2 宏及诊断脚本为准；未提供 RTL，除已注释 bit 外不可臆测更多 bit 语义。

| 偏移 | 名称/用途 | 证据 |
|---:|---|---|
| `0x40` | TPG status | `milianke_v4l2_zerocopy.c:44`; `diag_regs2.sh:7` |
| `0x44`, `0x48` | 当前 width, height | `milianke_v4l2_zerocopy.c:45-46,613-617` |
| `0x4c` | pixel format（诊断名） | `diag_regs2.sh:10` |
| `0x50` | frame count | `milianke_v4l2_zerocopy.c:47`; `diag_regs2.sh:11` |
| `0x54`, `0x58`, `0x5c` | FPS config、bytes/frame、version（诊断名） | `diag_regs2.sh:12-14` |
| `0x60` | CTRL：bit0 `reg_enable`，bit1 `soft_reset` | `milianke_v4l2_zerocopy.c:48,648-655` |
| `0x64` | padded frame bytes，作为 DMA read size | `milianke_v4l2_zerocopy.c:49,616-626` |
| `0x68`--`0x7c` | drop/pattern/delivered/debug/pixel/DMA beat 诊断项 | `diag_regs2.sh:17-22` |
| `0x80`, `0x84`, `0x88`, `0x8c` | source/camera status/frame count/error | `milianke_v4l2_zerocopy.c:50`; `diag_regs2.sh:25-28` |
| `0x90` | camera mode：0=1080p、1=4K、2=720p | `milianke_v4l2_zerocopy.c:51,71-75,241-260` |
| `0x94`, `0x98` | drop-detect count、AE gain；gain 范围 0--1023 | `diag_regs2.sh:30-31`; `milianke_v4l2_zerocopy.c:52,157-169,807-810` |

**控制流程 [事实]**：setup 把 `CAM_MODE=0`、gain=100、CTRL.bit0=1（`pcie_setup.sh:288-299`）。V4L2 开流时重读 width/height/padded bytes，写 CTRL.bit1 软复位，DMA 线程首次提交前写 CTRL.bit0；停流写 0（`milianke_v4l2_zerocopy.c:439-447,613-665,685-705`）。切换格式时会写 `CAM_MODE`，但只允许非 streaming 期间（同文件:217-263）。

## 3. SGDMA 字符设备与接口

### 3.1 节点

- **[事实]** 源码定义的节点模板为 `ANLOGIC-PCI%d_control`、`ANLOGIC-PCI%d_user`、`ANLOGIC-PCI%d_h2c_%d`、`ANLOGIC-PCI%d_c2h_%d`，以及可能的 `...events_%d`（`sgdma_drv/anlogic_pci_cdev.c:27-49`）。每个实际探测出的 H2C/C2H engine 创建一个节点（同文件:462-524）；最多值初始为各 4，但实际数由 IP probe 更新（`anlogic_pci_drv.c:91-94`）。
- **[未知]** 节点实际名称不能仅据源码保证：部署诊断脚本检查 `/dev/sgdma0_c2h_0`（`diag_dma_test.sh:24-37`），与当前源码模板 `ANLOGIC-PCI0_c2h_0` 不一致。须在板上加载后的 `/dev` 和 dmesg 确认，不能把任一名称写死。

### 3.2 数据、控制、mmap、poll/read

- **[事实]** H2C 节点 `write()`、C2H 节点 `read()` 将用户页映射为 SG 表，调用 `sgdma_xfer_submit()`；`lseek` 的文件位置充当 endpoint 地址。普通 read/write 路径按引擎方向校验并等待 DMA 完成（`sgdma_drv/cdev_sgdma.c:51-94,164-245`）。
- **[事实]** SGDMA 节点 ioctl：性能开始/停止/读取、地址模式 set/get（set 当前返回 `-ENOSYS`）、对齐查询、aperture R/W 和自定义描述符读写；代码号/结构体见 `sgdma_drv/cdev_sgdma.h:49-99`，分派见 `cdev_sgdma.c:644-680`。自定义读写允许每描述符长度不同，返回 `done/error`（`cdev_sgdma.c:520-641`）。
- **[事实]** control/user 节点有 32-bit BAR `read/write`、BAR mmap、以及 INFO、online/offline、单/批 BAR 读写、PCI config R/W ioctl（`sgdma_drv/cdev_ctrl.c:100-112,160-304,306-379`; 接口定义 `cdev_ctrl.h:62-146`）。源码虽有参数 `bar_id`，但此处未见边界检查，用户态不应把它当作安全的通用硬件 API。
- **[事实]** events 节点支持阻塞 `read()`（要求 4 bytes）和 `poll()`，由 user IRQ 唤醒（`sgdma_drv/cdev_events.c:26-113`）。普通 SGDMA 节点 file operations 在已审阅范围内未注册 `.poll` 或 `.mmap`；control/user 才注册 `.mmap`（`cdev_ctrl.c:371-379`）。

### 3.3 中断模式与轮询模式

- **[事实]** `poll_mode` 模块参数默认 0，描述为 1 使用硬件轮询、0 使用中断（`sgdma_drv/anlogic_pci_lib.c:40-42`）。值为 1 时分配 writeback、创建轮询线程，并明确跳过 MSI/MSI-X/IRQ setup；值为 0 时启用 MSI/MSI-X、设置 IRQ 和 channel/user interrupt（同文件:4518-4545；`pcie_setup.sh:266-274` 以 `poll_mode=1` 加载）。
- **[推断]** 轮询减少中断依赖但消耗 CPU/可能增加调度影响；中断空闲开销较低、依赖 MSI/MSI-X 路径可用。二者的吞吐和延迟不能从源码确定，应同一 payload/帧率在板上测量。
- **[事实]** V4L2 自己还会在“无已排队 vb2 buffer”时以 500--1000 µs sleep 轮询队列（`milianke_v4l2_zerocopy.c:449-459`）；这与 SGDMA 的 `poll_mode` 是不同层次。

## 4. V4L2：一帧、缓冲区和用户接口

### 4.1 一帧如何由 DMA 得到

1. **[事实]** 用户 `REQBUFS`/`QBUF` 后，vb2 使用 `vb2_dma_contig_memops`，每 buffer 建一个单-entry SG table，地址来自 `vb2_dma_contig_plane_dma_addr()`（`milianke_v4l2_zerocopy.c:546-580,824-834`）。
2. **[事实]** 开流读 FPGA 的 width/height/padded bytes，设置 `read_size`，使 C2H0 的 EOP flush 生效，软复位 FPGA 并启动 kthread（同文件:608-665）。
3. **[事实]** kthread 从 `buf_list` 取已排队 buffer，调用 `sgdma_xfer_submit(sgdev, 0, false, 0, ...)`；数据 DMA 到该 vb2 物理连续内存（同文件:449-464）。
4. **[事实]** 该实现把 `xfer_len >= pixel_bytes * 99%` 当作一帧，写 timestamp/sequence、把 payload **固定报告为** `pixel_bytes`，再 `vb2_buffer_done(DONE)`（同文件:426-507）。小于半帧的 EOP fragment 会重新入队；介于半帧与 99% 的短帧也重入队（同文件:474-491）。

### 4.2 申请、排队、完成与释放

- **[事实]** 单平面 buffer 大小为 `max(pixel_bytes, read_size)`，buffer 数限定 4--8（`milianke_v4l2_zerocopy.c:518-544`）；`buf_prepare` 检查容量，`buf_queue` 加入自旋锁保护的链表（同文件:583-606）。
- **[事实]** 成功 DMA 后 `DONE` 交回 userspace，用户 `DQBUF`/消费后再 `QBUF`；ioctl 表直接采用 vb2 的 reqbuf/querybuf/qbuf/dqbuf/streamon/streamoff helpers（同文件:390-414,499-507）。
- **[事实]** stop 时停 kthread，将仍在队列中的 buffer 标为 `ERROR`，关闭 FPGA pipeline；buffer 销毁时释放 SG table（同文件:572-581,685-708）。
- **[事实]** V4L2 还提供 `read`、`mmap`、`poll`（vb2 helpers）和 MMAP/DMABUF/READ IO modes（同文件:727-735,824-827）；video node 由 `video_register_device(..., -1)` 动态分配，故 `/dev/videoN` 不固定（同文件:853-861）。

## 5. 当前固定假设与冲突

| 类别 | 固定/回退假设 | 证据与风险 |
|---|---|---|
| RGB24 | `BPP=3`，唯一枚举 `V4L2_PIX_FMT_RGB24`，sRGB | `milianke_v4l2_zerocopy.c:54-55,192-214`；不适合直接表达 JPEG payload |
| 分辨率/帧率 | 表只有 1920×1080@60、3840×2160@30（禁用）、1280×720@60；默认/回退为 1080p | 同文件:60-78,217-293,342-388 |
| 帧大小 | `W*H*3`，DMA size 用 64-byte 行对齐 padded bytes，99% 阈值，payload 强报 `pixel_bytes` | 同文件:426-507,613-626 |
| V4L2 节点 | 教程/Python 固定 `/dev/video73`，setup/test 仅在发现失败时回退 `/dev/video1` | PDF 第 1/测试章节；`rk3576_yolov5s_pcie.py:4,14`; `pcie_setup.sh:315-320`; `test_1080p.sh:36-41` |
| SGDMA 节点 | 诊断脚本固定 `/dev/sgdma0_c2h_0`，却与源码模板不一致 | `diag_dma_test.sh:24-37`; `anlogic_pci_cdev.c:39-49` |
| PCIe 代际 | DTS `max-link-speed=<2>`，V4L2 注释按 x1 Gen2 约 350 MB/s 限制 4K；但硬件基线记录板卡资料称 2.0×1 与 3.0×1 冲突 | `rk3576.dtsi:4322-4323`; `milianke_v4l2_zerocopy.c:60-63`; [硬件基线](../hardware/platform-baseline.md) H1 |
| BAR 地址 | `0xf0200000`（BAR0）和 `0xf0400000`（BAR1）出现在诊断/回退脚本 | `diag_regs.sh:3,20`; `test_1080p.sh:10`；RC 枚举后 BAR 可变，必须动态发现 |
| BDF/硬件状态 | rebind 脚本以 `21:00.0` 判断成功 | `pcie1_rebind.sh:13-16,34-40`；BDF 也应动态发现 |

另有一个跨层不一致：V4L2 仅允许 RGB24，而 YOLO 脚本先尝试 `YUYV` 再 `RGB3` 并固定请求 1280×720@30（`rk3576_yolov5s_pcie.py:14-17,222-236`）。**[推断]** 该脚本能否成功依赖 OpenCV/V4L2 实际协商结果；不能从源码证明它与该 V4L2 wrapper 在所有版本上兼容。

## 6. 改为可变长度 JPEG 的影响

### 可复用与必须改造

- **可复用 [推断]**：若 FPGA 保持同一 PCIe EP、Vendor/Device ID、BAR 枚举和 AXI-Stream C2H SGDMA IP，RC 枚举、`anlogic_pci.ko` 的 PCI 匹配、DMA 描述符提交、C2H transfer、poll/IRQ 机制均可复用。`sgdma_xfer_submit()` 返回实际完成字节数，底层具备承载可变长度 transfer 的能力（`anlogic_pci_lib.c:2877-3116`）。这不表示已有帧边界语义足够。
- **必须改造 [事实+推断]**：当前 V4L2 强设 RGB24、`W*H*3`、固定 padded size、99% 原始帧阈值，并把真实 transfer length 丢弃为 `pixel_bytes`（`milianke_v4l2_zerocopy.c:54-78,426-507,518-626`）。JPEG 必须改为以 header/descriptor 提供的 `payload_len` 完成一帧、容量上限检查、跨 DMA fragment 拼接或明确“一帧一 EOP”、错误/丢帧处理，以及把 bytesused 报为真实 JPEG 长度。还要定义宽高、帧号、时间戳、校验与背压；这些是赛题工程推导，不是当前示例已有协议。
- **[未知]** FPGA 当前 tlast/EOP 是否准确代表帧末、是否能给出长度/metadata、单 JPEG 是否会跨描述符或 DMA transfer，均不能由 Linux 资料确认；当前 raw 示例甚至为伪 tlast 采取“99% 接收、碎片丢弃”规避（同文件:426-435,631-640）。

### 是否仍应包装 V4L2

**建议 [推断]**：JPEG 若目标是标准视频/相机生态，可继续 V4L2，但应把节点设计为 compressed capture（例如 MJPEG 语义，前提是实际 payload 确为兼容 JPEG），正确报告 `bytesused` 和格式；若是赛题自定义帧头/非标准 JPEG/需要可靠 metadata 和流控，优先使用 SGDMA 字符设备之上的小型自定义用户态接收库/服务。不要把非 raw payload 伪装成 RGB24。

| 路线 | 优点 | 代价/适用性 |
|---|---|---|
| 直接 SGDMA 字符设备 | 最接近 DMA；可获得实际 read 长度；帧协议完全自主 | 用户态负责 buffer、帧重组、poll/线程、错误恢复；节点名/API 需封装稳定 |
| V4L2 compressed capture | `v4l2-ctl`、GStreamer/OpenCV 等生态兼容；vb2/DMABUF 缓冲管理成熟 | 要正确实现可变 `bytesused`、帧边界和 compressed format；不适合私有协议硬伪装 |
| 自定义用户态接口（封装 SGDMA） | 迭代快；头部、版本、统计、JPEG 解码/NPU 输入可共同演进 | 非通用设备 API；须自管 ABI、性能、权限和测试 |

## 7. 无硬件静态检查与接板最小验证

### 不接硬件可做（本轮未执行编译）

1. `bash -n` 检查 `pcie_setup.sh`、`test_1080p.sh`、诊断脚本；同时人工审查其会写 sysfs/加载模块，不能作为无硬件测试执行。
2. `python3 -m py_compile rk3576_yolov5s_pcie.py`，检查用户程序语法；不导入 `cv2/rknnlite`，避免环境依赖。
3. 用 `rg`/代码审查核对 Vendor/Device ID、节点模板、BAR 偏移、V4L2 格式、固定尺寸与脚本回退值的一致性；本文件已发现节点名和 BAR/代际假设风险。
4. 对 DTS 做只读文本/语法检查（若已有独立 `dtc` 和完整 include 环境，可在临时输出目录检查；本轮不安装依赖也不生成/替换 DTB）。重点确认最终构建链确实 include `rk03/pcie.dtsi`，而不是仅审查片段。
5. 编写纯用户态 JPEG 帧解析单元测试（伪造 length/header、截断、超长、跨片），但在接口协议冻结前不应假设字段格式。

### 接板后的最小顺序（仅步骤建议，未执行）

1. 只读确认实际 DTS status、`/sys/bus/platform/drivers/rk-pcie` 绑定状态和 `lspci -nn`；确认枚举出的设备确为 `1edb:abcd`，记录实际 BDF、Link Status 的 speed/width。
2. 从该 BDF 的 sysfs `resource` 读取 BAR 起始/范围，避免 `0xf0200000`/`0xf0400000`；只读比对 version/status/width/height 寄存器是否合理。
3. 在获授权加载驱动后，核对 dmesg 中 SGDMA 实际 H2C/C2H 数和 poll/IRQ 状态，枚举实际 `/dev/ANLOGIC-PCI*` 或其它 udev 节点；先做小、受控 C2H read，再读 DMA 状态/错误计数。
4. 确认 FPGA stream 的 EOP/完成长度稳定后，再加载 V4L2，使用动态发现的 `/dev/videoN` 做 `QUERYCAP`、format/framesize 枚举、少量 buffer capture；核对 `bytesused`、sequence、drop/error。
5. 最后接 GStreamer/OpenCV 与 NPU，逐段记录链路速率、DMA 完成长度、帧率和端到端时间戳。对 JPEG，先验证逐帧完整性/解码，再接推理。

## 8. 当前无法确认的关键项

- **[未知]** 最终板卡 PCIe 实际协商代际/速率：DTS/驱动示例按 Gen2，而硬件资料存在 PCIe 2.0×1 与 3.0×1 的冲突（[硬件基线 H1](../hardware/platform-baseline.md)）。只能读 `lspci -vv`/Link Status 和实测确认。
- **[未知]** FPGA EP 的 BAR 数量、每个 BAR 的大小、user/config/DMA BAR 的真实映射和全部寄存器 bit 定义；Linux 代码只能显示软件的使用假设。
- **[未知]** SGDMA 硬件实际探测出的 channel 数、MSI/MSI-X 是否可用、events user IRQ 是否由 FPGA 实现，以及课程模块和当前 Linux kernel/BSP 的 ABI 兼容性。
- **[未知]** V4L2 的固定 raw 示例是否对应提供的 bitstream 的真实 output；课程包中 V4L2 注释提及 spurious tlast，说明其正确性不应只由代码宣称判定。
- **[未知]** JPEG 的最大长度、每帧/分片边界、长度字段/校验/背压/重传和标准 JPEG 兼容程度；这些必须由 FPGA 与 Linux 共同冻结接口文档，不能从本课程 raw RGB 示例推导。

## 9. 最重要的五个发现

1. 官方路径是 RK3576 RC 枚举 FPGA EP；V4L2 只是建立在 SGDMA C2H0 上的包装层，不是独立 PCI driver。
2. 当前 V4L2 是 raw RGB24 定长帧实现：DMA 实际长度被 99% 阈值过滤并最终强报为 `W×H×3`，不能直接接收可变长度 JPEG。
3. SGDMA 底层 transfer API/字符设备具备按实际完成字节返回的基础，PCIe/SGDMA 大部分可复用；JPEG 的核心缺口是明确帧 metadata、边界与 buffer 生命周期。
4. `pcie_setup.sh` 强制 `poll_mode=1`，因此实际示例绕开 MSI/MSI-X/IRQ setup；V4L2 自身还另有 buffer-list 轮询，二者不可混为一谈。
5. 课程资料中的 `/dev/video73`、`/dev/sgdma0_c2h_0`、BDF `21:00.0` 和 BAR `0xf0200000` 都不是可靠平台常量；其中 SGDMA 节点名甚至与所附源码模板不一致，必须动态发现并板上验证。
