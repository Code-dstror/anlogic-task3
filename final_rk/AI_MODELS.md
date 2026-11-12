# V5 单目 AI 模型说明

适用组合为 `final_basic / seed25` 与 `final_rk V5`。两个部署权重随 `final-basic-seed25-repro.tar.gz` 提供。解包前先用 `sha256sum -c SHA256SUMS` 核对同目录的两个归档。

| 用途 | 模型 | 输入 | SHA256 |
|---|---|---|---|
| 检测 | YOLO26n 23 类 | RGB 640×640 等比例缩放，补边值 114 | `2135d0a442227e906c328338546938ddbcacef836728a3c721c09b7cca2b7eee` |
| 深度 | NR03 guarded epoch15 | RGB 640×640 整图拉伸 | `fd539fd0d89697ee6bcfb98c77f8be2776b87edfc7899d31045a5ec7f5b1aa75` |

两个文件在归档内都叫 `model.rknn`。它们各自的完整相对路径、字节数、23 类顺序和四类映射见 [ai-models.json](ai-models.json)。四类标签按源码配置读取，分别为 `pedestrian`（5）、`vehicle`（8）、`two_wheeler`（2）、`obstacle`（8）。

运行配置与资源哈希取自完整包的 `control/ai_provenance/dependencies.json`。清单中的 `required_for_live` 区分实时所需文件和历史回放引用。完整包可依照主 README 的单目模式进入 YOLO 叠加，显示检测框、类别和估计距离。距离为模型估计，实时叠加允许异步滞后。报警、实际 CAM0 内参和尺寸估算的集成状态按 V5 原交付记录。

历史 21.0457 FPS 来自固定视频回放到内存叠框的另一次测量。V5 实时性能应记录同轮相机输入、AI 推理、HDMI 输出、时长和版本。重新导出或复训所需的检查点、转换工程及训练输入待确认分发范围后另行提供。

## 基础模型与训练数据

- **检测模型。** 以 [Ultralytics 官方 YOLO26n 预训练权重](https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo26n.pt) 为起点，用 Ultralytics 8.4.183 在 [nuImages](https://www.nuscenes.org/nuimages) 前视相机子集上微调为 23 类。训练 13,187 张，验证 3,249 张。训练产物 `train_end_best.pt` 经部署 ONNX 转为本包的 RKNN，导出及转换链路的 SHA256 见模型清单。
- **深度模型。** [Ultralytics YOLO26n Depth](https://docs.ultralytics.com/tasks/depth) 的 `yolo26n-depth.pt` 用于初始化 LC64 的骨干与特征融合部分，并作为 LC64 训练的教师模型。LC64 权重续训得到 NR03，本包采用第 15 轮的 `train_end_best_guarded.pt` 转换产物。NR03 的数据清单按以下方式划分：

| 数据来源 | 训练帧 | 验证帧 | 测试帧 |
|---|---:|---:|---:|
| [PandaSet](https://scale.com/open-datasets/pandaset) | 1,440 | 176 | 32 |
| [Argoverse 2](https://www.argoverse.org/av2.html) | 2,532 | 755 | 558 |
| [nuScenes](https://www.nuscenes.org/) | 0 | 0 | 404 |

以上数量来自训练数据审查及实际配套清单。原始数据通过各发布方获取，按对应条款使用。权重的上游、训练与导出身份集中记录于 [ai-models.json](ai-models.json)。
