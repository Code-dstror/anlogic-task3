# camera_fusion_r1 工作范围

本目录是独立融合候选。以 `camera_rate_r3` 封印 `5914a5b2` 为生产骨架，
合入 `camera_hdr_quality_r1@7dde99e7`，通过 `camera_raw_r2@1a5603c1` 核对共同来源。
三个输入工程、已发布包和历史证据保持只读。遵守仓库根、`src_fpga/AGENTS.md`
及 `fpga_prj/AGENTS.md`。原生工程和运行目录分别为 `fpga_prj/rfcamera_fusion_r1.al`
和 `fpga_prj/rfcamera_fusion_r1_Runs/`。

厂商 IP 保留原字节。Tone 数据只采用画质候选的两份已固定系数表。
保留 UHD/HD 速率、RAW/JPEG、槽身份和退休合同。新增或修改 RTL 由无实现上下文的作者
使用公开接口做独立短测。本机只做短仿真、read_design 和有界的小模块综合。
初次融合阶段只做本机验证。2026-11-10用户随后授权推送本候选到BUILD_SERVER，
一次4线程共享综合、20个各4线程物理种子执行full；固定源与回执见docs/SERVER_BUILD_20261110.md。
烧录和板级操作仍不在本轮范围。

2026-11-10后续优化：已先确认eade457d提交并在云端，保留该回退和原20种子批次。
用户随后明确要求北京时间22:40后收尾，最终优化源一次SYN4＋80个PHY4 full；
唯一新请求及接收回执见docs/SERVER_OPT_BUILD_20261110.md。不取消或覆盖旧批次。
