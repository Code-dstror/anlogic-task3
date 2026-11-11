# HDR 槽年龄比较的时序试验

5bd 的 seed90 `phy_1` Routed detail L18025 显示 −0.585 ns DFI setup。实际 launch 是 CAM1 writer `o_frame[145]`，经描述符的时间戳低字比较，进入 `hdr_eye_shared` 槽分配的 bank_state CE。seed93 detail L20368 的 −0.651 ns 由实时 `now_ns[43]` 经高字减一和相邻高字判定进入同族 CE。两条路径的 cell／net 延迟分别为 1.944／5.907 ns 和 1.989／5.937 ns。 [5bd 布线基线](BASELINE_5BD.md)

试验候选把 `stamp.high == now.high-1` 改写为 `stamp.high+1 == now.high`，32 位加减取模。bank 等待窗口中的 `arrival.high` 同样处理，保留 64 位回卷语义。描述符年龄仍有 `now.high != 0` 限定，排除绝对零附近的 64 位回卷。低字比较改为高 16 位优先、相等时才由低 16 位定结果。开下界、闭上界和每次判定的实时 `now_ns` 均由相同输入定义。该变换把高字运算移到已保持的描述符或 bank 到达时间一侧，增加的并行运算开销和真实时序收益需经测量。 [隔离候选](../../tmp/nov9_hdr_age_ab/candidate/hdr_eye_shared.v)

## 隔离试验结果

实际 `hdr_eye_shared` 默认 1920×1080、两眼、四个 bank、真实 `hdr_pair_directory` 及冻结 `ram40_sdp_fixed.ipc`。同一载体以寄存器供描述符和当前时间，保持所有控制和目录输出可观察。新 TD 6.2.3.210850，PH1A90SEG324-2，7.502 ns，4 线程、`area_prior`、partition mapping、`min_control_set=2`、`add_map_lut_struct=on`。隔离工程和运行位于 `tmp/nov9_hdr_age_ab/`，首次 A/B 与补跑各有 150 秒墙钟预算。

| 阶段 | 结果 |
|---|---|
| 基线 `opt_gate` | FAIL。112.531 秒后 `wait_run syn_1` 返回 `PRJ-8806`，原生子进程意外退出。已有 `.opt_gate.end.f`、非空 gate DB 和报告，进程退出码为 1，fresh `.error.f` 数量为 0 |
| 基线独立重开 | FAIL。复核全部输入哈希和非空 gate DB 后，`open_run syn_1` 在 `Import ChipWatcher` 后原生 coredump。耗时 0.421 秒，重开前后 DB SHA256 相同 |
| 候选综合及重开 | PASS。隔离原生 opt_gate 和同工程重开共 118.547 秒。now 高／低字、stamp 高／低字到 bank_state 的四个定向集合均非空，估计裕量分别为 +4.254、+2.750、+3.847、+3.655 ns |
| 独立仿真、P&R、物理时序、bitgen、板级 | NOT_RUN |

两份 raw gate 导出表中，整体估计 SWNS 为 +2.389→+2.442 ns。两份最差均由 `now_q[7]` 启动，终点分别为 `u_hdr/state[2]` 和 `u_hdr/bank`。候选 `u_hdr` logic LUT 1532→1545、ripple adder 171→299、FF 890→890、ERAM 3→3，载体 Slice 2009→2122。+53 ps 的整体估计与 +113 Slice 对应同一隔离载体。原版定向报告尚缺。 [原版 gate 报告](../../tmp/nov9_hdr_age_ab/baseline/hdr_age_probe_Runs/syn_1/hdr_age_probe_gate.timing) · [候选 gate 报告](../../tmp/nov9_hdr_age_ab/candidate/hdr_age_probe_Runs/syn_1/hdr_age_probe_gate.timing)

## 年龄比较隔离对照

为取得同阶段定向数据，从实际源码逐字提取描述符和 bank 年龄表达式，用相同的时钟和输入／输出寄存器进行非工程 `optimize_gate`。补测的共享借位版将 `now.high-1` 拆为两个并行 16 位减一。低半字为零时选择高半字减一，否则选原高半字。两半拼接的结果仍是 32 位模减一，原低字年龄比较保持。原版、逆变换和共享借位版分别耗时 44.969、43.985、46.906 秒，均退出 0，六组定向对象均非空。结果仅覆盖比较表达式，槽状态写使能和布线由实际工程验证。 [原版输入与命令](../../tmp/nov9_hdr_age_ab/cone-baseline/RESULT.json) · [逆变换输入与命令](../../tmp/nov9_hdr_age_ab/cone-candidate/RESULT.json) · [共享借位输入与命令](../../tmp/nov9_hdr_age_ab/cone-candidate-shared/RESULT.json)

| 定向 setup 裕量（ns） | 原版 | 逆变换 | 共享借位 |
|---|---:|---:|---:|
| now 高字 → 描述符资格 | +4.159 | +5.073 | +4.134 |
| now 低字 → 描述符资格 | +4.170 | +3.966 | +4.066 |
| stamp 高字 → 描述符资格 | +5.167 | +4.292 | +4.877 |
| stamp 低字 → 描述符资格 | +5.005 | +4.737 | +4.807 |
| now 高字 → bank 等待资格 | +4.145 | +4.722 | +4.171 |
| now 低字 → bank 等待资格 | +4.019 | +4.047 | +3.831 |
| 载体 SWNS | +4.019 | +3.966 | +3.831 |

逆变换把高字组合延迟转移到描述符，stamp 高字路径损失 875 ps，载体增 128 个 ripple adder 和 113 Slice。5bd 原工程 raw gate 已用 63903／64320 Slice。共享借位版在比较载体维持 98 个 ripple adder，Slice 542→562，SWNS 下降 188 ps。两个候选均未采纳，生产 `hdr_eye_shared.v` SHA256 为 `acf8c8d6c5ee648d6ebb8ea9154116357d2cf6edb8f5554b37f2229d1dd3e76f`。逆变换 SHA256 为 `48f0b6d4e7270c1374d39eebf6f071666bca208cdde31ab62c407a8fbd3cfe61`，共享借位 SHA256 为 `fa192dbf0d4db4a9ed6eed30f1362164d6b202d1a62664f173399016fd5374f9`。 [原版命令与输入](../../tmp/nov9_hdr_age_ab/baseline/RESULT.json) · [原版重开记录](../../tmp/nov9_hdr_age_ab/baseline/REOPEN_RESULT.json) · [候选命令与输入](../../tmp/nov9_hdr_age_ab/candidate/RESULT.json) · [公开短测合同](HDR_BANK_PUBLIC.md)

初次受限启动被 Windows 拒绝执行已登记的 Python。获得运行权限后用相同解释器和 TD 根运行。首次 runner 为两份独立目录设置共同截止时间，补跑对已导出的原版做只读重开并单独运行候选。

```powershell
& 'python' -I -B `
  'refactor/camera_raw_r2/tmp/nov9_hdr_age_ab/run.py' 'D:/App/TD_Release_2026.2.210.850'
& 'python' -I -B `
  'refactor/camera_raw_r2/tmp/nov9_hdr_age_ab/followup.py' baseline-reopen 'D:/App/TD_Release_2026.2.210.850'
& 'python' -I -B `
  'refactor/camera_raw_r2/tmp/nov9_hdr_age_ab/followup.py' candidate-run 'D:/App/TD_Release_2026.2.210.850'
& 'python' -I -B `
  'refactor/camera_raw_r2/tmp/nov9_hdr_age_ab/cone_run.py' 'D:/App/TD_Release_2026.2.210.850'
& 'python' -I -B `
  'refactor/camera_raw_r2/tmp/nov9_hdr_age_ab/cone_run.py' 'D:/App/TD_Release_2026.2.210.850' candidate-shared
```
