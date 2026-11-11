# 验证与优化源码档案

这里保存 camera_fusion_r1 已纳入版本控制的仿真源码、独立公开合同、优化试验和原辅助工具。
这些文件不注册到生产 `.al`；未采用的 A/B 候选独立保存。

- `src_fpga/simulation/`：本工程各独立黑盒测试、oracle 和测试专用载体。
- `verification_reference/`：公开合同、原输入清单、fixture 生成器及来源封印。
- `experiments/`：面积/时序对照载体、候选源和脚本，包括未采用方案。
- `tools/`：原始辅助脚本；新目录可直接使用的协议生成器/UART/检查工具在上一层 `tools/`。

这些脚本原本以 `refactor/camera_fusion_r1` 或仓库根为上下文，部分需要固定的 peer SDK、
共享 JPEG oracle、原版本 Git 对象和外部 ModelSim/TD。复现需配置本机路径；归档未重跑仿真。
复现请按 [构建与检查说明](../../fpga_docs/BUILD_AND_VERIFY.md) 回到原仓库布局使用对应固定源，
原路径与新位置的关系见 [RELOCATION.json](../../fpga_docs/provenance/RELOCATION.json)。
