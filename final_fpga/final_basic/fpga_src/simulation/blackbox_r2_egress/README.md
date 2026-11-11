# r2 JPEG egress 和 HDR FENCE 独立短测

测试作者依据公开端口、合法参数、PCIe 线格式和公开握手合同建立预期值。生产 RTL
和厂商模型仅用于不透明编译和 SHA256 绑定。输入、输出和故障判据分别记录在
[JPEG egress 合同](../../../verification_reference/egress_public.md)和
[HDR FENCE 合同](../../../verification_reference/hdr_fence_public.md)。

JPEG 掩模禁用 profile 的 START mask 与 source type 均为零。START 输入握手后
生产者可复用描述符，RESULT 和扩展仍分别持有各自的数据直到对应握手。HDR 合法
RAW capsule 的高 40 位为零，低 56 位按 lane0 在最低位的顺序拼接四个 RAW14。

从仓库根目录在 PowerShell 运行。可用 `--suite tokens`、`--suite cdc` 或
`--suite hdr` 选择单门。各门有仿真时间 watchdog，整个运行共享 54 秒工具预算。

```powershell
& 'python' `
  refactor/camera_raw_r2/src_fpga/simulation/blackbox_r2_egress/run.py `
  --modelsim-bin 'D:/App/modelsim/win64' `
  --td-root 'D:/App/TD_Release_2026.2.210.850' --suite all
```

## 同一批输入的结果

ModelSim SE-64 2020.4 与显式 TD 2026.2.210.850 模型的三门均 PASS，合计 8.016 秒。
每次运行写入独立目录。最终证据记录了命令、实际输入和测试台 SHA256、模型版本及原始日志。
[最终 result.json](../../../tmp/blackbox_r2_egress/20261108T135830Z-c957aec5/result.json)

令牌和 CDC 展开各保留四条警告，分别为冻结 RAM IP 的两条 ECC 注入端口宽度警告
和 TD 2026.2.210.850 RAM 模型的两条 `INIT_FILE` 越界警告。两门的 RAM 全 410
字均完成写读校验。HDR 的两条警告来自 ModelSim 优化时的 `-L ph1` 库选项提示，
该门的 DUT 由传输和复位逻辑组成。控制台也记录了 `onerror` 的命令上下文提示。

| 短门 | 通过条件和观察值 |
| --- | --- |
| 直接 JPEG 令牌 | 首 flit 的 magic、schema、identity、reserved、session 两半和 epoch 两半单独损坏。flit1 的 sequence、camera、零扩展和 reserved 以及 flit7 reserved 损坏时，完整接收 128 flit 后进入故障隔离。覆盖错索引、提前 FENCE、LAST 后 JPEG、FENCE e3/e4、无 LAST 的负终态和后续恢复。连续 24 拍实测 24 拍无空拍，共 379 个 KEEP 字节。 |
| 真实 JPEG CDC | 两个异步时钟，官方 FIFO 与 RAM。两笔连续帧经 START、JPEG、128 flit 和 RESULT，capture 从 `ffffffff` 环绕到 `00000000`，身份随帧切换。首笔核对 410 个 40 位 RAM word，包含末字补零。检查 START、数据首尾、扩展和 RESULT 反压，扩展读租约，旧身份借用隔离，以及 RESULT 排空后才证明 fence。目的钟停止时仅断言源复位取消未握手的 RESULT，恢复后首笔成功。 |
| HDR PIX FENCE | 8×2 的四组 RAW14 到成功 SOURCE，下一 owner 三组后用精确失败 FENCE 排空。SOURCE 反压时保留 FIFO 头。坏 tag、计数和保留位各自隔离。停 PIX 后复位取消持有的 SOURCE，下一 owner 重新成功。该门用公开 FIFO 读口 BFM，DFI 源侧空闲。 |

绑定的主要生产输入如下，其余输入及模型见最终 `result.json`。

| 文件 | SHA256 |
| --- | --- |
| `ordered_frame_egress.v` | `eb5312ed137935d5081d7470d5973f61ae3d3ac0735559bb77cf072b34c7a81d` |
| `ordered_frame_cdc.v` | `976c55d96763f8e69e9b686fc84719fc4609ccba7423778c2c8481b80ce46455` |
| `hdr_raw14_shared_transport4.v` | `34963c31b7b050384663a11dd078741c229821f24445c9e80d02e9a081a1c404` |

首轮令牌门在翻转 flit1 sequence 后仅等待 32 周期即判故障缺失，日志和输入哈希均已封存。
维护者确认完整 base 资格在 128 flit 暂存和 RAM 写完后判定。复测保持相同生产 RTL，
把坏 base 输入送全后要求锁存故障且没有扩展、shape 或 RESULT。首 flit 和错索引
仍按早期隔离判定。
[首轮 sim_tokens.log](../../../tmp/blackbox_r2_egress/20261108T135331Z-b1d7c640/sim_tokens.log)
[首轮 result.json](../../../tmp/blackbox_r2_egress/20261108T135331Z-b1d7c640/result.json)

本批结果限于短报文和小几何功能仿真。整机满幅帧率、DDR B、PCIe SAFE、槽退休、
综合、布局布线、时序和板级在本批均为 NOT_RUN。
