# RAW 透传黑盒仿真

测试台通过 `stereo_raw_store` 和 `raw_video_record_formatter` 的公开端口驱动相机写入终态、AXI 读响应、主机反压及 SAFE 退休。独立记分板根据捕获时写入的描述符、DDR 字节样本及 ARAW v1 字段布局逐字节比较。运行器仅将生产 RTL 和 TD 仿真模型交给 ModelSim 编译，并记录输入 SHA-256。[公开端口与 ARAW v1](IO_CONTRACT.md)

## 复现

从仓库根目录使用 PowerShell 7。模型路径由 `-TdRoot` 显式指定，默认 ModelSim 路径为 `D:/App/modelsim/win64`。每个用例的进程硬上限为 50 秒。测试台另有 20 μs 或 60 μs 的仿真时间 watchdog。

```powershell
& 'refactor/camera_raw_r1/src_fpga/simulation/blackbox_raw_20261107/run_blackbox.ps1' `
    -TdRoot 'D:/App/TD_Release_2026.2.210.850' -Seed 531271
```

可用 `-Case store_order_and_safe,store_4k` 选择用例。每次运行在 `refactor/camera_raw_r1/tmp/blackbox_raw_20261107/` 创建独立目录，保留 `run.json`、逐用例日志和工具版本日志。判定要求仿真进程正常退出、对应 `BLACKBOX_PASS` 标记存在且日志没有 Fatal 或 Error。

## 事务约定

- BEGIN 在 `s_begin_valid && s_begin_ready` 同拍读取 `o_begin_accepted` 和槽号。满槽的 BEGIN 返回 accepted=0，释放后以新请求重试。
- 冷空闲由 `o_empty` 和 `o_read_quiet` 判断。`o_raw_drained` 适用于本次已接收的读事务。RAW DONE 终态保持到匹配 SAFE 握手或共同复位，DONE_OK 需要真实末拍握手和正常 AXI 终态。
- 兼容处理描述符的 `[383:367]` 和 bit 0 清零。Bayer 和时间有效性由独立端口返回，按捕获值检查。描述符和借用的 128 位身份保持到 SAFE 握手。
- SAFE 握手与真实槽退休分开计数。匹配 SAFE 可以在 `i_release_quiet=0` 时被接收，槽位必须等 `o_retire_done` 才能复用。错身份不能握手。

## 用例

| 用例 | 检查 |
| --- | --- |
| `formatter_lengths` | 1、15、16、17、65 字节载荷，64 字节头部，四种 Bayer，时间有效位，尾拍 KEEP/LAST 和随机反压 |
| `formatter_abort`, `formatter_reset` | 分别阻塞四个头拍再中止，已接受的非末载荷拍后中止，阻塞头拍时共同复位，再启动新记录 |
| `store_order_and_safe` | BEGIN 及失败终态不发布，双眼同序号并分别回绕，同眼真实捕获顺序，128 个单比特错 SAFE，其他眼在写时的两阶段退休，满槽拒绝和代次更新 |
| `store_4k` | 4160 字节、260 个 AXI R 拍；地址连续，单次 burst ≤16 拍，跨 4 KiB 分 burst，首 burst 未返回 R 时保持 ARREADY 高 11 拍 |
| `store_stop_offer`, `store_stop_last` | STOP 时保持已呈现的记录或末拍，允许其真实握手后报负终态，丢弃未呈现记录 |
| `store_cancel_ar`, `store_cancel_await_r` | AR 被阻塞或已接受但尚无 R 时 cancel，等已承诺 burst 完整排空，检查后续请求和槽退休 |
| `store_cancel_payload`, `store_cancel_combined` | RAW 首拍受阻时 cancel，保留已呈现载荷，组合路径等待读排空后合法中止 ARAW |
| `store_rresp`, `store_rresp_final` | 首拍 SLVERR、末拍 DECERR 均产生负终态，随后复位并验证合法记录和旧 SAFE 隔离 |
| `store_bad_rid`, `store_early_rlast`, `store_missing_rlast` | 错 RID、提前 RLAST、末拍缺失 RLAST 各自保持故障且禁止安全排空/退休，复位后恢复 |
| `store_reset_pending_raw` | 在途 AXI、受阻 RAW 和 ARAW 头拍同时复位，变更会话后验证新记录及旧 SAFE 隔离 |

正常 store 测试以 `8×2` 的 20 字节载荷检查两拍 DDR 数据，第二拍 `KEEP=000F`。4 KiB 和 AR cancel 用例采用 `16×208`，后者只服务 cancel 前承诺的 burst。周期为 7.5 ns。仿真状态与综合、布局布线、静态时序和板级状态分别记录，后四项为 NOT_RUN。

## 结果

最终种子 531271 的 17 个用例全部 PASS。单次 ModelSim SE-64 2020.4 进程为 3.167–4.133 秒，整套含编译和输入校验累计 60.154 秒。4 KiB 用例接收 17 个 AR、260 个 R，逐字节比较 4160 字节 RAW 和 4224 字节 ARAW 记录。首 burst 的 11 拍高 ARREADY 窗口内没有接收额外请求。第二套增加了该窗口和逐拍排空承诺检查，两套的 14 项生产和 TD 模型输入 SHA-256 相同。仿真结束后重新核对了最终清单的全部 19 项输入哈希。

最终证据位于 `C:/fpga_workspace/anlogic-task3/tmp/blackbox_raw_20261107/20261107T151203.384Z-15772/run.json`。源 HEAD 为 `38d5c614f34fdbd1e096a9522c1d4dec4e4d22a0`，生产源和 TD 模型的实际输入以清单哈希为准。证据保留在实际执行目录。收尾时将运行器默认产物路径改到子工程 `tmp/`，该路径改动进行了静态检查。

## 早期测试记录

以下目录仍保留初始断言失败。修订针对公开握手定义及测试台采样，期望数据始终来自测试输入和 ARAW 合同。

| `C:/fpga_workspace/anlogic-task3/tmp/blackbox_raw_20261107/` 子目录 | 首次断言及归因 |
| --- | --- |
| `20261107T150017.263Z-38540` | 误要求冷空闲 `o_raw_drained=1` |
| `20261107T150116.716Z-7132`, `20261107T150222.824Z-37660` | 将保持的 `o_begin_accepted` 每拍计作事件，实际应在 BEGIN 握手采样 |
| `20261107T150306.191Z-30444` | 将输入扩展位当作兼容处理描述符的输出字段；独立 Bayer、时间有效端口仍检查原始输入 |
| `20261107T150649.397Z-41904` | 将保持的 RAW DONE 逐拍计数，并误限定 DONE_OK 必须在末拍当拍或下一拍出现 |
| `20261107T150824.504Z-9012` | 公开 DONE/SAFE 语义修订后的四组定向检查 PASS |
| `20261107T151019.659Z-38184` | 种子 874831，17 组完整检查 PASS |
