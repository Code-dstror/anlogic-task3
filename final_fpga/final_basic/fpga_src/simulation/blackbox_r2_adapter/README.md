# r2 独立黑盒短测：RGB 适配器与 RAW SOURCE owner

独立测试作者只接收 [适配器合同](../../../verification_reference/adapter_public.md)、
[适配器端口](../../../verification_reference/adapter_ports.txt)、
[SOURCE 合同](../../../verification_reference/source_borrow_public.md) 和
[SOURCE 端口](../../../verification_reference/source_borrow_ports.txt)。生产 RTL 及依赖不透明编译，
不使用历史测试、内部层次信号或 `force`。两套测试分别给一条合法固定 1080p raster；
其余用例只送少量前缀。终态、像素组、上下文与所有权按实际 VALID/READY 对账。

在 `refactor/camera_raw_r2` 内运行：

```powershell
$r2BlackboxPython = 'python'
$r2BlackboxRunner = 'src_fpga/simulation/blackbox_r2_adapter/run_blackbox.py'
& $r2BlackboxPython -I -B $r2BlackboxRunner --suite adapter --modelsim-bin D:/App/modelsim/win64 --td-root D:/App/TD_Release_2026.2.210.850
& $r2BlackboxPython -I -B $r2BlackboxRunner --suite source_borrow --modelsim-bin D:/App/modelsim/win64 --td-root D:/App/TD_Release_2026.2.210.850
```

可重复 `--case <用例>` 选取子集；`--rtl-dir <固定源码快照>` 可绑定另一组不透明源码。
每次运行创建 `tmp/blackbox_r2_adapter/<UTC>_<suite>/`，记录命令、编译输入副本、SHA256、
工具版本、配置和原始日志，不覆盖失败证据。每个 `vsim` 进程最多运行 40 秒，保留 5 秒
给退出与收集结果；HDL 还有独立仿真时间 watchdog。不记录波形，不编译 TD 模型。

| 套件 | 用例及边界 |
| --- | --- |
| `adapter` | `first_raster`：518400 组逐拍核对，首拍/行尾/帧尾与上下文/终态反压，LAST 后等待正确 SOURCE 和读侧排空。 |
| `adapter` | `cancel_first`、`cancel_middle`：取消时保留已承诺 RGB，排空后到负终态并复用；`reset_context`、`reset_output`、`reset_status`、`stopped_clock`：各 held 位复位及下一 owner 首拍。 |
| `adapter` | `malformed`：错 EOL、额外 SOF 和恢复；`source_identity`：上一 owner 错 tag、当前 owner 冲突重复 SOURCE；`source_fault`：显式/隐式错误、同拍优先级。 |
| `source_borrow` | `first_raster`：真 owner 与真适配器，只有外部 ISP 用一拍可反压的确定性 RAW4→RGB4 映射。检查完整首事务、错 tag bit 34、冲突重复 SOURCE、尾拍与终态反压和处理退休。 |
| `source_borrow` | `source_failure`、`cancel_priority`、`cancel_raw_offer`、`source_without_drain`：六字段身份、已承诺 RAW/RGB、显式错误与同拍取消、cleanup/局部复位、普通失败与协议故障后的复用。 |

适配器在 ModelSim SE-64 2020.4 上通过 10/10，首帧 3.344 秒，9 个前缀用例各
1.922–2.344 秒。冻结适配器 SHA256
`129cca5bb8cb2be65ed64664c03e675af52a8b042d4c7c59dd298bf8b20bfdde`，见
[完整结果](../../../tmp/blackbox_r2_adapter/20261108T133722.994145Z_adapter/result.json)。

SOURCE 组合初次运行在同一适配器上使用 owner SHA256
`a46cd8a999ac360b4c530bc7034070e9305a2f20fadb3906e67b0fc6079f7490`，见
[完整结果](../../../tmp/blackbox_r2_adapter/20261108T134959.129713Z_source_borrow/result.json)：

| 用例 | 结果 | 秒 | 公开端口观测 |
| --- | --- | ---: | --- |
| `first_raster` | PASS | 3.344 | 读侧、ISP RAW、RGB 三处各接受 518400 组；早到错 tag 和冲突重复负 SOURCE 分别记 stale，正确 SOURCE 得到成功终态。 |
| `source_failure` | FAIL | 2.031 | 先拒绝 5 种错身份。无 cancel 的匹配负 SOURCE `error=0xa5` 排空 5 组；终态 `ok/error/groups` 期望 `0/165/5`，实际 `0/3/5`。 [原始日志](../../../tmp/blackbox_r2_adapter/20261108T134959.129713Z_source_borrow/source_failure.log) |
| `cancel_priority` | PASS | 2.813 | 同拍取消覆盖 `0xa5`，终态 error 3；5 组、一次 cleanup/复位，下一 owner 正常接收前缀。 |
| `cancel_raw_offer` | PASS | 2.046 | 停住的 RAW 第 5 组仍完成握手；取消后没有新 RGB，第 4 组结束，一次 cleanup/复位后可复用。 |
| `source_without_drain` | PASS | 2.000 | 精确 SOURCE 缺少读排空时锁存故障，阻止复用；复位后新 owner 完成 8 组并负终态。 |

失败日志 SHA256：`c7018f3674f27586caccb9614970d86ca07ceda133cecd498e577c646ed6b41c`。
初次组合结果为 **4 PASS / 1 FAIL**，完整首帧通过不覆盖显式错误码反例。

固定父版 `5bdca7029b4aa9c6005ca67d89d045a92d4fc4a5` 的四个 Git blob 独立冻结，
只用同一测试台运行 `source_failure`，2.453 秒复现相同的 `0/165/5 → 0/3/5`。
因此该行为与父版一致；两次原合同 FAIL 均保留。
[基线输入身份](../../../tmp/blackbox_r2_adapter/baseline_5bdca702_opaque/identity.json)、
[基线结果](../../../tmp/blackbox_r2_adapter/20261108T135258.806259Z_source_borrow/result.json)。

维护方按现有私有 owner 的取消语义澄清了[组合合同](../../../verification_reference/source_borrow_public.md#source-cleanup-and-native-terminal)：
读侧非零 SOURCE 错误在这一层引起本地取消，第一 native 错误精确为 3。保持 leaf 直接
SOURCE 的显式错误码规则和生产 RTL 不变。只修正 `source_failure` 组合期望并重跑该短例，
2.516 秒 PASS：5/5/5 组（读侧/ISP RAW/RGB），cleanup 和局部复位各一次；后续 owner
8/8/8 组并独立到负终态。错身份、held RGB、真实握手与复用断言保持。
[修正后单例结果](../../../tmp/blackbox_r2_adapter/20261108T135438.960332Z_source_borrow/result.json)。
同一生产字节下合计 5/5：初跑通过四项，澄清合同后单例通过；未重跑完整帧。

逻辑 ISP 只验证传输与控制。满幅首事务不外推 ISP 质量、持续帧率、综合、布局布线、时序、
DDR/PCIe 传输或上板资格。
