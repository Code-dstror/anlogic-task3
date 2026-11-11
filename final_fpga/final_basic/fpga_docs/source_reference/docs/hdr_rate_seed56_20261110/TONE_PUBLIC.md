# T96 HDR 双像素吞吐独立短测合同

测试顶层实例化 `hdr_tone96_shared4`。两版用 [端口声明](TONE_PORTS.vh) 及相同的模型、时钟与刺激，分别验证独立期望。基线取 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213`，候选路径为 `experiments/hdr_tone2_20261110/candidate/hdr_tone96_shared4.v`。基线固定副本和候选都可编译、哈希。测试作者只读本公开合同及端口，测试根据下面的整数式计算期望。

## 流行为

- 125 MHz 单 PIX 时钟。上升沿 `s_valid && s_ready` 接收一个组，上升沿 `m_valid && m_ready` 退休一个组。输入持有所有字段直到接受。输出 `m_valid` 且未 READY 时，保持有效、数据、SOF、EOL 和 clipped。
- 每组含四个完整像素。像素 `j` 是 `s_data[42*j+:42]`，各像素按高到低 `{R,G,B}` 每分量 14 位。输出像素 `j` 是 `m_data[30*j+:30]`，仍按高到低 `{R,G,B}` 每分量 10 位。SOF、EOL、clipped 是组级不透明标记，输出一一保序。`s_hdr` 一帧内固定。输出 VALID 为低时载荷未定义。
- 连续输入且下游一直 READY 时，HDR 基线相邻组接收间隔为四拍，候选为两拍，首组接收到首组退休的基线/候选目标分别为 14/12 拍。SDR 两版均每拍可接一组，第一组下一拍退休。等待的 SDR 必须在早先 HDR 组全部到达输出边界后才被接受。上一笔 HDR 输出恰好退休的同一拍可接受首组 SDR。后一笔 HDR 同样不能越过 SDR。
- `rst_n=0` 或 `clear=1` 时立即关闭 READY 和 VALID，跨至少一个上升沿清空所有已接的组和待退输出。复位/clear 释放后使用独立身份的新帧。合法反压有限，不要求上游保持当前数据跨过协调 clear。相同帧内的短供给间隙和最后一组长反压均合法。

## 冻结整数算术

设 `rh(n,d)=floor((2*n+d)/(2*d))`，其中 `n` 为非负整数、`d>0`。分段 `[0,1024)`、`[1024,2048)`、`[2048,4096)`、`[4096,8192)`、`[8192,16384)` 的 knot 间隔分别为 32、64、128、256、512，并包含终 knot 16384。固定 `W=16368`、`K=1024`。

```text
G(q) = rh(65536 * 1023 * (W+K), W * (q+K))
T(q) = min(1023, rh(q * 1023 * (W+K), W * (q+K)))

HDR: M = max(R,G,B), a <= M < b with consecutive knots a,b
gain       = G(a) - rh((G(a)-G(b)) * (M-a), b-a)
mapped_max = T(a) + rh((T(b)-T(a)) * (M-a), b-a)
component(C) = mapped_max                       if C == M
component(C) = min(mapped_max, rh(C*gain,65536)) otherwise

SDR: component(C) = min(C,1023)
```

覆盖合法首帧和连续 HDR 接收节奏，所有分段边缘、0 和 16383、并列最大分量及四 lane 的不同结果。用有限输出反压覆盖 EOL 和模式交接，清除在途组和被反压的输出后验证新的首帧，覆盖 SDR 直通及 1023 饱和。用固定种子、带 wall-clock 和仿真 watchdog 的最小短测。完整 1080p service、综合、物理和板级各自另计。 [原冻结数学规格](../../../../guidance/Anlogic_R8_FPGA/reference/tone_reference.py)

## 不透明编译依赖

路径以 `refactor/camera_raw_r2/` 为根。用本机 ModelSim `D:/App/modelsim/win64` 和 TD2026.2 `D:/App/TD_Release_2026.2.210.850`。生产及厂商源仅供编译和输入 SHA256。ROM MIF 仅作仿真初始化，不作为数值 oracle。

```text
src_fpga/rtl/hdr_tone96_shared4.v        # 固定 Git baseline 的生产路径
experiments/hdr_tone2_20261110/baseline/hdr_tone96_shared4.v
experiments/hdr_tone2_20261110/candidate/hdr_tone96_shared4.v
src_fpga/simulation/assets/tone96_rom0_sim.v
src_fpga/simulation/assets/tone96_rom1_sim.v
src_fpga/ip/coefficients/tone96_0.mif
src_fpga/ip/coefficients/tone96_1.mif
src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/RTL/mult_18s18s_p1_multiplier.v
src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/RTL/mult_18s18s_p1_multiplier_top.v
src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/mult_18s18s_p1.v
```

使用 `+define+PH1`。在独立 run 将两个 MIF 的全部 512 地址转换为每地址一行十六进制；官方仿真封装按运行工作目录读取 `./rom_init/tone96_0.mif.dath`、`./rom_init/tone96_1.mif.dath`，须放到该相对目录。首轮若仅放在工作目录根部会导致 ROM 初始化失败，不能当成 DUT 算术结果。编译同版本的模型至 `ph1`，`ph1_phy_gsr.v` 编译至 `work`，启动 `-L ph1 work.PH1_PHY_GSR ph1.glbl` 与测试顶层。保留原始 MIF、DATH、两版 DUT、模型、测试台和编译器记录。

```text
sim_release/common/al_phy_glbl.v
sim_release/ph1/ph1_logic_eram.v
sim_release/ph1/ph1_phy_eram.v
sim_release/ph1/ph1_logic_mult.v
sim_release/ph1/ph1_phy_dspmult.v
sim_release/ph1/ph1_phy_dspmult_v2.v
sim_release/ph1/ph1_phy_dspsiou.v
sim_release/ph1/ph1_phy_dspadd_v2.v
sim_release/ph1/ph1_phy_dsptadd_v2.v
sim_release/ph1/ph1_phy_dsplogic_v2.v
sim_release/ph1/ph1_phy_gsr.v
```
