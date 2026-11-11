# ARAW 封装与 RK 解包回归

在仓库根目录使用 `ENVIRONMENT.local.md` 中的 Python 和 ModelSim。每次运行使用新的名称。

```powershell
python refactor/camera_raw_r1/src_fpga/simulation/raw_video_record/run.py --modelsim-bin $env:MODELSIM_BIN --name raw_record_check
```

测试包括短记录的随机有限反压、末拍 stall、头部 abort、body abort、共同冷复位，以及 1080p 和传输长度上界的连续就绪用例。字节参考按 ARAW 字段表拼接期望头部并重构实际握手数据，核对 RK 零复制视图、Bayer 元数据、10-bit 样本和非法记录拒绝。合成长度 1、16、17 字节用于隔离封装边界，相应记录会被 RK 的 RAW10 几何校验拒绝。

源快照、SHA-256、命令、实际字节 trace 和结果写入 `refactor/camera_raw_r1/tmp/raw_video_record/<name>`。本回归的综合、布局布线、STA 和板级状态为 `NOT_RUN`。
