# 0002：SGDMA 字符设备优先承接 JPEG

- 状态：**Proposed（DRAFT，未接受）**
- 日期：2026-09-13
- 决策方：Linux 与 FPGA 双方共同确认
- 关联：[0001](0001-pcie-primary-mipi-fallback.md)、[PCIe JPEG 帧协议 v0.1](../../interface/pcie-jpeg-protocol-v0.1.md)

## 决策

在 PCIe 主链路的第一版中，Linux 侧优先使用官方 SGDMA 驱动创建的 C2H 字符设备，由自定义用户态接收库/服务接收、校验和解码 JPEG；暂不复用固定 RGB24 的 V4L2 包装层。第一版允许轮询；MSI/MSI-X 与 V4L2 MJPEG 均留作后续、实测驱动的演进项。

这不是对 PCIe 代际、BDF、BAR 地址、设备节点名、DMA 通道数或硬件参数的决定；它们保持 **TBD**，在实机枚举和双方联调后记录。

## 依据与边界

**官方源码事实（只读审查）：**

- 课程示例中 RK3576 为 PCIe RC，FPGA 为 EP；`anlogic_pci.ko` 匹配并探测 SGDMA 引擎、创建实际发现的 H2C/C2H 字符设备。
- C2H `read()` 把用户页构成 SG 表并调用 `sgdma_xfer_submit()`；该 API 返回完成字节数。SGDMA 支持轮询和 IRQ 模式，课程 setup 使用 `poll_mode=1`。
- 现有 V4L2 wrapper 将格式固定为 RGB24、帧大小固定为 `width*height*3`（并使用 padded-size/99% 阈值），完成后也固定报告该 bytesused；这不是可变长度 JPEG 的正确语义。
- 源码和脚本对 `/dev` 节点模板/实际名称存在不一致，且 BDF、BAR 地址、PCIe speed 不可写死，必须动态发现。

**本项目建议：** JPEG 使用版本化帧头、真实 `payload_length`、序号、校验和明确 slot 所有权。SGDMA 仅作为传输机制；帧边界、metadata、背压和恢复不会由现有 raw V4L2 示例自动提供。

**TBD：** FPGA 的 BAR/RTL、EOP 是否一帧一个、最大 JPEG 长度、slot/队列参数、CRC/timestamp、IRQ 能力和实际协商链路均未由本决策假定。

## 后果

正面：可直接以真实完成长度和自定义 header 管理 JPEG；避免把压缩码流伪装成 RGB24；协议与错误统计可快速同 FPGA 一起迭代；不依赖尚未验证的 V4L2 可变 bytesused 实现。

代价：用户态需要负责动态发现已绑定的 C2H 节点、缓冲区生命周期、帧校验、超时/重同步、JPEG 解码和性能统计；第一版的轮询可能带来 CPU 开销，须后续测量而非预设。

## 接受条件与后续

接受本决策前，双方须冻结 v0.1 帧头、slot/索引与 BAR ABI，并在板上完成：枚举身份及实际 BAR/节点记录、固定数据 C2H、单 JPEG 解码、多 slot 连续/丢帧恢复，以及轮询基线测量。若 JPEG 被证实为标准兼容码流，且可正确提供 compressed capture 的 `bytesused`、帧边界和错误语义，可另行提出 V4L2 MJPEG 适配决策；它不替代底层协议验证。
