# RK 参数事务独立黑盒短测

按 [公开接口合同](../../../docs/parameter_timing_20261110/CFG_PARAMETERS_PUBLIC.md) 驱动生产 `mono_config_service_v2`，通过异步 USER/PIX 时钟、公开 BAR 读写、真实 CDC 和 TD 2026.2 RAM/FIFO 模型验证配置事务。配置请求和 ACK 的端点模型只用公开端口，合格首帧由 `frame_accept` 表示，HDR 场景将它作为所需相机组的合格 LONG 边界。寄存器、命令、状态位、错误码和 schema2 字段位置由 [PCIe 协议 JSON](../../../../../docs/pcie_protocol_v1.json) 生成。

| 场景 | 公开观察点 |
| --- | --- |
| `mono` | HE → 去雾 generation 0 → HDR → 去雾 generation 1。覆盖 JPEG Q/minQ、adaptive、预算与 restart 边界，HDR motion/timer 公开示例，核对每次完整请求、像素域 ACTIVE 和 BAR APPLIED 的 epoch/首帧序号。 |
| `dual` | 协调复位后发现双相机能力，首个 SDR 事务与连续两个 HDR 事务到 APPLIED。覆盖 motion base/shift、delta、wait、age 的合法最小值和最大值。 |
| `reject_basic` | 缺少 FRAME_APPLIED 协商、Q 越界、minQ 为零或超过 Q、未知 flags、adaptive 零预算、预算或 restart 越界。每项新协调 BOOT，检查 INVALID、旧 ACTIVE 不变及无下游配置请求。 |
| `reject_hdr` | delta 高字、零 wait/age、修改固定黑电平 50/50、ratio 4、qualification 15、扩展保留位和双目 F22/lane 请求。 |
| `fault_recovery` | 匹配完整 ACK 后，源终止故障与首帧边沿同时输入，验证 ERROR/RESET 及旧 ACTIVE 保留。协调重启后首个合法事务到 APPLIED。 |

单目首个 HE、单目 HDR 与双目首个 SDR 事务包含旧工作延迟排空、远端请求反压、迟到 ACK、旧 epoch ACK 以及 ACK 前错误帧脉冲。匹配 ACK 后保持 `pipeline_idle=0`，先检查 ACTIVE/epoch 未发布，再在 `source_ready` 上送入合格首帧。通过条件同时包含实际 BAR APPLIED 及读回一致的完整参数。

## 运行

从仓库根目录用本机原生 PowerShell 运行。ModelSim 与 TD 根路径显式传入。

```powershell
& 'python' `
  'refactor/camera_raw_r2/src_fpga/simulation/blackbox_parameters_20261110/run_cfg_parameters.py' `
  --modelsim-bin 'D:/App/modelsim/win64' --td-root 'D:/App/TD_Release_2026.2.210.850'
```

可重复传 `--case` 选择场景。每次创建 `refactor/camera_raw_r2/tmp/parameters_20261110/rtl_bb/<run-id>/` 下的新库及原始日志，可用 `--run-id` 指定未用过的标签。每场景仿真上限 1 ms，每次完整运行墙钟上限 60 s。运行清单包含命令、工具版本、输入 SHA256、退出码、场景终态及公开断言。

## 实测结果

`cfg_003_negotiated` 的 5 个场景均 PASS。8 个合法事务在 BAR 发布 APPLIED，17 个 PREPARE 被拒绝，1 次源故障进入 RESET 并随后通过协调复位恢复。三次旧 epoch ACK 及提前帧均保持 ACTIVE，随后用匹配 ACK 和合法帧在 `pipeline_idle=0` 时完成 APPLIED。最长场景为 59.037 µs，完整运行墙钟为 14.73 s。每项终点和证据路径见 [VALIDATION.json](VALIDATION.json)。

三项编译均为 0 错误、0 告警。每个场景展开时有 2 条冻结 `ram40_sdp_fixed` ECC 注入端口宽度告警 `vopt-2241`，以及 8 条 TD 2026.2 `ph1_logic_eram.v` 的 INIT_FILE 范围告警 `vopt-2697`。原始日志保留全部告警。

保留首轮 `cfg_001_first_compile` 的 ModelSim 配置文件路径调用错误。第二轮 `cfg_002_local_ini` 缺少公开合同中的 `CFG_HOST_CAPABILITIES.FRAME_APPLIED` 协商前置，因此其失败和负例结果均保留为合同交付／测试台证据。补齐协商后在新库验证；缺协商本身也作为独立 INVALID 反例通过。

本验证的硬件覆盖边界止于公开配置服务与其配置、ACK、合格帧接口。图像算法、物理相机、整帧性能、DDR、综合、布线时序和板级结果各自独立。
