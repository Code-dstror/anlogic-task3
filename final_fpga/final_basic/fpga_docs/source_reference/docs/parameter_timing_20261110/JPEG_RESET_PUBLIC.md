# JPEG 源侧复位公开短测合同

测试对象为 `ordered_frame_cdc` 的实际跨域链。使用 [公开接口与线协议](C:/fpga_workspace/anlogic-task3/refactor/camera_raw_r2/verification_reference/egress_public.md) 的所有公开端口、数据布局、扩展 RAM 读口和 fence 规则。固定合法 profile 如下。

```verilog
ordered_frame_cdc #(
    .CONTEXT_ENABLE(1), .WRITE_TAG_ENABLE(1),
    .RECORD_EXTENSION_ENABLE(1), .RECORD_EXTENSION_WIDTH(16384),
    .BORROW_EXTENSION(1), .MASK_CONTEXT_ENABLE(0),
    .EXTENSION_RAM_ENABLE(1), .STREAM_EXTENSION(1)
)
```

## 可观察行为

- 源与汇各自在真实上升沿按 VALID 和 READY 同为高完成传输。使用异步相位的 8.000 ns 源时钟和约 7.502 ns 汇时钟。START 元数据保持至源 START 握手，JPEG 保持 DATA/KEEP/LAST，真实 RESULT 保持身份、长度、状态和对应扩展至各自握手。VALID 为低时载荷未定义。扩展暂存租约按公开协议检查。
- 任意一侧低有效复位断言取消当前 cohort。即使任意时钟停住，源公开 READY、扩展 stream 开始资格、汇公开 VALID 和两侧 reset_done 应撤回，允许组合传播与仿真 delta 收敛。任一复位仍为低时无新传输。复位释放后保持 offer 至各自握手。源、汇各自的 reset_done 是本域传输的资格，独立计分。停钟期间没有采样沿，恢复时只能提交新 cohort 的数据。
- 合法成功帧以 START、至少一拍 JPEG 且恰一拍 LAST、完整 128 个扩展 flit、匹配的实际 RESULT 为顺序。字节 0 为数据的最低 8 位，KEEP 每个置位计一字节。核对 START 的 session/epoch/sequence/camera/tag、实际 JPEG 字节与 KEEP/LAST、扩展头和 RAM word，以及 RESULT 的身份、质量、长度和成功标志。待下游真实接收 RESULT 并排空后才评分 fence prove。
- 启动和复位恢复的外部握手时序应保持。可使用固定 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213` 作为公开端口边沿对照。同一刺激、相位、READY 时序及不同的运行库下记录 reset_done、首个公开握手和终态相对边沿。独立的协议期望决定正误，A/B 边沿比较额外检验是否引入等待周期。

## 必测风险

1. 双侧释放。第一笔合法短帧预先提供 START，合法扩展通过实际 FIFO 和暂存 RAM，到下游 RESULT 握手及 fence prove。固定 START 或 LAST 时有限反压，核对 offer 保持和恰一次传输。
2. 首笔资格边界。双复位撤销后，在源第三个真实上升沿拉长高相，然后恢复正常源时钟。源 offer 持有并在实际 READY 时前进。按公开 reset_done 和握手计数，比较同刺激的首笔边沿与终态。再覆盖停在低相的一次释放。每次重启给不同的帧身份和内容。
3. 停源时钟后从汇侧断言复位。先让有效帧进入扩展借用或 RESULT 反压阶段。取消过程中确认公开资格及时撤回，恢复后只接收新的 START、JPEG、扩展和匹配 RESULT。用另一次短运行覆盖源侧复位断言和不同的时钟停止相位。结束前完成新帧的下游 RESULT，核对无残留成功或重复。
4. 正确身份但错误的成功长度。发送实际 KEEP 计数及最后一拍，按既有 E2 规则期待负结果。若在复位前反压终态，保持 offer，取消后用下一笔合法帧证明恢复。扩展 oracle 使用公开协议，勿依赖旧 DUT 输出。

## 不透明编译

使用 [公开实际跨域链编译清单](C:/fpga_workspace/anlogic-task3/refactor/camera_raw_r2/verification_reference/egress_public.md) 的完整闭包，额外编译 `refactor/camera_raw_r2/src_fpga/rtl/reset_release_sync_data.v`。该文件也可加入基线闭包。显式指定 TD model 根 `D:/App/TD_Release_2026.2.210.850/sim_release`，ModelSim `D:/App/modelsim/win64`，独立基线/候选库，`PH1` 宏和公开清单的 sibling top。测试作者可哈希并编译，评分只用公开端口和协议，生产 RTL、旧 TB、vendor 模型、内部层次均不作为输入资料。测试进程墙钟上限 60 秒并设仿真 watchdog。保留命令、输入和 TB SHA256、真实握手与终态记录。
