# RAW、HDR、Tone 和共享 ISP 黑盒短测

测试作者使用公开端口编写了新夹具。RAW 期望由五字节组队列生成。融合和色彩期望由整数公式、Bayer 邻点与公开 Gamma 表生成。两份 Tone MIF 只用于仿真模型初始化。[RAW 合同](../../../fpga_prj/verification_archive/experiments/raw_ingress_equiv/PUBLIC_CONTRACT.md)、[HDR 融合合同](../../../../camera_hdr_quality_r1/analysis/fusion/PUBLIC_CONTRACT.md)、[Tone 数值合同](../../../../camera_hdr_quality_r1/analysis/tone/PUBLIC_CONTRACT.md)、[共享 ISP 合同](../../../../camera_hdr_quality_r1/docs/blackbox/ISP.md)、[HDR 读取合同](../../../../camera_hdr_quality_r1/docs/blackbox/READER.md)。

| 检查 | 功能仿真 | 终态及覆盖 |
| --- | --- | --- |
| RAW 基线与候选 | 两臂 PASS，四份公开轨迹逐沿一致 | 每臂 15 END、7 ABORT。32×2 与 64×2 连续换帧，前帧 END 与次帧 SOF 同沿，固定 LONG/SHORT 和 40×2 的 4-byte 尾。检查四个 SOURCE 身份字段、坏 SOURCE 时的末拍保护、捕获反压溢出、早 EOL、帧内 SOF、取消、禁用、复位和恢复。 |
| HDR 融合 | PASS | 2,284 组成对输入覆盖平衡和旧兼容预设，检查残差、膝点、饱和、配置极值和六推进沿延迟。160 组有限反压产生 97 个停顿周期。停钟时断言 clear 或 reset，复钟后各完成 64 组恢复。 |
| Tone | PASS | 四页各 16,384 个灰码，稳态每两拍接收四像素组。768 组混合彩色及 SDR 输入覆盖并列最大值、高光底值和页切换，产生 466 个停顿周期。clear 与 reset 后各恢复 64 组。 |
| 直接色彩流水 | 两臂 PASS | 每臂 336 组、7 帧、108 个饱和组，逐拍核对输出和统计。6 次相邻帧参数同时在途，304 个停顿周期。取消在途输出后恢复 48 组。 |
| 真实共享 ISP | 两臂 PASS | 每臂 6 帧共 3,925 组，含 3840×4 SDR 图。GBRG 去马赛克、WB、四页 HDR Tone、Gamma 与统计逐组核对。每帧最后 RGB 组停顿六拍后成交并回到 `o_job_idle`。在途复位后另一帧的 15 组全部退休。 |
| 真实 HDR 读取链 | PASS | 六个 68×63 作业覆盖两眼两 bank 的四组合及两个预设。每个作业两成员各完成 335 个 AXI 字，覆盖跨 4 KiB 和末 11-byte，逐码检查共 6,426 个 RAW14 四像素组。START 后和末组停顿时改变配置引脚，最后 RAW 持稳 7–8 拍后成交，RESULT 持稳到接受且 `o_read_quiet=1`。 |

读取链注入 SLVERR、AR 呈现未接受时取消、已接受 AXI 读和已呈现 RAW 同时在途时取消。三种故障分别排完 16、16、176 个已承诺 AXI 字后收到失败 RESULT，下一作业各自通过。在途 RAW 协调复位后新作业也通过。记录 163 拍 AR 停顿、1,794 拍响应供数空洞和 5,517 拍 `RVALID && !RREADY`。

RAW 的小画幅覆盖打包与帧边界，3840×4 覆盖生产行宽下的缓存和邻点边界。整机帧率、光学画质、CSI、物理 DDR、JPEG、RK 联机与板级属于独立验证范围。本门的整机综合、P&R、物理 STA、bitgen 和板级状态均为 **NOT_RUN**。

## 运行与证据

在仓库根使用 `ENVIRONMENT.local.md` 登记的 CPython 3.12、ModelSim SE-64 2020.4 和 TD 6.2.3.210850。示例的 `$fusionPython`、`$fusionModelsim`、`$fusionTdRoot` 分别为 Python 可执行文件、ModelSim bin 目录和 TD 根。为每次重跑使用新目录。

```powershell
$fusion = (Resolve-Path refactor/camera_fusion_r1).Path
$bb = "$fusion/src_fpga/simulation/blackbox_fusion_datapath"
& $fusionPython -B "$bb/run_raw_ingress.py" --modelsim-bin $fusionModelsim --td-root $fusionTdRoot --run-dir "$fusion/tmp/blackbox_fusion_datapath_raw_replay"
& $fusionPython -B "$bb/run_datapath.py" --modelsim-bin $fusionModelsim --td-root $fusionTdRoot --run-dir "$fusion/tmp/blackbox_fusion_datapath_isp_replay"
& $fusionPython -B "$bb/run_reader.py" --modelsim-bin $fusionModelsim --td-root $fusionTdRoot --run-dir "$fusion/tmp/blackbox_fusion_datapath_reader_replay"
```

色彩 A/B 的生产侧编译当时的 `src_fpga/rtl/wide_color_pipeline.v`，候选侧通过 `--color-candidate "$fusion/experiments/color_pipe_equiv/candidate/wide_color_pipeline.v"` 替换唯一同名源。对已采纳源重跑当前功能门使用上方默认命令。可用 `--cases merge` 等选择具体门。每个子进程墙钟最多 60 秒，RAW、数值和读取链 runner 总墙钟分别为 160、180、120 秒。各测试台有独立仿真时间 watchdog。

| 原始运行目录 | 保存内容 |
| --- | --- |
| `tmp/blackbox_fusion_datapath_raw_02` | 两臂命令、哈希、终态、原始日志、四配置逐拍轨迹。 |
| `tmp/blackbox_fusion_datapath_isp_02` | Tone、两臂色彩与共享 ISP PASS。合入候选与原版源码 SHA 在 `inputs.json`，四套向量和 ROM 初始化 SHA 在 `vectors.json`。单独 merge 的缺库启动日志原样保留。 |
| `tmp/blackbox_fusion_datapath_merge_03` | 加载同版 TD 全局模块后，独立 HDR 融合 PASS。 |
| `tmp/blackbox_fusion_datapath_reader_01` | 实际 reader、共享解包、成员 RAM、MAC 模型及夹具的文件哈希，作业向量、命令、原始日志与 RESULT 终态。 |
| `tmp/blackbox_fusion_datapath_raw_01`、`tmp/blackbox_fusion_datapath_isp_01` | 保留原失败。RAW 夹具把最后组前的普通 DATA 也挡住，修正为按实际 TUSER/TLAST 只暂停最后 DATA。ISP 初次准备阶段将 Tone MIF 宽度误写为 96，按实物 512×40 修正后运行。 |

RAW 两臂 SHA-256 分别为 `787acfaef657a6cf709f2e808bfdaaa2e750546d0dd89ed0b8800f3f227e7ccd` 和 `8569d76989de58b9940cfa9090f8f3fd3ecd6c3eddea75b34fa31e01743381c3`。色彩两臂分别为 `88b84e37bd4dc9dd2a8137bdd7b5ef420fcb424b4095ea343d7621f0ec2054c2` 和 `54f2c7e04a376d926c63dc16d7b18e81f3a8a221c4caf49cfb426fdd9fcc1db5`。所有通过门的源文件、测试台与输入合同前后哈希一致。原始日志保留模型警告。
