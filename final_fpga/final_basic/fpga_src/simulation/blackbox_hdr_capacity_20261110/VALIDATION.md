# HDR RAW owner 控制容量验证记录

`full-r02` 的 ModelSim 功能仿真八个场景均通过。载体使用实际 RAW 捕获、写者、目录、
owner、派发和调度器。测试作者只使用公开端口与合同，外部字节图样和帧身份来自固定
输入计划。 [结果](../../../../../tmp/hdr_rate_seed56_20261110/capacity_blackbox/full-r02/result.json)

## 首事务和容量拒绝恢复

`first` 在两眼各送一组 LONG/SHORT。四个成员均真实 SOURCE 握手，320 B 按槽逐字节
匹配，完成 4 AW、20 W、4 个 OK B，出现 5 个 W 有效而未就绪的拍。两笔 acquire 均
在各自 SOURCE 和最后一次 OK B 之后，随后得到完整的 job/pair ID 和双租约，经
member、context、START、RESULT 和已匹配处理终态，分别在 DFI 拍 1887、3476 真实
RELEASE。两次 retire acknowledgment 齐全，最终 quiescent。 [首事务](../../../../../tmp/hdr_rate_seed56_20261110/capacity_blackbox/full-r02/first.stdout.log)

`late-peer` 在 CAM0 两 bank 均占用时于 690 拍记录 C LONG 的负 BEGIN。A 在 1879 拍
RELEASE。C SHORT 于 2120 拍到达，2140 拍仍获负 BEGIN，此时 A 的 bank 已空且 B
仍为 OWNED。下一组 D LONG 于 2369 拍到达，D 最终于 5059 拍 RELEASE。该场景的四组
均有两成员 SOURCE，A、B、D 三组 job 和退休一一对应，C 无 job 或残留写入。
[恢复轨迹](../../../../../tmp/hdr_rate_seed56_20261110/capacity_blackbox/full-r02/late-peer.stdout.log)

## 三相位 A/B

两眼各以 3,300 DFI 拍送一组，SHORT 相对本眼 LONG 晚 100 拍，捕获终点约在 2,900
和 3,000 拍。每眼 30 组热身后，以组身份统计后续 60 组，两眼每种角色各有 60 次
SOURCE。各相位快慢两侧的 720 条 SOF 和 SOURCE offer 记录逐条一致。

| CAM1 相位（DFI 拍） | 实际服务（DFI 拍） | CAM0 job / RELEASE | CAM1 job / RELEASE | CAM0 / CAM1 缺组 | 两眼测量组尾排空退休 |
|---:|---:|---:|---:|---:|---:|
| 100 | 1947 | 60 / 60 | 40 / 40 | 0 / 20 | 1 / 1 |
| 100 | 1587 | 60 / 60 | 60 / 60 | 0 / 0 | 1 / 1 |
| 400 | 1947 | 50 / 50 | 50 / 50 | 10 / 10 | 1 / 1 |
| 400 | 1587 | 60 / 60 | 60 / 60 | 0 / 0 | 1 / 1 |
| 3200 | 1947 | 40 / 40 | 60 / 60 | 20 / 0 | 1 / 1 |
| 3200 | 1587 | 60 / 60 | 60 / 60 | 0 / 0 | 0 / 1 |

每个缺组在其同眼的 LONG 和 SHORT 各有一次负 BEGIN。快侧含热身的两眼各 90 组均
全收全退，零负 BEGIN。六场景均零 pair expiry、坏 FINISH、fault。三组慢侧全程真实
acquire、job、RELEASE 和 retire 总数分别为 150、150、151，快侧分别为 180。

共同边沿窗 `[99119, 297119)` 中，每眼每角色均有 60 次 SOF 和 60 次 SOURCE。该窗内
job、BFM 处理完成和 RELEASE 的逐眼计数等于表中对应数值。表中的尾排空按身份另计，
它统计最后一次实际 SOURCE 握手后退休的测量组，属于表内 RELEASE 计数的子集。

每笔实际 acquire→job 为 20 DFI 拍，job→START 为 3 拍，START→RESULT 快、慢分别为
1555、1915 拍。acquire→RELEASE 快侧恒为 1587 拍，慢侧恒为 1947 拍，分别落在
1,650 拍服务预算以下和以上。

## 复现与范围

```powershell
& 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_capacity_20261110/run.ps1' `
  -RunId full-r02 `
  -TdRoot 'D:/App/TD_Release_2026.2.210.850' `
  -ModelSimBin 'D:/App/modelsim/win64'
```

以上命令为已运行记录，复跑时更换 `RunId`。ModelSim SE-64 2020.4 与本机 TD 模型
6.2.210.850。八场景墙钟耗时 2.329–2.728 秒。初次展开 0 errors、207 warnings，
其中 197 条涉及未接输出或端口，2 条涉及冻结 RAM 的 ECC 输入位宽，8 条涉及 RAM
空初始化范围。原始日志完整保留。 [精确 argv](../../../../../tmp/hdr_rate_seed56_20261110/capacity_blackbox/full-r02/commands.jsonl)

26 项生产 HDL/IP/include 的 Git blob 与 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213`
一致。所有输入运行前后 SHA256 一致。

| 文件 | SHA256 |
|---|---|
| `tb_hdr_capacity.sv` | `3cb4a3592162e3b517534c70ce14b61536c1738339bcc5a5326dcbe8b932bda4` |
| `run.ps1` | `cd4c3319473c8892821709b3458fdf0ed85c22883ba395ee0aac207bddbf2a38` |
| `owner_service_carrier.v` | `cc87e87643f2711120e94f39fc6708273f6a88b304423c8ed2d6a659957fa4e3` |
| `OWNER_CAPACITY_PUBLIC.json` | `1ae479b07a740cef1b124e3146e30e0b522f8e163bd7bd7c5c34f5c60b2629f1` |

[生产闭包身份](../../../../../tmp/hdr_rate_seed56_20261110/capacity_blackbox/full-r02/production-identity.json)
· [输入哈希](../../../../../tmp/hdr_rate_seed56_20261110/capacity_blackbox/full-r02/inputs-before.json)

本门只覆盖 16×4 RAW 控制、规定的时钟相位和给定服务时限。DDR、reader、PIX/JPEG 和
票据终态为 BFM，真实满幅 DDR/处理吞吐与持续 1080p30/30 需独立验证。STOP、取消、
模式切换和板上时序未纳入该合同。综合、P&R、STA、bitgen、板级均 `NOT_RUN`。
