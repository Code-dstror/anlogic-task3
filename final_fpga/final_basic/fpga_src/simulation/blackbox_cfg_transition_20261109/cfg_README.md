# 配置切换独立黑盒短测

测试使用实际 `mono_config_service_v2`、PIX owner、两只受控 TD 40×512 FIFO 和 USER BAR。USER 与 PIX 时钟分别为 125 MHz 与 100 MHz，沿错相。外部捕获和 DFI 通过公开端口建模。模型在完整接收 1184 位配置元组后延迟回送整包 ACK，在允许新捕获后提供 CAM0 首帧接受事件。

从仓库根目录使用 PowerShell 7 调用。每次最多 55 秒墙钟，模拟上限 1.5 毫秒。每次调用建立独立结果目录，并记录模型路径、精确命令、输入 SHA256、工具版本及原始日志。

```powershell
$cfgRunner = 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_cfg_transition_20261109/cfg_run.ps1'
$cfgTools = @{ TdRoot = 'D:/App/TD_Release_2026.2.210.850'; ModelSimBin = 'D:/App/modelsim/win64' }
& $cfgRunner @cfgTools -Build baseline -Case liveness
& $cfgRunner @cfgTools -Build candidate -Case liveness
& $cfgRunner @cfgTools -Build candidate -Case profiles
& $cfgRunner @cfgTools -Build candidate -Case negative_ack
& $cfgRunner @cfgTools -Build candidate -Case fault_at_sof
& $cfgRunner @cfgTools -Build candidate -Case stopped_reset
```

`baseline` 从 R2 的 `tmp/fieldfix_20261109/baseline/` 取 engine 和 service。两份基线文件与 `d1a7f871d0b58d7294bfcdd5c396e3be87597799` 中对应 Git blob 完全一致。其余编译依赖与候选相同。基线预期为 `REPRODUCED_FAIL`，runner 返回 1。候选要求显式 `PASS` 标记且返回 0。

结果目录位于 R2 的 `tmp/blackbox_cfg_transition_20261109/`。以下运行使用 ModelSim SE-64 2020.4 和 TD 2026.2.210.850，单场总墙钟 5.45–6.45 秒，最长模拟 84.085 微秒。

| 运行目录 | 结果 | 观察 |
| --- | --- | --- |
| `20261109T105446396Z-baseline-liveness` | REPRODUCED_FAIL | HE 首事务发布 epoch 1。去雾收到完整 ACK 并接受四个 CAM0 事件，旧 BAR ACTIVE epoch 1 保持，`STATUS=0x11`。 |
| `20261109T105446465Z-candidate-liveness` | PASS | 同一用例在新处理仍忙时发布去雾 epoch 2，回报第一个 CAM0 序号 `0x480`。 |
| `20261109T105446329Z-candidate-profiles` | PASS | 两轮 HE→去雾→SDR 及 HDR→去雾，最终 epoch 8。逐次核对请求标量、全部 32 个扩展字、远端全量元组和 ACTIVE BAR 读回。 |
| `20261109T105447423Z-candidate-negative_ack` | PASS | 错 epoch 的 ACK 被计为 stale。全量匹配的负 ACK 终止并报 `ERROR_RESET=6`，保留旧 ACTIVE。冷启动后新的去雾事务成功。 |
| `20261109T105449018Z-candidate-fault_at_sof` | PASS | 错 epoch ACK 后，匹配 ACK 恢复放行。首帧同拍的 source fault 优先，报 `ERROR_RESET=6` 并保留旧 ACTIVE。冷启动后新的去雾事务成功。 |
| `20261109T105449685Z-candidate-stopped_reset` | PASS | USER 停钟时 PIX 收到首帧，异步双复位撤销待发布事务。恢复后重新完成 BOOT 和单目去雾，ACTIVE epoch 1。 |

每轮 PREPARE 都在模型保持 `pipeline_idle=0` 时检查 pause。模型标记旧工作完成后才允许 READY。远端请求施加有限背压，ACK 前及 ACK 后未提供首帧的窗口都读取 BAR 检查旧 ACTIVE。HDR 参数的位段采用 R2 公开协议 JSON，`HDR_MOTION_BASE` 从位 87 开始、宽 14 位，`HDR_MOTION_SHIFT` 从位 101 开始、宽 4 位。

早期结果也保存在原目录。`20261109T105142063Z-baseline-liveness` 是前置条件遗漏，维护者补充 `CFG_HOST_CAPABILITIES[0]=1` 后完成合法首事务。`20261109T105352290Z-candidate-liveness` 已达到功能终态，但 runner 把 ModelSim `$finish` 当作错误退出。正式对照使用同一测试台及修正后的 runner。

此证据范围是短时功能仿真。真实图像、传感器、物理 DDR、PCIe 传输、综合、P&R、STA 和板级验证均为 NOT_RUN。
