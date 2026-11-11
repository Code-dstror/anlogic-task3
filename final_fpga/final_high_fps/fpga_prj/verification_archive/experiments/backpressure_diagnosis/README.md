# DDR 写响应期限诊断

状态 **DIAGNOSTIC_ONLY**。保留原 a10 正向门的 FAIL。其外部 BFM 按 AXI 提供合法的晚响应，
但超出本工程 DDR 服务期限。原正向门漏写该期限。生产 RTL、超时参数和原始测试均保持原样。

实际 `ddr3_jpeg_store` 默认 `AXI_TIMEOUT_CYCLES=4096`，传给生产双客户端仲裁器。
仲裁器 `ddr_axi_two_client_arbiter.v` 在速率、画质、RAW 和融合候选字节一致，SHA256 为
`380eeec665aa03ab2c0fffb944747afcbe4399f3182ab917496d0a6dfe73b446`。
融合 `ddr3_jpeg_store.v` 与速率 R3 一致，SHA256 为
`e60fe999ce02fa4720efcc032d9de468377291c5b58fc051ee6d2f396fd09c25`。
祖先实现及公开规格都规定 watchdog hard recovery、原承诺保持和共同复位。 [双客户端仲裁器规范](../../../../src_fpga/rtl/ddr/ddr_axi_two_client_arbiter_spec.md)

若最后一拍 W 在 DFI 沿 `k` 转移，沿 `k+1` 至 `k+4096` 可采样 BVALID。
`k+4096` 尚未见 BVALID 时锁存恢复要求。BVALID 已呈现但客户端暂时未给 BREADY 时不计作缺服务。
a10 在 `k+4096` 沿后才呈现 BVALID，`k+4097` 接受。其 ID、状态、W/R 末拍与债务账目检查均通过。

| 时间 ns | 诊断观察 |
| ---: | --- |
| 162692 | JPEG 第一个 WLAST 真实接受，已写 256 B |
| 193420 | DFI cycle 14820，写响应等待计数 4095，BVALID=0/BREADY=1。首个 watchdog 为写，读等待为 0。仲裁器同沿锁存恢复，顶层 store/raw 故障同沿出现 |
| 193428 | DFI cycle 14821，承诺的旧 JPEG B 正常握手。保持恢复隔离，不启动新事务 |
| 200948 | RAW SOURCE `ok=0`，RAW 已读 1120 拍。原正向断言于此终止 |
| 205396 | 续看 JPEG SOURCE `failed=1` |
| 220900 | 续看 JPEG RESULT `ok=0,length=0` |
| 290965 | 12,000 个额外 DFI 拍后，外部 AXI 欠账为 0，fault 仍高，RAW owner 与 record 仍未宣布 quiet；capture 和 buffer 未就绪。writer ACK、ticket、RAW retire、record offer/retire 和 host 数据均为 0 |

待独立产品门覆盖期限内完整首产品、期限外承诺 B 排空和协调 cold reset 后的合法首产品。
无整机综合、布局布线或板测证据。

## 重放

以仓库 `ENVIRONMENT.local.md` 登记的 CPython、ModelSim SE-64 2020.4 执行。沿用 a10 的 TD
2026.2 / 6.2.3.210850 模型编译库与 ROM 文件。脚本将库复制到独立目录，用 `+acc` 被动读取首故障。
续看跳过原正向极性和成功产物断言并记录随后状态，保持同样输入、DDR B 时序和生产设计。
每次 ModelSim 执行的墙钟上限为 60 秒。实际命令保存在各诊断目录 `simulate.json`。

```powershell
& $fusionPython -B refactor/camera_fusion_r1/experiments/backpressure_diagnosis/run_trace.py --modelsim-bin $fusionModelSimBin --run-dir refactor/camera_fusion_r1/tmp/backpressure_diag_a10_fresh
& $fusionPython -B refactor/camera_fusion_r1/experiments/backpressure_diagnosis/run_trace.py --modelsim-bin $fusionModelSimBin --run-dir refactor/camera_fusion_r1/tmp/backpressure_diag_a10_fresh_continued --continue-after-timeout
```

| 原始记录 | SHA256 |
| --- | --- |
| [a10 输入索引](../../tmp/blackbox_fusion_product_a10_all_b/inputs_before.json) | `f8ede53744edf21d472a28236a759997bc3d8f2a407527acef48f10fbae6d8ec` |
| [a10 原始 FAIL](../../tmp/blackbox_fusion_product_a10_all_b/normal/simulate.log) | `e88047d93da37f1081d1f5448d346c48209fcfacfc318370af72c3d63b21a06c` |
| [被动首故障 trace](../../tmp/backpressure_diag_a10_01/simulate.log) | `39e22df3a8c714b8307c794c7d66c402c95b5e709e1c810a30ade36eee183472` |
| [超时后续看](../../tmp/backpressure_diag_a10_02_continued/simulate.log) | `bdfcfdc7d5ca6baa68f9221e3b364d93a6fada100d9f03c82d380f2a82266974` |
