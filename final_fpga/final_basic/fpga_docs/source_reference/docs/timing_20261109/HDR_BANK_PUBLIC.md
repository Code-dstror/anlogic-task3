# 双眼 HDR 槽公开合同

候选验证状态为 PENDING，等待同载体时序结果和采纳决定。

黑盒短门使用 `hdr_eye_shared #(.WIDTH(16),.HEIGHT(4))` 和真实目录 RAM。每眼有两个 bank，每 bank 有 LONG 和 SHORT 两个成员。上升沿处理握手。复位 `rst_n` 低有效。固定 `stop=0`、`transport_fault=0`，除非需要验证显式中止。

| 输入 | 宽度 | 作用 |
|---|---:|---|
| `clk`, `rst_n`, `stop`, `transport_fault` | 各 1 | 本地 DFI 时钟、异步低复位、停止、传输故障 |
| `now_ns` | 64 | 当前无符号纳秒时钟 |
| `config_valid`, `cfg_hdr` | 各 1 | 配置请求，HDR 固定 1 |
| `cfg_session`, `cfg_epoch`, `cfg_delta`, `cfg_wait`, `cfg_age` | 各 32 | 会话、epoch，最大曝光差、未完 bank 等待上限、描述符年龄上限 |
| `cfg_ratio` | 3 | 合法 HDR 固定 4 |
| `frames`, `begin_valid`, `member` | 768、2、2 | 眼 0 在低 384 位。相应眼 member=0 LONG、1 SHORT |
| `finish_valid`, `finish_ok` | 各 4 | 位 `2*eye+member`，实际成员写成功或失败终态 |
| `pair_take`, `release_valid`, `release_bank`, `release_id` | 2、2、1、64 | 接管 pair，按眼释放对应 bank/完整 ID。一次只发一个释放 |
| `read_quiet`, `ticket_released`, `write_quiet` | 1、1、2 | 释放资格。测试模型在读完目录后可置 1 |
| `ext_req`, `ext_slot`, `ext_consume` | 各 2 | 每眼目录读请求，单共享 slot，分别接收目录响应 |

| 输出 | 宽度 | 作用 |
|---|---:|---|
| `config_ready`, `config_error` | 各 1 | 配置 READY 和错误脉冲 |
| `begin_ready`, `accepted` | 各 2 | 每眼 BEGIN 的 READY 与允许结果，在 VALID&&READY 同沿采样 |
| `capture_slots`, `camera0_generation`, `camera0_lease` | 4、32、64 | 受理 BEGIN 的槽、代号、lease。每眼槽占两位，眼 0 在低位 |
| `finish_ready`, `pair_valid`, `pair_bank`, `pair_ids`, `release_ready` | 4、2、2、128、2 | 成员终态 READY、每眼 pair 资格、bank、每眼 64 位 ID（眼 0 低位）、释放 READY |
| `ext_ready`, `ext_valid`, `ext_last`, `ext_data`, `ext_word` | 2、2、2、64、8 | 目录请求 READY、每眼目录数据 VALID 和 LAST、每眼 32 位字、每眼 4 位索引 |
| `empty`, `fault`, `diag_begin_reject`, `diag_pair_expire`, `diag_bad_finish`, `diag_bank_states` | 2、1、2、2、4、8 | 眼级空、故障，以及只读事件和状态 |

复位后等两眼 `empty`。配置在 `config_valid && config_ready` 接受。推荐 `cfg_session=11, cfg_epoch=1, cfg_delta=32, cfg_wait=32, cfg_age=32`。有生效配置之后才发送 BEGIN。BEGIN 请求从首次 VALID 到 VALID&&READY 持有该眼的描述符和 `member`。受理后用该成员的 FINISH VALID&&READY 给出真正写完结果。拒绝的 BEGIN 无 FINISH。连续重复输入请在两笔之间区分握手，已握手的 VALID 在下一上升沿前撤销或更换为新事务。

## 描述符和配对

384 位描述符按下表打包。未列字段置 0。为每眼每角色用递进的序号，保持时间戳非降。两成员属同一 group，SHORT 时间戳至少等于 LONG，差值不超过 `cfg_delta`。成功 BEGIN 之后的 FINISH 必须用相同眼和角色。两成员均被准入且 FINISH OK 才能发布 pair。

| 描述符位 | 值 |
|---|---|
| `[0]`, `[3]`, `[4]` | 1、1、眼索引 |
| `[2:1]` | LONG=1，SHORT=2 |
| `[76:45]`, `[108:77]`, `[140:109]` | session、sequence、epoch |
| `[204:141]` | 无符号纳秒 timestamp |
| `[220:205]`, `[236:221]`, `[238:237]` | 16、4、RAW10=1 |
| `[270:239]`, `[302:271]`, `[334:303]`, `[366:335]` | `32'h56a3d02f`、LONG 3200 / SHORT 200、256、非零 group ID |

`pair_valid && pair_take` 锁住该眼的 bank 及完整 ID。目录读取用 `ext_req[eye] && ext_ready[eye]`，`ext_slot={bank,member}`；每个成员是索引 0 到 15 的 16 个字，`ext_last` 仅索引 15 有效。每眼有效的数据、索引和 LAST 在 `ext_consume[eye]` 为低时保持。读取时检查两成员的会话、epoch、序号、时间戳、曝光、group、完整 lease 和几何。

| 目录字索引 | 内容 |
|---|---|
| 0 | `[6]=bank`，`[5]=member`，`[4]=eye`，`[3]=1`，`[2:1]=type`，`[0]=1`，其余 0 |
| 1、2、3、4 | generation、session、sequence、epoch |
| 5、6、7 | timestamp 低字、高字、`{height[15:0],width[15:0]}` |
| 8、9、10、11 | integration、gain、sensor recipe、group ID |
| 12、13、14、15 | lease 低字、高字、1、0 |

正常每眼 slot 的低位是角色，高位是 bank。可将成功 BEGIN 的 generation/lease 与目录字段对账，LONG/SHORT lease 相异。目录处理结束且释放资格为真后，驱动 `release_valid[eye]`、捕获的完整 `release_id` 和 `release_bank` 到 READY 握手，随后该 bank 可重新分配。建议检查两个目录读取和释放到 `empty[eye]`，其中一次 READ 响应加有限反压。

## 年龄边界

描述符准入年龄使用检查当拍的 `now_ns`，以无符号 64 位绝对时间解释，区间 `(now_ns-cfg_age, now_ns]` 的下界排除，上界包含。绝对 0 附近把下界按数学负数处理，不能把 64 位最大值一侧的时间戳当作当前描述符。测试应在整个单笔 BEGIN 提供固定 `now_ns` 以便用公开输入独立判断。

已经分配的未完成 bank 使用分配时刻作为等待起点，与 descriptor timestamp 独立。当前一成员 FINISH 已排空且同眼目录引擎空闲时，等待 age 为 `(now_ns - arrival) mod 2^64`，严格小于 `cfg_wait` 才仍在等待窗口内。恰好到 `cfg_wait` 已到期。该过程在 `now_ns` 跳变后按当前输入判断，允许 64 位时钟回卷。可通过 `diag_pair_expire[eye]` 与 `empty[eye]` 观察；终止测试前应看到应过期的 bank 清空，期间无 pair。

最小短门可先在 `now_ns=2^32+16, age=32` 检查 `2^32-16` 下界和 `2^32+17` 未来时间均拒绝，随后用 `2^32-15` LONG 和 `2^32+16` SHORT 走完首笔真实 BEGIN/FINISH/pair/目录/释放。再用新 epoch 或复位使序号历史独立，在 `now_ns=16` 核对 `64'hffff_ffff_ffff_ffff` 拒绝且同高字的 `stamp=8` 可受理。最后在 `now_ns=2^64-16` 成功分配一半并 FINISH，先将时钟跳到 15（等待 31），再到 16（等待 32）。检查 bank 仅在后一边界到期。各场景保持健康传输和合法身份，防止其他原因遮盖年龄边界。

## 不透明编译清单

生产文件仅供编译和哈希。以下相对 `refactor/camera_raw_r2/src_fpga`。

```text
rtl/hdr_eye_shared.v
rtl/hdr_pair_directory.v
rtl/td_sdp_ram40.v
ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v
```

Include `rtl/include/04_include`。使用 `D:/App/modelsim/win64`，显式 TD 根 `D:/App/TD_Release_2026.2.210.850`，在 `sim_release` 下编译官方 `common/al_phy_glbl.v`、`ph1/ph1_logic_eram.v`、`ph1/ph1_phy_eram.v`、`ph1/ph1_phy_gsr.v`。可将 `ph1_phy_gsr.v` 随 DUT 编入 work 并在测试顶层实例化 `PH1_PHY_GSR PH1_PHY_GSR();`，模拟顶层命令加入 `-L ph1` 和 `ph1.glbl`。使用单独 run 和仿真库，设置墙钟总上限 55 秒及仿真 watchdog 100 µs，保留精确命令、日志、测试台和编译输入 SHA256。短门范围是实际 HDR owner 与目录 RAM 控制链。
