# 随附 bit 与实际服务器结果

查询固定结果提交 `425edaaaf327235a64349c7149b568bb3de651f4`，快照为北京时间
2026-11-11 12:32:24。当前源码 `43dbc3f1` 的共享综合和 80 个物理种子均 DONE，
80 个种子均完成 bitgen；摘要均有负 setup。下载通过共享 `server/td/simple/client.py`
的原有分块及整文件 SHA256 校验，按固定结果提交取回必要文件，没有派发新任务。

选取 seed54，是因为它在上述 80 个同源摘要中 SWNS 最高，同时 HTNS=0；
没有将 bitgen 成功解释为时序或板级通过。本目录只保存这一版 bit。

| 项目 | 结果 |
| --- | --- |
| 源码 | `43dbc3f1d03668898b01c29c4b89a89930b66b9d` |
| 工程/器件 | camera_fusion_r1 / PH1A90SEG324-2 |
| 共享综合 / 物理 | SYN4 / PHY4，seed54 |
| bitgen | DONE，4,850,315 字节 |
| SHA256 | `9dbee9e9aab5b9fc8052639e46745fa59568a0e8d0d2ca5177b8e17ebb897508` |
| 报告阶段 | Routed，Slow/Fast 两角，STA coverage 99.85% |
| setup / STNS | −0.214 ns / −25.675 ns |
| hold / HTNS | +0.006 ns / 0.000 ns |
| 报告中 recovery / removal 最低裕量 | +3.582 ns / +0.014 ns |
| 时序资格 | **FAIL**，setup 尚未收敛 |
| 板级 | NOT_RUN |

| Routed 资源 | 使用量 | 器件容量 | 占用 |
| --- | ---: | ---: | ---: |
| Slice | 61925 | 64320 | 96.28% |
| Slice register | 71931 | 128640 | 55.92% |
| LUT6（该报告口径） | 57610 | 64320 | 89.57% |
| ERAM | 265 | 272 | 97.43% |
| DSP | 149 | 240 | 62.08% |

以上取自该种子的 `phy_1` 原件，未从局部综合节省量推算。STA 报告每组最多 10 个 endpoint、
每 endpoint 1 条 path，本次整理未作全部时钟例外、ignored path 或复制体覆盖审计。
资源余量较紧，后续优化是独立开发工作，本次仅整理归档。

- [bit 文件](../fpga_prj/bit/camera_fusion_r1_43dbc3f1_seed54.bit)、[机器可读身份](../fpga_prj/bit/BITSTREAM.json)
- [80 种子摘要](server_seed54_20261111/SEED_SUMMARY.json)
- [下载与文件哈希索引](server_seed54_20261111/FILE_INDEX.json)
- [服务器结果](server_seed54_20261111/artifacts/result.json)、[报告完整性清单](server_seed54_20261111/artifacts/reports.json)
- [Routed 时序原件](server_seed54_20261111/artifacts/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/simple.timing)
- [Routed 面积原件](server_seed54_20261111/artifacts/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/rfcamera_fusion_r1_phy.area)

初次集成和昨夜优化记录中的排队/NOT_RUN 是当时状态，本页补充当前选定 bit 的实际结果。
原回退源 `eade457d`、旧种子产物和原工程均未改动。

文件索引分别记录下载原始 SHA 与当前副本 SHA；报告数值和阶段信息保留，bit 保持原字节。
