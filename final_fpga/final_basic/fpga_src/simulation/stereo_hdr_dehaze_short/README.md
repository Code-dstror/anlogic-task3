# 双目 HDR、FPGA 去雾与 HE 冷启动短测

实际生产 TOP 接收 DUAL/N2、v4/2112B、ARM/START，再经唯一 host BAR 写入 HDR＋去雾＋HE 的 32 个 schema2 字并逐字读回。COMMIT 之后检查两台相机完成对应 I²C 配方，四个虚拟通道的真实 FS 均进入 parser。PIX、DFI 配置都为 `0x2A02`，内生自动系数选择保留为 0，预处理硬件看到去雾请求。此时还没有进入可产出视频的热身后帧，RK ACTIVE 与 epoch 仍保持 BOOT，去雾实际应用标志为 0。

`hdr_he.patch` 只改私有复制的测试夹具，原有满幅长测和被测 RTL 保持原字节。ModelSim 采用工程独立源清单和指定 TD 的原语模型。运行前后复核所有已封印生产文件、当前测试、测试所用原夹具及生成后的仿真输入。每次用不同的运行名。

```powershell
& 'python' -B refactor/camera_shared_r1/src_fpga/simulation/stereo_hdr_dehaze_short/run.py --name hdr_he_haze_repeat --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

已运行 `hdr_he_haze_short1`，54 项检查通过，墙钟 89.125 秒。生产设计 SHA256 为 `e48734eef8ff160b77d735f446a00583ead1cb1900cddd4b3b39383582b44331`，实际仿真输入清单 SHA256 为 `498f5367a9b4302b251c36ca9c922f8f66c3e7d98f49b6c63dac66bd4d057838`。自有运行告警 0，厂商 IP 与模型告警 298。见工程的 `tmp/stereo_hdr_dehaze_short/hdr_he_haze_short1/result.json` 和 `tmp/unified_dual_rate/hdr_he_haze_short1/run.log`。首幅完整产品、去雾画质、持续帧率和实板另行核对。

2026-11-05 在 CAM1 两拍帧头生产提交 `6c251b7a` 上，以新目录 `commit6c251b7a_hdr_he` 独立重跑。54 项通过，耗时 133.906 秒，400 份生产输入与 617 份完整测试输入起止哈希一致。生产设计 SHA256 为 `cd2a214687e803d7ca3fd9207ac9f92acd4bc8d8f585ba6bac1db8cb0b81f80f`，完整测试输入清单 SHA256 为 `1678b3d7e6f430f2d983b096bcd3e63a7758d84e3302b3c9b2e4a67d2acc68e5`。本次自有运行告警 0，厂商 IP 和模型告警 300。结束标志为 `shadow=2a02 pixel=2a02 dfi=2a02 VC_FS=4 APPLIED=0 restored=0`。
