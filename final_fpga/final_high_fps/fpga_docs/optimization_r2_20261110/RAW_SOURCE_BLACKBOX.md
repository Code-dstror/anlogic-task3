# Private RAW→ISP→native RGB 独立黑盒短门

2026-11-10，`raw_source_r2_blackbox_20261110_r02`。基线和候选分别通过独立公开接口计分板，1,589 行逐拍控制、有效元组及复位边界轨迹字节相同。

## 输入和范围

使用 8 ns PIX、14 位 RAW、外置 ISP、`ORIGINAL_SYNC_CLEAR_ENABLE=1`。HD/UHD 两档以 16×4 和 32×8 小几何代表，每帧分别为 16 和 64 个 RAW4 组。DUT 包含实际 private RAW、清理和 native RGB 适配器。外置 ISP BFM 从每个被其接受的 RAW 组构造确定性 RGB，计分板用独立输入模式校验 RAW 四样本、RGB 四像素、KEEP、行尾、帧尾、索引和身份。10 位、内部 ISP 数值、相机入口、DDR 和满幅持续吞吐未覆盖。

无实现上下文的测试作者只使用[公开合同、端口声明和不透明源清单](../../fpga_prj/verification_archive/experiments/reset_data_qual_r2_20261110/PUBLIC_CONTRACT.md)编写新 [bench](../../fpga_prj/verification_archive/src_fpga/simulation/blackbox_raw_source_r2/tb_raw_source.sv) 和 [runner](../../fpga_prj/verification_archive/src_fpga/simulation/blackbox_raw_source_r2/run.py)。本门使用维护者确认的以下公开约束。

- `context_fire` 沿已发布匹配的 frame/job/pair/member。lease、native tag 和 writer tag 最迟在 owner valid 沿有效。本门在 valid 前使用不同的占位值，建立 valid 后逐沿核对合格 owner 的全部字段，直到最终 idle 才释放或替换借用数据。
- SOURCE 在最后一个 RAW 被接受后给出，reader quiet 先稳定一个采样沿。SOURCE 和 RGB 帧尾可以互换先后。STATUS 接受后可以通知 processed SOURCE，`i_pipeline_quiescent` 和 `i_post_pool_idle` 仍分别约束最终退休。
- 已有 ISP SOF 且取消是首错时，给一拍 cancel，期望 `E_CANCEL=3`。已呈现的 RAW/RGB 保持至握手，清理脉冲期间 ISP reset 低且已呈现的工作已经排空。

| 输入 | SHA-256 或固定源 |
| --- | --- |
| 基线提交 | `eade457d7477110605f90eb5abc08420d8936642` |
| 基线 private RAW | `782e4b6bd3f9845c61a1fe26308f763b50c68b6a461ff09401f5299c733fcf8b` |
| 候选 private RAW | `7a1ef673db77bc3f5b961f717e208c9180aa742d0a6dd51c851ab8cf875228ba` |
| 不透明清单 | `b865762d844172cf53612e1b1307a541462ba46e666d555e12ab02c1bb866e73` |
| 公共合同 | `6320b4509e8abc9ebfb9c172326d18540c170e09b0c7c389db3d0dac2bd722ce` |
| 端口声明 | `9d04eab1f4eb9f9bbc158f078fb18b8985c757413813de18fc032ccd974600d5` |
| Bench | `db5149c0149d24fa71af83efdd4b195b7b7b02efd066786fd16f9fcba62e6352` |
| Runner | `592240e561447a26f57e9b03355e2ac136b39c7950d7ba7297a4b53028729471` |
| 公开轨迹，两臂相同 | `2ee9b7327efe05931d10a9d3173c1873595219b6eaf5fe7e76acbc6c6e3867a8` |

## 可观察结果

| 场景 | 两臂各自通过的公开检查 |
| --- | --- |
| 冷启动首帧和 stale SOURCE | 16 组通过 RAW、ISP RAW、ISP RGB 和 adapter RGB。完整数据在 332 ns 结束。分别单独破坏 frame、lease、job、pair、tag 和 member，六个 SOURCE 都分类为 stale，计数各加一。412 ns 接受匹配 SOURCE 后才完成成功 STATUS。 |
| 大几何与 SOURCE 先到 | 64 组全路径对账。匹配 SOURCE 在 1340 ns 被接受，尾组 RGB 在 1388 ns 被接受。输出 context、STATUS、普通 RGB 和末组 RGB 经过有界反压，保持全元组直到握手。 |
| 处理后退休 | 两个正常帧分别独立拉低 `i_pipeline_quiescent` 和 `i_post_pool_idle`。原始 STATUS 完成和 processed SOURCE 通知都未提前归还 owner。对应 drain 恢复后达到 `o_pool_idle`。 |
| 取消与无复位恢复 | 同时保持一个 stalled ISP RAW 和一个 stalled RGB，再发一拍 cancel。reader 排空 16 组，ISP 兑现 2 个 RAW 和 2 个 RGB，adapter 输出端实际握手 1 组。1748 ns 接受匹配 SOURCE，1780 ns 采到唯一清理脉冲，1860 ns 接受失败 STATUS，`ok=0,error=3,groups=1`。完成 processed SOURCE 和退休后下一帧 16 组成功。 |
| 停钟重启 | 分别在 CLK 高相位和低相位停钟并异步复位，丢弃带 stalled offer 的帧。复位在停钟时断言，停钟期间释放输入 reset 不会提早释放 ISP。两个重启首帧分别以 16 和 64 组通过完整 SOURCE、STATUS、processed SOURCE 和 idle。 |

冷启动与两次重启的前三个上升沿都没有 context、payload、RAW READY 或 SOURCE READY 暴露。下表的 F3 和 R4 以边沿本身计时，边沿后 1 ns 另采样确认 ISP 释放与 context 可用性。

| 启动 | ISP 释放 F3 | context 在 R4 后可用 | 首次合法命令采样 | 首帧退休 |
| --- | ---: | ---: | ---: | ---: |
| 冷启动 | 48 ns | 52 ns | 60 ns | 537 ns |
| 停在高相位后重启 | 2484 ns | 2488 ns | 2496 ns | 2901 ns |
| 停在低相位后重启 | 3056 ns | 3060 ns | 3068 ns | 4001 ns |

每臂终态为 5 笔成功退休、1 笔取消退休、2 笔协调复位丢弃和 6 笔 stale SOURCE。成功帧合计 176 个 RAW4 与 176 个 RGB4 握手，另有取消帧独立对账。

## 复现与日志

在仓库根使用 `ENVIRONMENT.local.md` 的 Python 3.12 与 ModelSim 路径。本次工具为 ModelSim SE-64 2020.4 (2020.10)，两臂各有独立 `work` 库。逐进程墙钟限 55 秒，suite 限 158 秒，仿真限 20 μs，最终 suite 实耗约 6 秒。纯 Verilog DUT 源清单不需 TD 模型。复跑时换新目录名。

```powershell
& $fusionPython -B refactor/camera_fusion_r1/src_fpga/simulation/blackbox_raw_source_r2/run.py `
  --modelsim-bin $fusionModelSimBin --run-name raw_source_r2_blackbox_20261110_r02
```

[原始证据](../../tmp/raw_source_r2_blackbox_20261110_r02/evidence.json)记录每个命令、源文件哈希、参数、结果及耗时。[基线仿真](../../tmp/raw_source_r2_blackbox_20261110_r02/raw14_baseline/vsim.log) · [候选仿真](../../tmp/raw_source_r2_blackbox_20261110_r02/raw14_candidate/vsim.log) · [公开轨迹](../../tmp/raw_source_r2_blackbox_20261110_r02/raw14_candidate/public_trace.txt)。[首轮 r01](../../tmp/raw_source_r2_blackbox_20261110_r01/evidence.json)保留，r02 补强延迟 owner 窗口的 READY 门控、SOURCE 前一沿 reader quiet 以及清理脉冲时的承诺排空断言。

本门功能仿真 **PASS**。本门综合、P&R、物理时序、板级均为 **NOT_RUN**。
