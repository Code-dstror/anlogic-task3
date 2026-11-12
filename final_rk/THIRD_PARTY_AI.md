# 单目 AI 第三方来源

| 内容 | 来源与许可记录 |
|---|---|
| Ultralytics 相关模型和代码 | V5 完整包保留 `control/ai_helper/candidate/LICENSE.ultralytics`，本次将同一份 AGPL-3.0 文本补入精简包。详见 [Ultralytics 开源指南](https://docs.ultralytics.com/help/contributing/#open-sourcing-your-yolo-project-under-agpl-30)。发布范围需结合具体模型、对应源码和已有授权核对。 |
| ByteTrack 的 CPU 适配 | 上游为 [FoundationVision/ByteTrack](https://github.com/FoundationVision/ByteTrack/tree/d1bf0191adff59bc8fcfeaa0b33d3d1642552a99)，许可证为 MIT。精简包的 `bytetrack_cpu/provenance.json` 记录上游提交、所改文件与哈希。原许可证已按该记录恢复。 |
| SciPy 和附带数学库 | V5 完整包保留 SciPy 1.10.1 ARM64 运行依赖，许可证随其 `.dist-info` 目录提供。 |
| Rockchip RKNN Runtime、MPP 和 RGA | 使用目标 BSP 的接口和运行库，具体文件身份见 V5 依赖清单。对已随包分发的厂商二进制，团队需核对其对应版本的分发条款。 |
| 语音 | 队员确认 V5 的 8 个 WAV 由 [RealDubbing](https://realdubbing.com/zh/) 免费生成。文件和哈希见模型清单。[服务条款](https://realdubbing.com/zh/terms-of-service)第 6 节将使用范围与套餐和第三方语音服务条款关联。随公开仓库或 Release 再分发原 WAV 的范围待确认。 |
| 训练数据及初始权重 | 具体来源和用法见 [模型说明](AI_MODELS.md#基础模型与训练数据)。原始数据和权重的分发范围按各自条款核对。 |

许可证副本见 [Ultralytics AGPL-3.0](licenses/Ultralytics-AGPL-3.0.txt) 和 [ByteTrack MIT](licenses/ByteTrack-MIT.txt)。项目顶层 `LICENSE` 及 FPGA、Linux 和 AI 的完整第三方清单由团队确认后加入。
