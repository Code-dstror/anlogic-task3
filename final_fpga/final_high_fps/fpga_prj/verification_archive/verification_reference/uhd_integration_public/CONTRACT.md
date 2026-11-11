# UHD JPEG 集成短门公开合同

测试对象为 `uhd_integration_fixture`。实例使用默认参数。测试只读本文、生成目录的
`uhd_integration_fixture_ports.vh`、`compile.json` 和公开协议文档。所有 `.v`、
受保护 IP、厂商模型及 `projection.json` 只供不透明编译或计算哈希。只通过本顶层公开
端口激励、注入错误和对账。

## 生成与时钟

从仓库根目录运行以下命令，目录名须为本次唯一。

```powershell
& 'refactor/camera_fusion_r1/verification_reference/uhd_integration_public/project_fixture.ps1' -RunName 'integration_gate'
```

输出位于 `refactor/camera_fusion_r1/tmp/uhd_integration_projection/integration_gate`。
`compile.json` 的 `sources` 和 `include` 相对候选根，`td_models` 相对显式
`<TOOLS_ROOT>/TD_Release_2026.2.210.850`。ModelSim SE-64 2020.4 将 PH1 GSR 编入 work，
其余厂商模型编入 ph1。使用列出的定义与 include 路径，并把 `sibling_tops` 与测试顶层
并列展开。命令、工具版本、生成输入与测试哈希、原始日志及终态写入新的运行目录。
整个门使用不超过 200,000 个 PIX 上升沿的 watchdog 和 180 秒墙钟 watchdog。

生产和投影`.v`使用普通Verilog编译，不强制`-sv`；其中有合法Verilog标识符与SV保留字冲突。
测试台`.sv`另行`-sv`。官方fdct MAC的wrapper及internal两个`.v`单独`vlog -mfcu`且无`-sv`，
同一组defines/include不变；强制SV会使该版本宏指令初始化不同。当前冻结MAC无define.v文件，
不要照搬更早IP版本的额外文件名。保留编译分组和日志，不修改生产IP来适应仿真器。

JPEG ROM采用已冻结仿真wrapper，只把INIT_FILE重定位，数值/端口/时序参数与原件一致。
在新建的vsim工作目录下不透明执行 `prepare_rom.ps1 -SimDirectory <该目录绝对路径>`，
生成 `rom_init/*.mif.dath` 和原始MIF/输出SHA清单。不能只传未被wrapper使用的ROM_INIT_ROOT。

`sys_clk`、`i_pixel_clk`、`i_mem_clk`、`i_host_clk` 分别使用 40 ns、8 ns、
7.502 ns、8 ns 周期，偏移独立。以低 `pcie_mperst` 及空闲事务开始，随后按模型
提供 `i_clock_ready`、`i_mem_ready`、`i_host_link_up`、`i_host_bme`。
对应的 PIX/DFI/USER 接口在 `o_pixel_reset_n/o_dfi_reset_n/o_user_reset_n` 释放后使用。
内存接口另以 `o_mem_reset_n` 为约束。旧板级数据脚空闲，`uart_rx=1`；
`board_ref_clk_100m` 可接空闲板参考时钟。测试不驱动板级双向输出。

## 范围与几何

该载体保留原顶层配置、时钟域所有权、RAW 捕获和共享回放、真实 SOURCE、JPEG、
DDR 仲裁和 ring、记录元数据、C2H native buffer ARM 和匹配 fence/ACK 逻辑。板 PLL、
传感器/I2C/CSI 和 crop、Bayer/ISP 核数值、DDR PHY 与 PCIe hard port 是公开模型边界。
CFG 能力页保持生产 UHD 标识 3 和 MAX 3840×2160。本门的数据面编译成 240×16 和
480×32，且只测选中 UHD 的高档。480×32 是验证栅格。原始 CAP 数值与满幅记录资格
分别由正式尺寸 CFG 和 RAW 门证明。

高档每行 120 个 RAW4、全帧 3,840 个 RAW4。四个 10 位样本低位在先紧密打包。
实际输出 JPEG 为 480×32 基线 4:2:2，30×4 MCU，共 120 MCU。短门不用 240×16
图像替代原有 1080p 算法回归。

## 配置到 ARM

- USER 侧由真实 CQ/CC 读写应用 BAR。初始 APP_ENABLE=0，等 BOOT 及
  SESSION_REARM_READY。按公开冷协议暂存 MONO、JPEG、旧 rate 0 和 geometry 1，
  APPLY 后读回 FC0=1、FC4=0x107。模型在看到 SYS25 的 `o_sensor_profile=5` 后，
  用 `i_sensor_profile=5`、`i_sensor_mode_running=1`、
  `i_sensor_config_done=1` 表达已就绪的数字传感器。启动时 profile 0 同理。
  `i_sensor_config_error=0`。
- 提交合法 schema2 SDR CFG PREPARE_EXT 和 COMMIT，base COLOR、处理使能 `0x0d`
  （扩展word0=`0x3402`，其余word为0），例如质量73、最低质量1、其余策略零。
  这启用共享灰度、高斯、HE，像素数学见 [公开算法合同](../uhd_preprocess_public/CONTRACT.md)。
  请求 session 从当前 CFG_SESSION 读出，请求 sequence 新鲜非零。真实
  `o_cfg_ack_fire` 在 PIX 边沿报告远端整包 ACK，检查 OK、session 和新 epoch。
  APP 仍关闭时提供匹配的实际裁剪 FS/SOF 和清洁图像终态，见
  `o_cold_config_sof` 后读 USER APPLIED、活动质量、epoch 和首帧 sequence。
  这个冷态观察帧可使用完整 480×32 数字输入，期望无产品采集、JPEG START 或 DMA 记录。
- 在仍冷态时用真实 record SELECT 选 v4，读回版本 4 和头长 2112。
  用 native shadow 和 SUBMIT 武装已知主机内存，观察 `o_buffer_armed`。
  再写应用 CONTROL 的 APP_ENABLE，观察真实 `o_session_armed`。
  看到 PIX 的 `o_capture_enabled` 后，开始首个合法产品帧。
  [几何选择](../../docs/GEOMETRY_CONTROL_PUBLIC.md) · [CFG](../../docs/UHD_CFG_PUBLIC.md)
  · [寄存器定义](../../docs/pcie_protocol_v1.json)

## 公开模型边界

- `i_event_*` 和 `i_crop_*` 为独立 valid/ready 接口，均在 PIX 上升沿采样。
  停顿时保持所有字段。事件 kind 0/1/2 是 FS/FE/ABORT。合法 FS 和 FE 使用同一
  sequence，ok=1、error=0、identity_valid=1。FS 先转移，再送 RAW4 首组 SOF；
  每行末组 EOL，所有 RAW4 sequence 与 FS 相同。末组完成后送真实 FE。
  本门保持 `i_crop_abort=0`，失败注入在 RAW 回读 AXI。
- 外部 ISP 模型在 `o_isp_raw_valid&&i_isp_raw_ready` 转移时取四个 14 位 lane。
  每个已接收 RAW4 对应一个 RGB4，SOF/EOL 随数据推进。可用独立、确定且非灰度的
  像素函数。RGB lane 为 `{R[7:0],G[7:0],B[7:0]}`，最早在低 24 位。
  `i_isp_rgb_valid&&o_isp_rgb_ready` 才交付，停顿保持数据，真实
  `o_isp_reset_n=0` 清除模型积压并压低 `i_isp_raw_ready/i_isp_rgb_valid`。
  仅在没有模型持有工作时给 `i_isp_idle=1`。
  `o_isp_width/height` 反映实际回放档位。模型只产生 RGB，SOURCE 和终态仍由
  真实回放、适配器和前景产生。
- AXI 模型在 DFI 分别按 AW、W、B、AR、R 握手推进。只把被 WSTRB 选中的已接受
  字节写入内存。按实际承诺保持 BID/RID、响应和末拍。RAW CAM0 起址
  0x02000000/0x03000000。JPEG 使用生产的 JPEG 槽地址。正向 B 由各已接受 AW
  的真实 WLAST 触发，延迟有限。AR 返回实际写入的内存。
- RAW 失败注入用一个已经承诺的 RAW AR 事务的 RRESP=SLVERR。保持 RID、RVALID、
  RLAST 与其他拍形状合法，后续已承诺 R 和 W/B 全部排空。JPEG 写路径仍返回真实
  AXI 响应，记录是否失败由 DUT 判定。

JPEG槽各16MiB，六个起址为0x0000000、0xA000000、0xB000000、0xC000000、0xD000000、0xE000000，
CAM0用前三槽。`i_mem_clk`就是该投影的实际DFI时钟。
本SDR门的`o_replay_source_tag`与`o_ticket_job`为同一个完整64位job identity，不能从它的子位推算capture序号。
`o_jpeg_source_done/failed`为PIX单拍，`o_ticket_result`为DFI单拍，伴随error/job同拍有效。
`o_record_quiet`为无活动写/读/退休债务的电平，允许已有READY槽，不能代替SAFE和ACK的退休检查。
现行AJPG `payload_crc32`固定0，未启用该项CRC协议策略；可独立计算收到payload的hash，但不据此要求线上字段非零。

## CQ/CC、native buffer 和 fence

USER 上升沿按 valid&&ready 采样 CQ/CC。读写都是对齐单 DWORD，BAR0。
CQ header 为 128 位，地址在 `[31:0]`，`[74:64]=1`，`[78:75]` 为读 0 或写 1，
`[95:80]` 是 requester，`[103:96]` 是 tag，`[114:104]=0`。
header KEEP 为 `4'hf`，CQ USER 首字节使能 `[3:0]=4'hf`，其余置零。
读 header 的 LAST 为 1。写 header 的 LAST 为 0，后继 payload 的低 DWORD 写入值，
KEEP=1、LAST=1。写是 posted。用合法读回检查时序。应用寄存器地址为
0x80000 加 12 位应用偏移，native 命令页在低 0x000–0xFFF。
成功 CC 读回的 `[45:43]=0`、`[42:32]=1`、tag 在 `[71:64]`、DWORD 在 `[127:96]`。

- native buffer shadow 写 0x020/024 为对齐地址，0x028 为字节容量，0x030/034/038/03C
  为 128 位 buffer identity 从低到高，0x040/044 为独立对齐的 fence 地址，0x048
  为 cookie。identity 的高 64 位为非零且会话内恒定，`[63:32]` 为递增非零 generation。
  运输复位后STOPPED=1；在IDLE且无FAULT时先写0x008=8 RESUME，再提交。
  0x008 写 1 是 SUBMIT。读 0x00C 可见 WAIT/ARMED bit 1、SAFE_RESULT bit 2、
  FAULT bit 3、STOPPED bit4、BOUND bit 5。此身份和 JPEG record identity 各自对账。
- `o_tlp_header_valid` 或 `o_tlp_data_valid` 在 `!i_tlp_halt` 的 USER 边沿传输。
  写头格式 2/3，首 data 与 header 同拍，后续按 `o_tlp_end`，每 data 低字节先到。
  `o_tlp_byte_length` 是 DWORD 对齐长度，byte enable 的低/高 nibble 为首/末 DWORD。
  模型根据真实包头、长度及使能写主机内存，有限停顿时保留 offer。
- fence 请求格式 0/1，无 data，长度 4，tag=0x1A。接收该请求后以同一 USER 域送
  RC，KEEP=F、LAST=1、USER bit42=1、bit32=0。RC DATA 从零开始赋值，
  `[6:0]` 为 fence 地址低位，`[28:16]=4`、bit30=1、`[42:32]=1`、
  `[71:64]=8'h1A`、`[127:96]` 为模型 fence 内存中预先写入的 cookie。
  在真实 RC 后读 SAFE_RESULT、result code 0x080、已发送长度 0x084、记录长度 0x088
  和回显身份 0x090–09C。0x0A0–0AC 返回绑定的产品身份。保持原匹配 shadow
  identity，再写 0x008=16 ACK。
  [主机 native ABI](../../rk_sdk/linux/dma_c2h_candidate/c2h_abi.py)

绑定产品身份从0x0A0低字到0x0AC高字为
`{16'h4a50, session[31:0], generation[31:0], slot[15:0], frame_id[31:0]}`。
与实际AJPG头的对应字段核对，不与buffer identity或64位job id混用。

## 最小成功与恢复判据

1. 从真实 CFG ACK、APPLIED、DMA buffer ARM 和 SESSION_ARMED 到合法首帧。
   查实际 RAW capture、正 SOURCE、JPEG START 及匹配身份、JPEG RESULT、所有写 B。
   对 JPEG B 使用有限延迟，尤其检查最后写响应到达前没有成功 writer 回执或记录
   offer。最终 B 后等真实 writer ACK、ticket result 与 RAW 槽释放。
2. 独立验证实际 C2H 主机内存字节。头是 AJPG v4、2112 字节，序号、session、epoch、
   CAM0 和宽高与本帧一致，processing mode为原协议的schema2标记 `0x8d`，
   neutral context/stats 资格清零。独立解析 JPEG SOF0、
   4:2:2 MCU 数、完整 EOI 和有效长度，按模型像素独立检查解码。
   检查真实 fence 和 ACK 之前 JPEG 槽保持占用。匹配 ACK 后需见实际
   `o_record_retire_fire` 及 `o_ring_retire_response_valid/code=0`。
   [v4 格式](../../rk_sdk/linux/task3_pipeline/record_v4.py)
3. 同一会话第二帧正常捕获。待本帧已出现真正 JPEG START，再对一个在途 RAW
   回读注入上述 SLVERR。可以在前几行成功读之后有限推迟下一已承诺 R，避免
   过早触发。必须看到匹配的失败 SOURCE、负 JPEG 终态、实际失败写回执和 ticket/RAW
   退休。已承诺的 AR/R 和 AW/W/B 均完成。零成功 READY、零成功 DMA 记录。
   已进入在途写入的失败 JPEG 槽由 ring 的失败路径释放写所有权。
4. 同会话、同档位的新合法帧达到与首帧相同的真实退休，证明前一帧没有留下 pending
   或阻塞所有权。负帧可保留尚未绑定的 native buffer 供这条恢复帧使用。

`o_cfg_ack_*`、`o_cold_config_sof`、capture、replay SOURCE、JPEG SOURCE 和
JPEG RESULT 观察端口按 PIX 采样。START、writer ACK、ticket、RAW retire、record
offer 和 retire response 按 DFI 采样。ARM 按各自时钟观察其稳定电平。
观察端口只回显实际握手和终态。此门通过后仍需分别记录满幅 JPEG、持续帧率、
整机 MIPI/DDR/PCIe 物理链路、P&R 与上板状态。
