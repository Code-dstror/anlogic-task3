# 技术文档入口

当前交付的身份和状态以 [总说明](../README.md)、[比特流状态](BITSTREAM_STATUS.md) 为准。
其余原有报告带有各自的阶段和源码范围；其中“NOT_RUN”“排队”“本轮”等描述是当时的记录。
历史哈希标识报告的原始输入；当前文件哈希见 `DELIVERY_FILES.json`，源码映射见 `provenance/RELOCATION.json`。

| 内容 | 文档 |
| --- | --- |
| 功能、分辨率、帧率及限制 | [MODE_MATRIX.md](MODE_MATRIX.md) |
| HDR/ISP/JPEG 参数与回读 | [RK_QUALITY_CONTROLS.md](RK_QUALITY_CONTROLS.md)、[RK_PARAMETER_DISCOVERY.md](RK_PARAMETER_DISCOVERY.md) |
| 4K、RAW、几何冷选 | [UHD_RK_CONTROL.md](UHD_RK_CONTROL.md)、[GEOMETRY_CONTROL_PUBLIC.md](GEOMETRY_CONTROL_PUBLIC.md)、[UHD_CFG_PUBLIC.md](UHD_CFG_PUBLIC.md) |
| 通信协议机器定义 | [PCIe](pcie_protocol_v1.json)、[质量](quality_control_v1.json)、[速率](rate_control_v1.json)、[几何](geometry_control_v1.json)、[RAW](raw_video_v1.json) |
| UART 调试 | [UART_FIELD_V4.md](UART_FIELD_V4.md) |
| 集成来源与取舍 | [INTEGRATION.md](INTEGRATION.md)、[IP 来源清单](LOCAL_CATALOG_IP.json) |
| 历史修复保留 | [FIX_RETENTION.md](optimization_r2_20261110/FIX_RETENTION.md) |
| 优化方案与实测 | [PROGRESS.md](optimization_r2_20261110/PROGRESS.md)、[AREA_RESULTS.md](optimization_r2_20261110/AREA_RESULTS.md) |
| 初次集成验证 | [QUALIFICATION.md](QUALIFICATION.md)、[原始索引](validation_20261110/INDEX.json) |
| 优化后黑盒 | [熵核](optimization_r2_20261110/BLACKBOX.md)、[RAW 数据资格](optimization_r2_20261110/RAW_SOURCE_BLACKBOX.md)、[ring 复位](optimization_r2_20261110/RING_RESET_BLACKBOX.md) |
| 本次整理检查 | [BUILD_AND_VERIFY.md](BUILD_AND_VERIFY.md)、[DELIVERY_CHECK.json](DELIVERY_CHECK.json) |
| 原始来源与路径映射 | [原源清单](provenance/SOURCE_MANIFEST.json)、[原封印](SOURCE_SEAL.json)、[归档映射与哈希](provenance/RELOCATION.json) |
| 新目录的活动源清单 | [fpga_prj/SOURCE_MANIFEST.json](../fpga_prj/SOURCE_MANIFEST.json) |

历史报告及 JSON 内的 `refactor/camera_fusion_r1`、`src_fpga`、`tmp`、服务器绝对路径和父工程路径
用于原始证据追溯，不是新目录的活动构建依赖。原有 Markdown 中能确定目标的本工程链接已调整。
大体积仿真库、编译 DB、缓存、厂商安装软件以及其他工程的 bit 不属于本目录源码归档。
