# DFI CONFIG 提交公开合同

验证对象为 `frame_job_config_cdc` 及两条实际 TD control FIFO。测试作者只依据本合同和公开端口建立预期值。生产源和模型只供编译及 SHA256 校验。编译问题由实现维护者定位。

## 参数与端口

生产紧凑配置为 `EXT_WIDTH=214, WIDTH=1920, HEIGHT=1080, EXT_STRIPS=4, DEHAZE_LUT_GUARD_ENABLE=0, EXT_COMBINATIONS=32'd0, EXT_SUPPORTED=8'h34, COMPACT_EMPTY_EXTENSION_ENABLE=0, COMPACT_STAGE2_EXTENSION_ENABLE=1, TRUSTED_INPUT=1`。该短测只驱动入口已经通过上游格式校验的 tuple。

| 方向和域 | 信号 | 宽度与含义 |
|---|---|---|
| 输入时钟、复位 | `i_pixel_clk`, `i_pixel_rst_n`, `i_dfi_clk`, `i_dfi_rst_n` | 各 1 位。两域独立时钟，任一复位低使本事务链复位 |
| PIX 输入 | `s_frontend_applied_data`, `s_frontend_applied_valid`, `s_frontend_applied_ok` | 374 位 tuple、1 位 VALID、1 位前端判定 |
| PIX 输出 | `s_frontend_applied_ready` | 1 位 READY |
| PIX 输出 | `m_whole_ack_data`, `m_whole_ack_valid`, `m_whole_ack_ok` | 374 位原请求、1 位 VALID、1 位最终判定 |
| PIX 输入 | `m_whole_ack_ready` | 1 位 READY |
| DFI 输入 | `i_pair_mode`, `i_mono_enable`, `i_max_delta_ns`, `i_max_wait_ns`, `i_max_age_ns` | 2、1、64、32、32 位。生产 SDR 固定为 0、1、1000000、50000000、100000000 |
| DFI 输出 | `o_job_config_valid`, `o_job_session`, `o_job_epoch`, `o_job_mode`, `o_job_mono_enable` | 1、32、32、2、1 位。HDR mode 为 2 且 mono 为 0 |
| DFI 输出 | `o_job_max_delta_ns`, `o_job_max_wait_ns`, `o_job_max_age_ns`, `o_job_config_snapshot` | 64、32、32、374 位。HDR 使用 tuple 的时间参数 |
| DFI 输入 | `i_job_config_ready`, `i_job_config_done`, `i_job_config_error`, `i_job_config_busy` | 各 1 位。请求握手与真实完成是不同的边沿 |
| DFI 输出 | `o_active_valid`, `o_active_session`, `o_active_epoch`, `o_active_config`, `o_active_hdr` | 1、32、32、374、1 位。最后一次成功提交的完整资格和身份 |
| DFI 输入 | `i_dehaze_lut_valid`, `i_dehaze_lut_generation`, `i_dehaze_update_busy` | 1、32、1 位。选定 profile 均绑 0 |
| DFI 输出 | `o_dehaze_lut_update_inhibit` | 1 位。选定 profile 为 0 |
| PIX 输出 | `o_source_reset_done`, `o_source_busy`, `o_source_fault`, `o_stale_ack_count` | 1、1、1、32 位。RESET_DONE、BUSY、FAULT 为电平，计数饱和 |
| DFI 输出 | `o_dfi_reset_done`, `o_dfi_busy`, `o_dfi_fault`, `o_stale_job_done_count` | 1、1、1、32 位。同上，计数在没有待完成 CONFIG 时收到 DONE 加一 |

输入在对应域上升沿采样。前端从 VALID 开始持有完整 tuple 和 OK 到 VALID&&READY。ACK 与 DFI 请求被反压时保持有效载荷。DFI 侧先握手接受 CONFIG，后续某个 DFI 沿由下游提供单拍 DONE，ERROR 与 BUSY 在该沿有意义。前端负回执应收到负 ACK，其间无 DFI CONFIG 请求。

成功提交沿为已接受请求的 DONE=1、ERROR=0、BUSY=0。该沿后 ACTIVE_VALID、SESSION、EPOCH、CONFIG 与 HDR 同步反映新 tuple，PIX 整体 ACK 可更迟。DONE 携带 ERROR=1 或 BUSY=1 时返回负 ACK，整组 ACTIVE 保留旧值。无待完成请求的迟到 DONE 不修改 ACTIVE。每次 ACK 都逐位回显原 374 位 tuple。复位立即清空 ACTIVE 资格与内容，放开后等各域 RESET_DONE，重新从 BOOT 起步。健康时反压必须有限。

## 可直接构造的合法测试数据

未列字段置零。`tuple[31:0]` 是请求 ID，`[63:32]` 是非零会话，`[65:64]` 为颜色模式 0，`[72:66]=75`，`[80:74]=1`，`[159:128]` 是 epoch。BOOT 用请求 ID=0、epoch=0 和全零扩展；后续用同一 session、非零请求 ID、epoch 为上一成功值加一。一次负 ACK 后可用同一待提交 epoch 和新请求 ID 再试。

令 `ext=tuple[373:160]`。旧 schema HDR 的 `ext[34]=1`，新版 schema HDR 的 `ext[213]=1, ext[1:0]=2`。新版 schema SDR 的 `ext[213]=1, ext[1:0]=0`，其余扩展位为零。两种 HDR 都用 ratio=4、qualification=15、delta=1000000 ns、wait=50000000 ns、age=100000000 ns。

| 值 | 旧 schema HDR 扩展位 | 新 schema HDR 扩展位 |
|---|---|---|
| Ratio | `[37:35]` | `[42:40]` |
| Qualification | `[79:76]` | `[84:81]` |
| Max delta | `[143:80]` | `[148:85]` |
| Max wait | `[175:144]` | `[180:149]` |
| Max age | `[207:176]` | `[212:181]` |

建议一个短序列覆盖 BOOT 成功到 PIX 整体 ACK、旧 schema HDR 请求在 DFI READY 前与 DONE 前均保留旧 SDR、提交后 HDR/epoch 同拍更新、新 schema SDR 先 DONE+ERROR、再 DONE+BUSY、最后正常成功，验证两次失败保留旧 HDR。随后新版 schema HDR 合法成功。对至少一次 DFI 请求及 PIX ACK 加有限反压。复位例可在 DFI 停钟时断言 PIX 复位，检查 ACTIVE 异步清零，复钟后新 session BOOT 成功。任一新 epoch 生效前，当前输出不得混用新旧配置。

## 不透明编译输入

下列仓库路径以 `refactor/camera_raw_r2/src_fpga` 为根。TD 根必须显式取 `D:/App/TD_Release_2026.2.210.850`，ModelSim bin `D:/App/modelsim/win64`，Python `python`。

编译 `work` 的 include 路径为 `rtl/include/00_rtl`、`rtl/include/03_mono_config_v2_20261015`、`rtl/include/04_include`、`ip/camera_control_fifo_40x512/RTL/include`。以下 Verilog 可用 `vlog -sv` 提交给编译器。

```text
rtl/frame_job_config_cdc.v
rtl/frame_config_extension_validate.v
rtl/reset_release_sync.v
rtl/control_message_fifo_ip.v
rtl/control_fifo_40x512.v
ip/camera_control_fifo_40x512/camera_control_fifo_40x512.v
ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v
ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v
```

`ph1` 库输入以 `TD_ROOT/sim_release` 为根。模拟顶层带 `-L ph1`、`ph1.glbl`，`ph1_phy_gsr.v` 也可随 DUT 编进 `work` 以配合测试顶层的 `PH1_PHY_GSR` 全局实例，实例名同模块名。

```text
common/al_phy_glbl.v
ph1/ph1_logic_eram.v
ph1/ph1_logic_fifo.v
ph1/ph1_logic_ramfifo.v
ph1/ph1_phy_eram.v
ph1/ph1_phy_fifoctrl.v
ph1/ph1_phy_gsr.v
```

每次用独立输出目录和库。建议模型墙钟总上限 55 秒、仿真 watchdog 100 µs。记录精确命令、参数、输入和测试台 SHA256、工具版本及 PASS/FAIL。应用级调度与票据、DDR、相机、布线和板级不在此短测范围内。
