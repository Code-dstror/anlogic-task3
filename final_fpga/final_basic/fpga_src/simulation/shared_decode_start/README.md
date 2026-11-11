# 共享 RAW10 解码启动与排空短测

在仓库根目录使用 `ENVIRONMENT.local.md` 中的 Python 和 ModelSim。每次运行使用新的名称。

```powershell
python refactor/camera_raw_r1/src_fpga/simulation/shared_decode_start/run.py --modelsim-bin $env:MODELSIM_BIN --name shared_decode_check
```

仿真直接连接生产 `stereo_raw_reader`、`shared_raw10_decode_service` 和解码核心。测试端模拟 8×2 RAW10 的 20 字节 AXI 读响应和 DATA/FENCE 握手。覆盖正常首读、屏蔽核心 START、首个 AR 前丢失上下文、4 KiB 分段的两 burst 之间丢失上下文、末次 R 后仍有 RAW 组时丢失上下文，以及 STOP 后保持 AR/R/DATA 并排空。每个结果在真实 FENCE 消费后才发布，等待结果握手期间仍持有解码器。最后用同一复位 cohort 验证正常再读。

`stereo_active` 由已拥有的 Stereo 核心非空闲状态产生。外层授权先于核心启动，正常完成或中止另有独立脉冲。生产使用外部共享解码器，测试源清单也只展开此分支。

源快照、命令、日志和 `qualification.json` 保存到 `refactor/camera_raw_r1/tmp/shared_decode_start/<name>`。此短测的综合、布局布线、STA 和板级状态为 `NOT_RUN`。
