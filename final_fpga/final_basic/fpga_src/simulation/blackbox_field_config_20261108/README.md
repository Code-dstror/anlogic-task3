# CFG 与 CAM1 独立黑盒短测

测试台只使用公开 BAR、流握手、时钟和引脚。CFG 运行真实 `mono_config_service_v2`（含 BAR 和跨域传输），外部模型按握手原样返回完整数字 ACK，并给出合法首帧脉冲。CAM1 运行真实 `sdr_camera_raw_frontend`，在 SDA 开漏引脚上回应 I²C，用数字 PHY 边界控制 WORD 时钟，在公开 PIX 端口送入合格或拒绝的 HDR pair 事件。作者只依据公开合同，不读取生产 RTL、旧测试、厂商模型或内部状态。

| 场景 | 当前结果 | 关键证据 |
| --- | --- | --- |
| `cfg-positive` | PASS | BOOT 后实际 SDR 去雾 APPLIED：request `0x51`、epoch 1、首帧 `0xfa10007b`。HDR 持有 drain、数字 ACK 和首帧边界；即便提前脉冲也不推进。合法首帧序号 0 后才 APPLIED，request `0x52`、epoch 2。逐字核对扩展 ACTIVE。 |
| `cfg-fault` | PASS | HDR 数字 ACK 后无帧，保持源 fault 使 BAR 终止为 ERROR/RESET(6)，清 BUSY/READY/APPLIED，response 匹配 `0x52`，全量 ACTIVE 与 epoch 1 保持。fresh reset/BOOT 后再次 SDR APPLIED。 |
| `cfg-same-edge` | PASS | 同一 PIX 沿同时给出源 fault 与首帧；负回执优先，保留旧 ACTIVE/epoch，禁止继续准入或自动重试。fresh reset/BOOT 后再次 SDR APPLIED。 |
| `cam-training` | PASS | SDR→HDR→SDR→HDR 实际 XCLR 与 I²C 分别为 203/139/203/139 笔；尾两笔为 `3000=00`、等待、`3002=00`。HDR 首个 pair 前停 WORD，PHY 掉线并报告 receive fault；恢复不重配。7 好、1 坏、7 好仍不稳定，第 8 个连续好 pair 才稳定；第二 HDR cohort 重新计数。稳定后 WORD loss 为保持的终止故障。 |
| `cam-nack` | PASS | 第 3 笔 HDR 写的末字节真实 NACK；2 笔成功后停止并保持 error，未自动重试。fresh reset 后实际 SDR、HDR 配置与 HDR 配对资格均完成。 |
| `cam-lock` | PASS | HDR 配置成功、pair 热身期间撤销配置时钟锁定；error 保持、done/stable 清除，恢复锁定不自动重试。 |

相同 oracle 下，seed92 的 CFG 在同一截止点仍为 `status=0x11`（BUSY 和 SESSION_READY）、`error=0`、`response=0x52`；seed92 的 CAM1 将首个合格 pair 前的停钟误判为终止故障。两个反例均保留原始 FAIL。CFG 对照仅替换冻结 engine/service 并省略旧接口没有的 fault 参数与端口；CAM1 对照在 include 搜索首位放冻结 capture 头，复用当前公开 wrapper 和其余相同模型。冻结源由维护者从 `81404aec1727e16f3df7424a74c5f960ad3d6683` 提供；这是组件对照。

公开 BAR oracle 来自仓库 `docs/pcie_protocol_v1.json` 和 `docs/s01_config_transaction.md`；引脚与编译合同见本目录 `IO_CONTRACT.md`（原维护者交接路径 `tmp/fieldfix_20261108/config_contract.md`）。开始时保留了三次合同澄清的原 FAIL：

- `config_blackbox_initial`：实例 `PROFILE=1` 是单目基准；启用 stereo capable 且 runtime 为双目时，公开 BAR profile ID 是 `DUAL1920=2`。
- `config_blackbox_profile2`：参数 `V2_SUPPORTED_ENABLES=0x3f` 为编译超集；双目只公开灰度、去雾、高斯、HE，即 `0x0f`。
- `config_blackbox_public`：PREPARE 期间 `source_ready` 可保持已初始化资格，`pause_new_jobs=1` 禁止新 job。COMMIT 数字 ACK 之前 source eligibility 为低且 pause 为高；ACK 后合法首帧要求 `source_ready && !pause_new_jobs && pipeline_idle`。

本次日志位于仓库 `tmp/fieldfix_20261108/`，各例均有独立 `manifest.json`（精确 argv、stage、完整输入 SHA256 和终态）及工具原日志：

| 运行目录 | variant 与场景 |
| --- | --- |
| `config_blackbox_admission` | current：三个 CFG PASS |
| `cam_blackbox_initial` | current：三个 CAM1 PASS |
| `config_blackbox_seed92` | seed92：`cfg-fault` FAIL |
| `cam_blackbox_seed92` | seed92：`cam-training` FAIL |

ModelSim SE-64 2020.4，TD 模型根 `D:/App/TD_Release_2026.2.210.850`。每例新建 work/ph1 库，整例默认墙钟上限 55 s，CFG 仿真 watchdog 500 µs，CAM1 70 ms；实际 3.7–7.2 s/例。收尾仅将 runner 的 seed92 取源改为固定 Git 字节重建，避免 tmp 成为唯一依赖；下表 runner SHA 是实际执行历史，不冒充修改后的哈希。重跑使用新的输出目录：

```powershell
$python = 'python'
$runner = 'refactor/camera_raw_r1/src_fpga/simulation/blackbox_field_config_20261108/run.py'
$td = 'D:/App/TD_Release_2026.2.210.850'
$msim = 'D:/App/modelsim/win64'
& $python $runner --td-root $td --modelsim-bin $msim --run-root tmp/fieldfix_20261108/cfg_cam_current_repro --case cfg-positive --case cfg-fault --case cfg-same-edge --case cam-training --case cam-nack --case cam-lock
& $python $runner --td-root $td --modelsim-bin $msim --run-root tmp/fieldfix_20261108/cfg_cam_seed92_repro --variant seed92 --case cfg-fault --case cam-training
```

seed92 的预期结果是失败退出，重跑仍保留 FAIL。当前 bench/runner SHA256：

| 文件 | SHA256 |
| --- | --- |
| `tb_cfg_field.sv` | `dee21962de6f5f6fa9a0364d7c31b9803c7607af84f682fc3d05ec8a018758d1` |
| `tb_cam_field.sv` | `2d1d3481789d08a44bb7136fbe2c5bcd94df7c4e7105da01b1c645fd28cd447b` |
| `run.py` | `6dc1e4a498d76a91d7bb51c5c3f39310ecbb8aaf80200f4b72d41fe926df7d32` |

未注入实际 CSI 包、主动 parser 身份失效或 pair CDC 溢出，未运行满幅数据、真实 TOP 双眼首帧到主机、模拟 PHY 训练、综合、P&R、STA 或板级。本测试证明公开刺激下的控制行为，不判断 seed92 实板故障的唯一触发原因。
