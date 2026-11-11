# 原生 BAR 请求与响应

`camera_pcie_bar_rx` 接收 PH1A TRGT1 的请求头、有效载荷和 EOT。完整合法的单 DWORD 写可进入项目寄存器或外部 AXI-Lite 页。写事务到 EOT 后才允许产生副作用。无支持的非发布读向既有寄存器桥产生 UR，错误的写包整包丢弃。外部 AXI-Lite 写保留原字节选通和独立 AW/W/B 握手。

RX 同时只交付一个需响应的 BAR 请求，保存完整十位 tag、硬核给出的十位 lookup ID 和请求身份，直到 client1 真正接受原生 EOT。新请求在 TRGT1 反压期间由硬核保持。物理核心单独复位时，旧 AXI 读响应仍能排空，TX 仅对已经交付且未随复位失效的原生读产生完成包。C2H 图像写使用独立 client0，读 fence 使用 BYPASS。

物理握手与 lookup 定义依据安路《SALPHOENIX 1A 系列 FPGA PCI Express 用户手册》UG913 1.4，物理页 44、52–53、61–63、67–68，文件 SHA256 为 `9bb8638e4b9d6ee8e6576716d9b3698351e025d236010177027ff7757338dc56`。本工程使用 128 位 EP 模式。[原生端口手册](../../../../../references/vendor/安路科技_PH1A_技术文档/使用指南/UG913_安路科技PH1A系列FPGA%20PCIE用户手册.pdf)

[run.py](run.py) 使用 45 秒单步骤上限，编译自有 RX、实际寄存器译码与 TX。最终 `native_lookup_final` 有 164 项检查、7 次有效原生完成、零仿真告警。覆盖同拍和分拍写、反压、同低八位不同十位 tag、UR/CA、ECRC/abort、写选通，以及硬核复位后迟到的 AXI 读。更外层的 MSI、DMA fence、实际生成 IP 模型展开见[端点测试](../camera_pcie_native/README.md)。
