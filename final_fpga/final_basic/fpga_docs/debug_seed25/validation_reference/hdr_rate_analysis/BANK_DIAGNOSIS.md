# seed56 双目 HDR 的 bank、派发与共享服务预算

在 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213` seed56 的 540.000455 秒 HDR 窗，两眼各输入 16,365 组，DFI 接作业 16,365/10,910，慢眼少 5,455 组，累计负 BEGIN 恰为 10,910。两眼 `pair_expire`、`bad_finish` 增量均为零。六个 OB 下游事件的总量均为 27,275，慢眼在不同 epoch 可交换，约 25/25 的总量仍约 50.5/s。同一会话 SDR 已观察到 60 次/秒退休。这些观测定位了缺口出现的位置，并将后续分析的焦点放在 HDR 成组和共享服务时间。 现场复算（原仓库参考）

## 两眼准入、派发与归还

| 阶段 | 生产 RTL 合同与审阅结果 |
|---|---|
| 源入队与写成功 | PIX `capture_admit` 是每个曝光的真实 SOF 准入。RAW 写端经跨域 FIFO 请求 BEGIN。正答复给出该角色的槽位，后续 FINISH OK 依赖真实数据、匹配 SOURCE、正确几何及所需 AXI B。拒绝的成员继续排空自己的源事务。每眼 LONG/SHORT 写请求和两眼之间的 AXI 写请求均在双有效时轮转，已接受事务持有到 B。 |
| bank 容量 | 每眼两个 pair bank，每 bank 容纳同眼同组 LONG/SHORT。`hdr_eye_shared` 检查角色、递进序号、单调时间戳、会话/epoch、组号、曝光配方、几何和年龄；同组 peer 还要过目录及时间差校验。合法新组需要一个 FREE。若决定沿已有同眼 RELEASE 握手，下一拍重判，否则两槽忙时负答复并记该组；该组另一成员迟到时即使出现空槽也得负答复。`diag_begin_reject` 统计全体正常运行期的负答复，现场数值与两次拒收一组吻合。 |
| READY 到真正作业 | 两角色均被接受且 FINISH OK，bank 才由 BUILD 进入 READY。同眼已有 OWNED 时新 READY 等待；没有 OWNED 时，较新的 READY 仍可能等另一个较老、尚有效的 BUILD，以保序。`full_raw_store` 单眼有合格 offer 就锁定该眼；两眼同有 offer 时，偏好上一笔实际 RELEASE 的另一眼。复位初次平局偏 CAM0，持续双 offer 时交替。由于等候 READY 和持有 offer 的相位，两眼同平均输入可以产生分配不等；交换慢眼的现场观测与该结构相容。 |
| 所有权与命令 | `raw_pair_job_service` 在调度器空闲、票据释放、HDR 复位完成、RAW 读和 PIX pool 安静时接受 pair，先锁 bank，再读取 LONG 的 16 字目录，随后产生 UART 所计 `o_job_valid && o_job_ready`。`raw_hdr_phase_scheduler4` 保持同一 pair、LONG 目录、两成员租约和身份，依次接受处理命令、HDR context、reader START。在此期间没有另一笔在途 HDR job。 |
| 真实终态与归还 | scheduler 要求已接受 reader RESULT、同一 job 的 member0 处理终态以及全链 quiet。`raw_job_ticket_context_cdc` 等匹配 PIX TERMINAL、准确 tag/session/sequence/epoch/camera 的 JPEG writer ACK、RAW 读/实际 JPEG 写 quiet，发送 RELEASE 并收到匹配 PIX RELEASE_ACK 后才呈现处理结果。`raw_pair_job_service` 继续等 owner RELEASE 握手，HDR bank 才真正 FREE。借用的目录/RAW 租约随这个握手归还。 |
| STOP/CFG | steady HDR 已启用目标槽本地退休。目标 OWNED bank 的两曝光写完后，另一槽可继续写。STOP/CFG、复位或故障走既有安静与隔离条件，真实读债、票据、JPEG 写及同眼目录仍各自受校验。 |

`full_raw_store.o_public_read_quiescent` 在此物理 profile 恒为高。正常 bank RELEASE 等待的是 `jpeg_frame_ring.o_write_quiescent`，涵盖 START、输入、FIFO、实际 B 和 ACK。已经 READY/SENDING 的 JPEG 槽及 USER DMA 退休有各自生命周期。PIX 接新产品依赖 session 级 `armed_pixel`、app enable、JPEG credit 和无故障，OB USER 的 `product_buffer_armed` 则是逐笔主机 DMA 缓冲。输出环的每眼可用槽和 DDR 读写仲裁仍可间接影响下一笔的 START 或处理时间。DFI 已预留的通用 credit 也不能确认未来指定眼的 START 就绪。83 个 idle/credit reserved 样本支持这些时刻有通用 credit，无法约束其他作业的逐次等待。 RAW owner（原仓库参考） · 派发与本地归还（原仓库参考） · job service（原仓库参考） · scheduler（原仓库参考） · 票据（原仓库参考） · JPEG 写静默（原仓库参考）

## 共享服务必须达到的速率

| 项目 | 速率或时间 |
|---|---:|
| 现场合法输入，单眼 / 双眼 | 30.30553 / 60.61106 组/s |
| 现场双眼平均 job 接纳间隔，含空档 | 19.798 ms |
| 完整接纳上述输入所需的平均间隔 | ≤16.498639 ms |
| 1080p 单像素 T96 无空拍下界 | 16.588800 ms/组，≤60.281636 组/s |
| 单像素 T96 对 30+30 整数目标的剩余预算 | 77.867 µs/组，约 0.467% |
| 双像素 T96 的纯计算下界 | 8.294400 ms/组，≤120.563272 组/s |

硬下界来自生产 `sys_pll_125m_25m` C0 和同一个 `real_hdr_camera_observe_axis` → `physical_camera_rgb_pipeline` → `shared_wide_isp` → `wide_color_pipeline` → `hdr_tone96_shared4`。两眼都借这个 ISP，HDR 每个 RAW4 对应的四个 RGB 像素至少占 T96 四个 PIX 周期，SDR 有四像素直通。1920×1080 因此要求每笔 2,073,600 个像素周期。仅 T96 已比现场输入预算多 90.161 µs/笔，即使 DDR、JPEG 和跨域零开销也缺 0.3294 组/s。单纯增 bank 可以吸收有限相位/抖动，持续流量受上述算力上限约束。 PLL 与共享 ISP 调用（原仓库参考） · 125 MHz IP（原仓库参考） · 共享色彩（原仓库参考） · T96（原仓库参考）

读端独立短测的同一 68×63 模型中，固定 AR→首 R 为 32 DFI 拍时，START→RESULT 为 3,515→2,421 拍，减少 31.1%，两版均 42 AR、670 R beat、1,071 组，逐组数据、运动和标志一致。该缩短发生在读端服务，不能直接乘到 TAKE→RELEASE 或整机 FPS。读、解码、Tone 和 JPEG 可重叠，跨域、分块和 DDR 争用会改变空拍。最终 T96 候选以两条算术 lane 同拍处理组内两个像素，共用组缓冲和控制，两拍拼成同一四像素输出，将 HDR 启动间隔从四拍/组降为两拍/组。冻结系数和算术保留每像素定点结果，成本由同载体小综合确认。两个改进均继续以真实 RELEASE 作为归还点。 reader A/B（原仓库参考）

## 条件模型与短门

用离散事件模型检查容量截止。两眼每 32,997 µs 来一组，组首为 LONG，SHORT BEGIN 晚 1,000 µs。LONG 和 SHORT 写成功分别在组首后 29,000 和 30,000 µs 到达。每眼先占两槽，每组在同眼首个合法 BEGIN 占槽、两 FINISH 后可服务、实际 RELEASE 后回收。双 offer 按上次归还眼的反眼选，模型将同刻 RELEASE 放在 BEGIN 判定前。热身 30 组后，每眼取输入身份连续的 330 组，排空后按该身份范围计账。 可重跑模型（原仓库参考）

| CAM1 初始相位 | 串行服务 19,500 µs，job / 负 BEGIN | T96 理想下界向上取整 16,589 µs，job | 串行服务 15,900 µs，job / 负 BEGIN |
|---:|---|---|---|
| 100 µs | 330/220，0/220 | 330/313 | 330/330，0/0 |
| 4,000 µs | 275/275，110/110 | 330/322 | 330/330，0/0 |
| 32,897 µs | 220/330，220/0 | 314/330 | 330/330，0/0 |

在捕获相位固定、两眼周期相同、没有额外失速的模型中，周期记为 `P`，组首到 READY 为 `C`，每笔从开始服务到归还为 `S`。`2S <= P` 时，相邻的两组最多有一组等 `S`，故 `C + 2S <= 2P` 就足够让每眼新 BEGIN 赶在占用两槽之前获得可用槽。15.900 ms 的示例给两笔留 `P − 2S = 1.197 ms`，给较晚释放者留 `2P − C − 2S = 4.194 ms`。这是一项候选集成短门的条件预算，现有 reader A/B 只测读段。19.5 ms 的模型按固定周期推算共享忙碌约 98.5%，真实 1 Hz UART 不能由该数值换算，模型也未拟合 idle 采样比例、抖动、FIFO 延迟或真实 DDR 首拍。

运行命令为 `pwsh -NoProfile -File tmp/hdr_rate_seed56_20261110/bank_capacity_model.ps1`。模型通过组、成员和终态账本检查。真实 RAW store、owner 和 scheduler 可用独立作者的短时 BFM 来对照同一容量形状；只有包含真实读、PIX 和 writer 的短门才能测该夹具下的新服务时间。板级判断还需要在一个 DFI 时间基准下关联首次容量拒绝、两成员 FINISH、READY、TAKE、reader RESULT、writer ACK、票据归还、RELEASE 和输出信用。优先用旁路计数或短事件采样，避免让观测进入准入反馈。 独立短门公开合同（原仓库参考）

本次归因状态为离线模型 PASS，真实 owner/dispatch 短门、综合、P&R、物理时序及新板测均为 NOT_RUN。
