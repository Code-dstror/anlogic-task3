# camera_fusion_r1 JPEG 熵编码独立短测

测试作者从新上下文接收公开端口、合法参数、身份错误及取消合同。只编译和哈希不透明 RTL 与厂商模型。用新编写的输入、公开端口监视器和 JPEG 数学 oracle 评分。模型不从 DUT 生成期望。

功能 PASS 均来自迁移前的运行。测试与报告归入 `camera_fusion_r1` 后，只校验路径、SHA-256 和生成的测试输入。旧运行命令及其输入 SHA 可通过迁移映射和运行目录的源码快照核对。[源码路径与 SHA-256 映射](blackbox-source-paths.json)

- [公开接口、参数和 JPEG 合同](../../fpga_prj/verification_archive/verification_reference/jpeg_throughput_public/CONTRACT.md)
- [短测代码](../../src_fpga/simulation/blackbox_entropy_area_r2/)
- [独立 JPEG 数学参考](../../../../tools/jpeg_ref/jpeg_ref.py)

## 功能覆盖

| 门 | 事务与断言 |
| --- | --- |
| `jpeg_entropy` | 生产 STREAM/RESTART/BANKED profile。21 MCU 测 ±2047 DC 差、±1023 AC、EOB、16/32/48 个零后的非零值、八种位对齐和 D0→D7→D0 回卷。首字节、首 RST 编号字节、最后字节分别停顿 7 拍。逐字节比较并检查 LAST 和 DONE，包含以 FF00 结束且 LAST 在 00 上的合法扫描。 |
| `jpeg_entropy` 异常 | DC 差 ±2048 各一次，期望 code 2。已建帧的后续 HEADER 更改 capture ID，期望 code 4 和原 capture ID。取消保持已发布字节直至接受，复位允许撤回未接受字节。每个异常后都从合法新帧到 LAST/DONE。 |
| `jpeg_encoder_top` | 真实共享流、banked、row stream、双几何编译容量 3840×32。输入为 1920×16 灰阶平坦、3840×32 灰阶纹理（DRI 17）、1920×16 灰阶纹理负 SOURCE、1920×16 灰阶斜坡恢复。三帧成功逐字节核对完整 JPEG，并用 Pillow 完整加载 RGB 像素，与独立 JPEG 的解码像素一致。检查实际 SOF 尺寸、4:2:2 采样、DRI、AXIS KEEP/LAST、已冻结的 RESULT 字段。 |
| `jpeg_encoder_top` 终态 | 低档先接受 LAST 再送正 SOURCE。高档先接受正 SOURCE，再持有 LAST 10 拍。负 SOURCE 在已发布 AXIS 拍被阻塞时接受，保持该拍，排空后才提交 STATUS、零长度与原身份。每个 RESULT 均受反压，负帧之后同次运行内接受并完成新帧。 |

21 MCU 直接扫描 oracle 为 4,097 B，含 456 个 FF00、126 个 ZRL 和 10 个 RST。完整编码器的像素输入由独立 Python 配方生成，R/G/B 都等于显式供应的 Y。Q14 双遍 DCT、Q75 舍入、BT.601 灰阶中性 Cb/Cr、Huffman 与位封装决定期望字节。所有比较计入实际握手，AXIS 长度按 KEEP 对账。

## 运行和证据

Python 3.12.9、Pillow 12.2.0、ModelSim SE-64 2020.4 和 `TD_Release_2026.2.210.850`。不透明输入按 manifest 的 SHA-256 封存，使用 `work.PH1_PHY_GSR` 和 `ph1.glbl`。ModelSim 单进程墙钟限 56 秒，测试整套限 177 秒。直接熵与 encoder 台分别设置 280,000 和 2,200,000 周期看门狗，PIX 时钟周期 8 ns。

以下重跑命令从仓库根执行。每次选择新的运行目录。

```powershell
$jpegPy = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
$jpegStage = 'refactor/camera_fusion_r1'
$jpegRun = "$jpegStage/tmp/entropy_area_r2_blackbox_production_replay_01"
$jpegRunner = "$jpegStage/src_fpga/simulation/blackbox_entropy_area_r2/run.py"
$jpegTd = '<TOOLS_ROOT>/TD_Release_2026.2.210.850'
$jpegSim = '<TOOLS_ROOT>/modelsim/win64'
& $jpegPy -X utf8 -B "$jpegStage/experiments/entropy_area_r2_20261110/compile_blackbox.py" --manifest "$jpegStage/tmp/entropy_area_r2_20261110/syn16_a1/blackbox_inputs/production/compile.json" --variant production --run-dir $jpegRun --td-root $jpegTd --modelsim-bin $jpegSim
& $jpegPy -X utf8 -B $jpegRunner --run-dir $jpegRun --td-root $jpegTd --modelsim-bin $jpegSim
```

重跑使用新的 `--run-dir`。每个运行目录的 `compile_inputs.json` 记录实际模型和 RTL SHA、编译命令。 `blackbox_run.json` 记录工具版本、实际命令、耗时和 TB/oracle SHA。 `fixtures.json` 记录输入和期望哈希，`*.trace` 和 `*.score.json` 保存握手、停顿、终态与字节计数。保持失败目录用于定位。

### 生产基线 PASS

`refactor/camera_fusion_r1/tmp/entropy_area_r2_blackbox_production_a1/` 的直接熵 11 事务通过，仿真 4.14 秒。完整编码器 4 事务通过，仿真 47.20 秒。

| 场景 | 输入 4PPC 握手 | AXIS 字节 | AXIS LAST 周期 | SOURCE 周期 | RESULT 接受周期 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1920×16 平坦 | 7,680 | 1,211 | 19,267 | 19,275 | 19,285 |
| 3840×32 纹理 | 30,720 | 69,587 | 114,759 | 77,157 | 114,769 |
| 1920×16 负 SOURCE | 7,680 | 3,584 可丢弃前缀 | 无 | 122,471 | 122,490 |
| 1920×16 恢复 | 7,680 | 5,111 | 141,747 | 130,179 | 141,757 |

测试输入与期望清单 SHA-256 为 `ab7a22dfa6045e72ffcc26304dc36d1391e24fe964da46c251539d802a8e7d6a`。所有成功 JPEG 的真实长度与 RESULT 一致。短测保留两档生产宽度和较少扫描行，范围为熵编码及 JPEG 叶级。板级、DDR、满幅稳态 FPS、物理实现和 STA 由各自证据评估。

### 候选 01 首次运行

`refactor/camera_fusion_r1/tmp/entropy_area_r2_blackbox_candidate01_a1/` 编译通过。直接熵 11 事务通过，仿真 2.75 秒。包含所有字节、输入接受、停顿及终态周期的 `entropy.trace` 与基线 SHA-256 相同，均为 `c108dedcc103840e0bb7dc0e6a721a3a3e8e3e31b656b36f182d29094ef4a19f`。

完整编码器运行与本地 TD 重叠，触及 56 秒墙钟预算，加进程树退出共 56.70 秒。高纹理帧最后观察到周期 101,891，工具超时，完整编码器状态 BLOCKED。原始 `encoder_vsim.log`、`encoder.trace` 和 `blackbox_run.json` 保留在该目录。

独占窗口补跑目录 `refactor/camera_fusion_r1/tmp/entropy_area_r2_blackbox_candidate01_a2/`。复制上次编译库和 ROM 到新目录，`compile_reuse.json` 记录原路径和编译回执 SHA。56 秒墙钟再次触发，加退出共 57.05 秒。前三帧到终态，最后到恢复帧约第 130,006 周期。完整编码器 BLOCKED。候选 01 的最终资格只采用已通过的直接熵短测。

### 最终候选分组

原四帧输入及数学期望保持原哈希。对基线与候选 02 均用 `--split-encoder` 把 encoder 仿真分成两组。首组低档成功切换到高档纹理成功，次组低档负 SOURCE 后同次复位继续低档恢复。各组分别复位并记录独立采样周期，单进程墙钟上限仍为 56 秒。直接熵 11 事务的仿真与 oracle 保持原样。

候选 02 编译 manifest SHA-256 为 `13e26fb9f7d6d551ec473446c6b1f0417d63d05fbd3ae2a006042f564579d061`。所编译的 `jpeg_entropy.v` SHA-256 为 `c6f2e10a8208e500c98154d3e7647f2d4d11a8ed3e7df9fd1f94a09b488a77c7`。基线 SHA-256 分别为 `bc0b252a72645847f878c551b2da93c6dc325527d45eb9eb483d0618bbb4c5ba` 和 `baf534007844b006331b0f0095079fbcc1a698ad74ef6003454010c5592c9663`。

分组仿真调用沿用上节显式工具路径。先通过封存 manifest 在新目录创建不透明编译库。候选 manifest 位于 `$jpegStage/tmp/entropy_area_r2_20261110/syn16_a1/blackbox_inputs/candidate02/compile.json`，variant 为 `candidate`。候选编译调用外层另设 56 秒进程树墙钟上限。

```powershell
$jpegCandidate = "$jpegStage/tmp/entropy_area_r2_blackbox_candidate02_split_replay_01"
$jpegBaseline = "$jpegStage/tmp/entropy_area_r2_blackbox_production_split_replay_01"
& $jpegPy -X utf8 -B $jpegRunner --run-dir $jpegCandidate --split-encoder --td-root $jpegTd --modelsim-bin $jpegSim
& $jpegPy -X utf8 -B $jpegRunner --run-dir $jpegBaseline --target encoder --split-encoder --td-root $jpegTd --modelsim-bin $jpegSim
```

基线分组复制生产基线的不透明工作库和 ROM，`compile_reuse.json` 绑定原始编译回执。直接熵的基线采用 `entropy_area_r2_blackbox_production_a1/entropy.trace`。候选 02 的直接熵 11 事务和 encoder 4 事务均通过独立 oracle。直接熵、低高成功组、负 SOURCE 恢复组分别用时 4.20、37.84、6.20 秒。生产基线的 encoder 两组分别用时 52.33、7.88 秒，均通过独立 oracle。[候选运行回执](../../tmp/entropy_area_r2_blackbox_candidate02_split_a1/blackbox_run.json) · [基线分组回执](../../tmp/entropy_area_r2_blackbox_production_split_a1/blackbox_run.json)

基线与候选 02 的原始 trace 完全相同，包含每次输入、输出、停顿、SOURCE、RESULT、错误、DONE 和 idle 的采样周期。三份成功 JPEG 的完整字节、AXIS KEEP/LAST 以及负 SOURCE 的可丢弃前缀都相同。两组末 RESULT 分别在第 114,769 和 26,998 周期接受。[A/B 路径与哈希](../../tmp/entropy_area_r2_blackbox_candidate02_split_a1/comparison.json)

| A/B 相同记录 | SHA-256 |
| --- | --- |
| `entropy.trace` | `c108dedcc103840e0bb7dc0e6a721a3a3e8e3e31b656b36f182d29094ef4a19f` |
| `encoder_success.trace` | `b3940290abf84be742ad121de882218f39ec45adf3c30001ddf252f960e40fef` |
| `encoder_recover.trace` | `82556ca775eeccf4c12fe4485faf169446e96a975bc491fa6f424fa7ec05c2ad` |
| `encoder.trace` | `7a2436e77f589a16ffa9022d27d7226c12bab3944d4ea699d0cbcdbc0809f30e` |
