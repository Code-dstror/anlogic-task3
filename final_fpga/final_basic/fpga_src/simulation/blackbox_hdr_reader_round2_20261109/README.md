# 双目 HDR 读端 512 组短测

独立黑盒作者仅使用公开接口与数值合同。生产 cursor、共享 RAW10 decoder、两只官方 ERAM 和 HDR merge 经真实握手跑到 reader RESULT。两版各 4/4 通过，每个成功作业按独立 oracle 校验全部 1,071 个 RAW14、motion 和边界组，对应结果文件逐字节相同。 [公开合同](../../../docs/seed12_round2_20261109/HDR_READER_PUBLIC.md)

| 用例 | 基线 → 候选 | 观测 |
|---|---|---|
| 首个 68×63 作业、固定 32 拍 AR 到首 R | 46→42 AR，3,501→3,389 拍 | 两曝光共 670 个 R beat，4 KiB 边界和 11B 末字正确 |
| 快读和有限输出/RESULT 反压 | 46→42 AR，5,783→5,767 拍 | 两队列峰值 496/488→512/504，稳定保持 VALID 与数据 |
| AR 被反压时取消 | 均一笔 16 拍，60 拍到负 RESULT | 已呈现 AR 保持 7 拍，完成真实 RLAST，无协议故障 |
| 同一复位周期的后续不同 camera/bank | 46→42 AR，3,501→3,389 拍 | 新输入产生独立的正确结果 |

真实运行使用 ModelSim SE-64 2020.4 和 TD `D:/App/TD_Release_2026.2.210.850` 的模型。两版分别耗时 3.960 和 4.252 秒，仿真 0 错误、各 8 条相同的官方 ERAM 模型告警。`run01/baseline`、`run01/candidate` 在工作区 `tmp/seed12_round2_20261109/hdr_reader_bb` 中各保存 `commands.jsonl`、`inputs.before.json`、`inputs.after.json`、`results.log`、`axi.tsv` 及输出 SHA256。隔离基线使用 `492c53845ef6d4830a6bad0759aef82c8d002df3` 的 cursor，Git blob `30f189201135454bd78c83516e9671e2e5aa5cc3`。在本轮实际运行中该快照位于 `tmp/seed12_round2_20261109/hdr_reader_baseline/hdr_pair_read_cursor.v`。

从仓库根目录用新的运行目录复现。基线文件须是上述 Git blob 的原始字节。

```powershell
pwsh -NoProfile -File refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_reader_round2_20261109/run_hdr_reader_bb.ps1 `
  -ModelSimBin D:/App/modelsim/win64 `
  -TdRoot D:/App/TD_Release_2026.2.210.850 `
  -BaselineCursor tmp/seed12_round2_20261109/hdr_reader_baseline/hdr_pair_read_cursor.v `
  -RunRoot tmp/seed12_round2_20261109/hdr_reader_bb/reproduce01
```

仿真覆盖读链功能和 BFM 读延迟。满幅每 HDR job 的 AR 从 21,718 到 20,250 是按固定 RTL 地址限制的算术，减少 6.76%。当前新整机综合、布局布线、物理时序和板级吞吐资格须另行记录。
