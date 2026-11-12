# RK3576 最终软件交付

对应 FPGA `final_basic / CAMERA_RAW_R2 · 1a5603c1 · seed25`，整理日期：2026-11-12。

| 文件 | 用途 |
|---|---|
| [final-basic-seed25-repro.tar.gz](final-basic-seed25-repro.tar.gz) | V5 完整软件复现包，与当前 RK 板端包一致；包含程序、bit、已验驱动、模型、私有依赖和详细说明 |
| [final-basic-seed25-source-minimal_20261112.zip](final-basic-seed25-source-minimal_20261112.zip) | 精简软件源码及必要说明，约1MB；供阅读和维护，不作为独立安装包运行 |
| [SHA256SUMS](SHA256SUMS) | 上述两个压缩包的 SHA-256 校验值 |

完整包面向原 RK3576 Debian12 / ARM64 / Linux6.1.99 BSP。每轮共同冷启动、SRAM 下载同一 seed25 后，通过 `reproduce.sh` 选择单目或双目、是否开启4G/Tailscale网页控制。保留终端控制、适用算法与参数面板、HDMI FPS、单目YOLO及SD循环录像。V5包含“先建立4G数据连接、校时，再严格验证HTTPS”的启动修复。

单目离线与双目4G入口已有板测反馈；三种双目布局、六种双目算法及录像样本正常。真实单目↔双目在线重建仍停用，长期录像回收/回放、AI精度及报警等边界详见包内文档。完整软件源码修复提交为 `670232df23f1fd89f3f19dc3b25b2569a0695f13`，依赖模块及原生构建源按各自冻结版本保留。

本目录只存放 RK 软件交付，仓库原有 FPGA 最终文件保持原位。
