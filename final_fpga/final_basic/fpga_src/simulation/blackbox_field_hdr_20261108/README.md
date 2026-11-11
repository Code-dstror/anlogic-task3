# HDR 现场异常黑盒短测

`tb_field_hdr.sv` 使用 [存储配对公开合同](OWNER_IO_CONTRACT.md)，在 16×4 配置下检查 BEGIN、FINISH、目录逐字读取、TAKE 和实际 RELEASE。写端及共享消费者使用 BFM。`tb_field_hdr_gate.sv` 使用 [物理曝光门公开合同](../blackbox_timing_20261107/HDR_IO_CONTRACT.md)，检查 RAW10 payload 和边界、逐 VC SOURCE 身份及物理配对终态。

## 运行

在仓库根目录执行。每次指定新的 `--run-dir`。`--profile baseline` 从固定提交 `81404aec1727e16f3df7424a74c5f960ad3d6683` 导出输入。`--profile candidate` 快照当前工作树的输入。owner 使用指定 TD 的仿真模型，cycle_gate 无 TD 模型依赖。日志目录包含实际 argv、源与模型 SHA256、测试参数及逐例结果。

```powershell
$python = 'python'
$runner = 'refactor/camera_raw_r1/src_fpga/simulation/blackbox_field_hdr_20261108/run.py'
$toolArgs = @('--modelsim-bin', 'D:/App/modelsim/win64', '--td-root', 'D:/App/TD_Release_2026.2.210.850')

& $python -I -B $runner @toolArgs --profile candidate --target owner `
    --run-dir tmp/fieldfix_20261108/hdr_owner_new `
    first_left first_right capacity_left capacity_right older_left older_right `
    phase_aligned_left phase_aligned_right phase_early phase_late stop_drain `
    failed_source_left failed_source_right wrap

& $python -I -B $runner @toolArgs --profile candidate --target cycle_gate `
    --run-dir tmp/fieldfix_20261108/hdr_gate_new `
    interleaved fe_peer_bad fault_wrap timeout_reset timeout_peer_bad
```

## 2026-11-08 原始结果

| 用例 | 冻结基线 | 候选 | `tmp/fieldfix_20261108` 下的证据目录 |
| --- | --- | --- | --- |
| 双眼合法首对、反压、连续退休 | 2 PASS | 2 PASS | `hdr_bb_baseline_a`、`hdr_bb_candidate_a` |
| 两次容量拒收、保留较老已准入组、释放后拒同组迟到对端 | 4 FAIL | 4 PASS | `hdr_bb_baseline_a`、`hdr_bb_candidate_a` |
| 释放相位扫、STOP 排空、负 FINISH 恢复、回卷 | 8 PASS | 8 PASS | `hdr_bb_baseline_b`、`hdr_bb_candidate_b` |
| 回卷后先确认空 bank，再提交迟到对端 | NOT_RUN | PASS | `hdr_bb_candidate_wrap` |
| 曝光交错、同拍 FE/BAD、双上下文故障与回卷、超时恢复和冷复位 | NOT_RUN | 历史与当前各 4 PASS | `gate_bb_candidate_b`、`gate_bb_candidate_c` |
| 旧组超时与新组 BAD 同拍、拒收两组迟到曝光及回卷恢复 | NOT_RUN | PASS | `gate_bb_timeout_overlap` |

四个基线功能失败均发生在真实退休后。候选禁止同组迟到对端另占 bank，后续完整组在 100 ms 配对等待窗口内完成目录读取和退休。首次曝光门编译缺少公开的头文件依赖，原工具失败保留在 `gate_bb_candidate_a`。

最终 runner SHA256 为 `58a6a4c5675f8705903d3d29833fd5cb11882918a0fccc658e00ae5f12477a4c`。早期 owner A/B 日志使用 runner `7e1e2751e040b116956dbd4f20bc5b31b69696a1a02f73c3331c43573a4bf24a`。强化回卷与曝光门通过日志使用最终 runner。

`gate_bb_candidate_b` 的历史源码 SHA256 为 `deb83f662120f2f9abad4aabd1f4e8fc06e6e76d527125afbda8cb39098c711e`。`gate_bb_candidate_c` 和 `gate_bb_timeout_overlap` 的源码 SHA256 为 `423ebc23a8e84e31cfd7c1efef37fc4f443b4473acacab104045db5a10dfd3d4`。混合负事件用例中，旧组在 612 ns 到期且新组 BAD 同拍握手，620 ns 收到各自的负 SOURCE。两个旧组的重放均无 RAW 或 SOURCE，回卷后的组 1 在 924 ns 完成双正 SOURCE 及正配对事件。

覆盖边界为公开端口的短控制序列和小数据 BFM。满幅帧率、真实 DDR 流量和跨时钟域集成均为 NOT_RUN。本短测也未执行综合、P&R、STA、bitgen 或板级验证。
