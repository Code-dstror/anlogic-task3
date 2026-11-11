# Seed12 双目 HDR 准入、bank 归还与读端审阅

板测来源为 `4a08ae35391e7b7ea6767260d7d1b4b182ef4bb9` seed12。审阅起点为 `492c53845ef6d4830a6bad0759aef82c8d002df3`。两者相关差异是前端孤立 SHORT 的等待资格和公开合同，本记录把重入暖机卡住与已运行 HDR 丢组分开。

## 同窗对账

按原始 `repeat-round/fpga-startup-window/decoded.jsonl` 以相同 UART 序号界分别取 DJ/v3 和 OB/v2。各页和各协议仍为独立握手快照。四窗开始与结束的 OB 三域和 DJ 两域均 fresh、reset_n 有效。逐秒展开 8bit BEGIN 计数，PIX admit 和 DFI jobs 用 16bit 模数。表内“缺 job”是每眼该窗的 LONG/SHORT admit（两者相等）减该眼 job。

| epoch | UART 序号 | 每路 admit | jobs 0/1 | 缺 job 0/1 | 负 BEGIN 0/1 | expiry、bad FINISH 增量 |
|---:|---|---:|---|---|---|---|
| 1 | 369–377 | 242 | 200/203 | 42/39 | 84/76 | 均 0/0 |
| 3 | 380–383 | 91 | 91/60 | 0/31 | 0/60 | 均 0/0 |
| 8 | 411–418 | 212 | 141/212 | 71/0 | 140/0 | 均 0/0 |
| 19 | 441–448 | 212 | 212/142 | 0/70 | 0/142 | 均 0/0 |

| epoch | DFI jobs 总计 | PIX frame admission / JPEG result | DFI writer ACK / ready claim | USER native descriptor / retire |
|---:|---:|---|---|---|
| 1 | 403 | 403/403 | 403/403 | 404/404 |
| 3 | 151 | 151/152 | 152/152 | 152/152 |
| 8 | 353 | 353/353 | 353/353 | 353/353 |
| 19 | 354 | 354/355 | 355/355 | 354/354 |

每眼负 BEGIN 折合的组数与 job 缺口相差至多一组，已接 job 与下游总量仅有窗口边界的一笔差。这定位到了作业接纳前的主要缺口。现有 BEGIN 累加所有负答复，故还需容量原因分计。29 个窗内秒级样本中，部分采样同时显示 scheduler idle、credit reserved、读端 quiet，以及只有 BUILD/FREE 的 bank（例如序号 382、383、414、415、448）。这给出共享服务可能存在空档的现象，短时 DDR/信用反压仍可造成前一级满槽。

## 生产路径与时间预算

- `shared_raw10_frame_ingress.v`、`shared_raw_capture_writer.v` 把真正准入的 RAW/SOURCE 送经 FIFO。BEGIN 收拒会排空该成员，已获槽写入等匹配 SOURCE/端标志与真实 AXI B 后才 FINISH。`hdr_eye_shared.v` 只把两成员 FINISH OK 的 bank 发布 READY。同组、角色、时间、配方、会话、epoch 均有真实资格。
- `hdr_eye_shared.v` 每眼两个 bank。合法新组无 FREE 且同眼本拍没有接受 RELEASE，`CHECK_BEGIN` 记 `remember_capacity_drop` 并在 REPLY 拒绝。后到 peer 遇到 capacity group floor 也被拒绝，即使届时有 FREE。同眼 RELEASE 在容量决定拍被接受时，owner 已留一拍重判。这一组级机制与板测两笔成员拒绝对应一组的形状相符。
- `full_raw_store.v` 的 `g_eye_dispatch` 在两眼 offer 都有效时使用轮转，真实 release 后将下一轮优先给另一眼。只到一眼 READY 时立即选该眼。慢眼交换符合物理相位和有限槽截止条件。对持续 READY 的对手，当前逻辑提供轮转服务。
- `raw_pair_job_service.v` 接管 pair 后读取 LONG 目录，随后给 `raw_hdr_phase_scheduler4.v` 单一 job。HDR START 后等真实 reader result、匹配的处理终态与 whole quiet，再发 owner retire。`raw_job_ticket_context_cdc.v` 等像素终态、匹配 JPEG writer ack、读写静默和 PIX RELEASE_ACK 才归还票据。`full_raw_store.v` 正常运行使用目标 OWNED 槽本地退休，其他 RAW capture writer 可继续运行。JPEG writer quiet 是写端证明，READY 记录和 USER 读/退还有独立生命周期。STOP/CFG 保持全局 drain。
- 30.28/s 每眼要求共享服务平均每 16.51 ms 接一笔，并给摄像头相位、写入完成和有限两 bank 留余量。约 50.5 job/s 的窗均摊是约 19.8 ms 每笔，包含 idle。单笔实际 RAW 占用与各阶段时间需分别实测。
- 一个简化离散事件模型即可出现相同的计数形状。两眼各按 33.02 ms 启动采集，每组占一个 bank 到真实退休，采集 30 ms 后 READY，双眼共享一笔固定 19.5 ms 服务，两眼同时 READY 时轮转。预热 30 组后计数 330 组，固定相位差约 0.1、4、33 ms 分别得到约 30.28/20.19、25.24/25.24、20.19/30.28。模型只说明两 bank、串行服务与相位可以产生观测形状。板卡上的采集时长、作业服务时长和相位仍待测。

## 最小读端改动

主工程 `rfcamera_raw_r2.al` 登记 `hdr_pair_read_cursor`、`hdr_pair_pixel_reader` 和 `shared_raw10_decode_service`。顶层 `anlogic2026` 的 `g_hdr_source` 实例化外部共享 decoder 及 `hdr_pair_native_source_service4`，后者走实际 pixel reader 与 cursor。生产 NR 关闭，DDR 共享走 `ddr_axi_two_client_arbiter`。该仲裁器把 HDR 读作为 client1，接受符合 4 KiB 和 16 拍限制的 burst，同 client 旧响应队列为空才选择下一笔。cursor 等上一笔真正 RLAST 后再准备下一笔 AR。

原 cursor 每个非尾 chunk 155 个 16B 字，等于 496 个 RAW10 group。候选采用 160 个字，正好 512 个 group 且每个非尾 chunk 的起止均在 16 拍界，沿用现有每笔 AXI 上限和 4 KiB 检查。1080p 每成员 2,592,000 B、162,000 个字。逐 burst 算法是先按 chunk 切分，再按 `min(16, 本 chunk 剩余字, 距下个 256 字边界)` 分配。每成员 AR 从 10,859（其中 1,601 短 burst）降到 10,125（全 16 拍），每 job 少 1,468 次即 6.76%。用每减少一笔省 20–60 个暴露的 DFI 等待周期举例，差为约 0.22–0.66 ms。这个换算与 DDR 仲裁、读延迟、decoder 有效重叠和下游反压有关，不代替同模型 A/B 或板测。

容量证明来自以下生产接口条件。

1. cursor 在 SELECT 时前一个 chunk 的 AXI debt 已结清、待送的 AXI word 已消费。选中成员的 public credit 要求其实际 occupancy 为 0，当前无同成员 native 有效组，且其已入队组数换算字节与 cursor 接收字节进度低 12 位相等。
2. 对同一成员，cursor 已接收与 decoder 已入队的字节差非负。每次授权前为零，此次授权后最大 2,560 B，严格小于 4,096 B，故低 12 位相等仍是精确的零欠账。共享 reservoir 若持有另一成员，必须排空它才能切换，目标成员的已认证空容量仍然有效。
3. 完整 chunk 为 2,560 B，恰有 512 个完整组。末 chunk 至多同长，并在最后 AXI 字用原 keep 限制有效字节。每组仅在真实 `native_valid && native_ready` 入队，最后一个可从 511 增到 512。占用到 512 时该队列拒绝额外 push，已颁 chunk 没有第 513 组。配对读从 RAM 取走的组使用独立的保持寄存器，释放后的物理队列槽可安全再用。正常和取消路径仍使用原 RLAST、merge drain、result 和归还契约。

代码变化集中在 `hdr_pair_read_cursor.v` 的分块常量及同一阶段的界限判断，`hdr_pair_pixel_reader.v` 更新相邻容量证明注释。没有增加存储、DSP、接口位宽或 CDC。常量比较的门级映射和 DFI 裕量需新综合/物理证据。这个改动改善读请求效率，现阶段无法将 50→60 或慢眼消失作为结论。

| 范围 | 候选作用与核对 |
|---|---|
| DFI `hdr_pair_read_cursor` | 160 个字的既有 CHUNK/PREPARE 运算。两成员字位置、末字 KEEP、AXI ID、事务形状与有债取消继续使用同一规则。 |
| DDR client1 | 对每段有效数据请求相同 DDR 地址范围，固定 16B/拍、≤16 拍、4 KiB 不跨页。控制器、仲裁器和响应 RAM 无改动。 |
| `hdr_pair_pixel_reader` 及 ERAM | 两个现有 40×512 队列，满值 512。采用完整容量，原 12bit 字节进度证明仍覆盖；同一官方 IPC 与端口。 |
| 像素身份及传感器 | RAW10 裁剪、VC、SOF/FE/SOURCE、bank 地址与几何参数照旧。AXI 分块发生在写成功、两曝光配对之后。末 chunk 对任意合法 `WIDTH % 4 == 0`、正 `HEIGHT`、整帧可装 slot 的形状仍按真实字数收尾。 |
| DFI 后半与 PIX/USER | 相同 RAW14 像素、motion、栅格边界、票据、FENCE 和 RELEASE 规则。无需工程清单增项或 CDC/STA 例外。 |

## 验证及板测区分

原 cursor 快照 `hdr_reader_baseline/hdr_pair_read_cursor.v` 的 SHA256 为 `328a0bf1501df4962859f4ef480857039781baeff65fbbaf26c493adcfb6d879`，Git blob `30f189201135454bd78c83516e9671e2e5aa5cc3`。独立作者使用 [公开合同](../../refactor/camera_raw_r2/docs/seed12_round2_20261109/HDR_READER_PUBLIC.md) 和 [真实读链载体](../../refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_reader_round2_20261109/hdr_reader_carrier.v)。68×63 跨两次 512-group 边界、4 KiB 和 11B 末字，检查 512 占用、反压稳定、合法首 job 到结果、已发 AXI 取消排空与下个不同 camera/bank 的结果。A/B 复用相同 BFM、相同输入及独立输出 oracle，检查 RAW14、motion、边界和实际 result，并报告同模型 AR 数和周期。物理 DDR、JPEG、主机以及持续满幅性能属于后续不同层次的资格。

独立短测两版各 4/4 通过。首笔及取消后的新 camera/bank 在同一固定 32 拍 AR 到首 R 的模型下为 46→42 笔 AR、3,501→3,389 拍 START 到 RESULT。每笔两曝光共 670 个 AXI R beat，按独立 oracle 输出 1,071 组和 214 个运动组。快读有界反压时两队列峰值为 496/488→512/504，正终态和 9 拍 RESULT 反压通过。持有 AR 时取消在两版都清偿一笔 16 拍突发并给出真实负终态；同一次复位后的下一笔通过。所有成功帧的 RAW14/motion/marker 文件逐字节相同。 [命令与复现](../../refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_reader_round2_20261109/README.md) · [基线结果](hdr_reader_bb/run01/baseline/results.log) · [候选结果](hdr_reader_bb/run01/candidate/results.log)

若保留短旁路诊断，容量首拒可直接使用 `diag_begin_reject & {2{remember_capacity_drop}}`，一组只计一次，CHECK 与 REPLY 间的释放保留原判定拍语义。两眼计数和真实 job TAKE→bank RELEASE 时长可复用 DJ 现有位置，后续同窗对账时结合已知 job、总拒收、过期和坏 FINISH。若容量首拒约等于作业缺口，说明在该窗发生真实双槽饱和；若占槽时间逼近共享服务预算，再区分 reader/FENCE 与处理/writer 尾部。最近一笔时长只有退休后才刷新，读作状态采样。
