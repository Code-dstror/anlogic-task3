# 冷态HD/UHD选择与传感器公开合同

生产同一 bit 保持双目 HD40/45/48 及原 HD 功能。几何只在冷态选择，0 为旧 HD，1 为单目 3840×2160 SDR15，2 为同尺寸 SDR20。
FBC 为 `REQUEST_GEOMETRY`，FC0 为 `ACTIVE_GEOMETRY`，FC4 为只读能力字。新值 `0x107` 的位 15:8 为 ABI 1，位 7:0 为支持码位图。旧值 `0x103` 支持码 0 和 1。
请求写要求 4 字节 strobe、值 0…2。非零选择只在已暂存 MONO0 且 rate 请求为 legacy0 时合法。
HD 暂存显式速率时重写 geometry0 保留该速率。UHD 暂存时可以重写 rate0，保留所选 UHD 档。
原MODE写恢复默认divisor、rate0和geometry0，故按MODE（若需要）→DIV/PRODUCT→GEOMETRY→APPLY顺序。
旧BAR/API语义不变；APP/C2H开始、locked、busy或配置不空闲时不能改。
应用CONTROL相对偏移为0x018，STATUS为0x01C（以docs/pcie_protocol_v1.json为准）；
APP_ENABLE为CONTROL bit0。AXI-Lite应用窗口地址为0x80018，而不是0x80004。
当i_stereo_start_inhibit为1时APP置1必须SLVERR且不启动；允许时置1启动并锁定后续冷选择。
APPLY用同一保持bundle进入PIX/DFI，SYS25收到sensor profile之后才发布USER DONE/ACTIVE。
UHD 码 1/2 分别输出 SYS25 和 PIX sensor profile 5/6，两档的三个本域 `o_*_uhd` 均为 1。USER active rate 均为 legacy0，冷档 divisor 保留实际请求。
HDR/算法是否允许由CFG能力与验证规则决定，UHD不能被写成双目。DONE不是I2C已完成或图像已输出。
reset/cohort停钟、隔离和握手延续原cold controller公开合同；非法请求保留原ACTIVE。

新opaque源码stereo_cold_control、reset_release_sync、mono_pcie_app_regs_v2，include目录00_rtl/01_include/04_include。
合法参数FRAME_DIVISOR2、RAW_EXPORT_ENABLE1、UHD_ENABLE1；生产时钟USER/PIX8ns、DFI7.502ns、CFG40ns。
UHD_ENABLE0时新几何窗口返回SLVERR而原rate/legacy行为不变。
公共端口声明由维护者从模块头单独导出，不允许测试作者读取实现。

## 传感器和裁剪

sensor recipe/config 的生产参数为 MODE_4K0、UHD_ENABLE1，以 `i_sdr_profile` 5/6 选择全像素 RAW10。
每次START冻结profile和gain，203笔I2C顺序、复位与唤醒时间保留。

| 冷几何码 | 传感器 profile | HMAX | VMAX | SHR0 | 标称周期 |
| --- | --- | --- | --- | --- | --- |
| 1 | 5 | 1600 | 3000 | 2254 | 66.667 ms |
| 2 | 6 | 1600 | 2250 | 1504 | 50.000 ms |

HMAX 字段 3028/3029、VMAX 3024/3025/3026、SHR0 3050/3051/3052 均为小端。
HADD/VADD/ADDMODE（3020/3021/3022）为 0，DIG_CLP_VSTART 30D9 为 6，VNUM 30DA 为 2，
SYS_MODE 3033 为 9，ADBIT 3031 和 MDBIT 3032 均为 0，LANEMODE 4001 为 3，运行增益按 START 输入写 3090。
两档共用 24 MHz 级 MCLK、720 Mb/s ×4 lane、22.222 µs 行周期和 746 行积分，标称积分约 16.58 ms。
Sony 全像素 RAW10 时序范围及实板核对项见 [传感器规格](../fpga_src/rtl/imx415_sensor_config_spec.md#uhd-sdr-timing)。
其他HD profile0/4/1/2/3仍分别60/30/40/45/48，HDR优先时仍原139笔配方，不混入UHD时序。

## UHD20 独立短测交接

冷选验证使用 `stereo_cold_control`、`reset_release_sync`，需要实际 APP 门时加入 `mono_pcie_app_regs_v2`。I2C 验证使用 `imx415_sensor_config`、`imx415_sensor_recipe`、`imx415_mode_table`、`imx415_hdr2_recipe_rom`、`camera_i2c_write` 和 `src_fpga/ip/vendor/anlogic_camera/sensor/ui_imx415_reg.v`，含 `00_rtl/01_include/04_include` 路径。仅通过公开读写、时钟、复位和 I2C 应答观察行为。整条配置和产品链夹具见 [UHD JPEG 公开合同](../fpga_prj/verification_archive/verification_reference/uhd_integration_public/CONTRACT.md)。

冷写在 USER 上升沿采样，响应 `00` 为接受，`10` 为 SLVERR。读请求在 USER 上升沿采样并注册响应和 `read_response_valid`。任一 USER/PIX/DFI reset 断言时共同复位，各本域同步退出。I2C START 在 SYS25 上升沿由 `i_start && o_start_ready && i_clock_locked` 接受。SDA 使用上拉，写事务依次发送 `0x34`、寄存器地址高字节、低字节和数据，各字节 MSB 先行并由从机在第九个 SCL 脉冲应答。I2C `o_error` 为故障期间保持，成功 `o_config_written` 和 SDR `o_stable` 保持到复位或适用故障。

- 从 reset 后默认 MONO/HD 冷启，写 geometry2 并 APPLY。错开 PIX/DFI quiet 和 SYS25 边沿，未共同接收时 USER ACTIVE 留在 HD 且 APP 受阻。共同接收后核对 ACTIVE2、rate0、三个 UHD 电平及 PIX/SYS25 profile6。锁定后尝试改档，ACTIVE 保持 2。
- 独立冷会话覆盖 geometry1/profile5，再试错值 3、缺 strobe 或双目下 geometry2，均返回 SLVERR。回到 HD 双目显式 40，并以合法 APPLY 到达 PIX/SYS25 profile1。检查重写 geometry0 保留已暂存 HD40，以及 UHD20 暂存后重写 rate0 保留 geometry2。
- 用真实 I2C writer 的 SDA ACK 验证 profile6 的首个合法 START 到第 203 笔 ACK 和 held `o_config_written`、`o_stable`。START 后改变 profile/gain 输入，冻结选择仍有效。profile5 使用旧字节值。注入 NACK 后重新 START，核对下一次完整成功及对应的值。SDR 两笔末写依次为 3000=00、3002=00，中间保持配置的 `SDR_WAKE_CYCLES`。
- I2C 定向短测可用 SYS25 周期 40 ns、I2C_HALF_PERIOD=4、SDR_RESET_HOLD_CYCLES=6、SDR_RELEASE_WAIT_CYCLES=8、SDR_WAKE_CYCLES=12，MODE_4K=0、RUNTIME_GAIN_ENABLE=1、UHD_ENABLE=1。HDR 参数若不用则取默认合法值。每例设置独立仿真与墙钟 watchdog。

crop新增UHD_WIDTH/HEIGHT（0表示禁用）、UHD_FIRST_ROW/GROUP及i_uhd。
在真实RAW SOF握手冻结选择；之后保持原valid/ready、SOURCE序号、SOF/EOL和ABORT-token合同。
生产HD1920x1080、首行16/首组1；UHD3840x2160、首行16/首组3。
数字几何输入UHD采用3864x2192（966组/行），选择行16..2175、组3..962；
居中范围与Linux IMX415公开pixel-array3864x2192一致，但仍需板级核对包行数/光学边界/Bayer。
参考 https://raw.githubusercontent.com/torvalds/linux/master/drivers/media/i2c/imx415.c 的pixel-array与寄存器定义；
本项目现有MODE_4K表是寄存器配方依据。不要再次用2192总行却从36起取2160行。

短测可选HD16x3/FIRST_ROW1/GROUP0、UHD20x5/FIRST_ROW2/GROUP1，输入尺寸明确容纳两种窗口。
更大尺寸的边界另做一条或数条3840宽行及负终态，不要求多帧满幅长跑。
ABORT必须是valid/ready token，不能替换未接受的旧RAW offer；已呈现行尾先排空再报告abort。

上句指输入i_raw_abort。输出o_abort是独立单周期通知，不带o_valid，也不等待i_ready；
必须在每个时钟采样沿单独计数，不能把它当成RAW数据输出队列中的一拍。
若此前已有受阻的RAW/EOL输出，其真实握手完成后才发该通知。无valid的输出数据/identity不因o_abort而获得有效语义。
