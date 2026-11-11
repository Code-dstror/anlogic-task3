# C2 混合记录离线样本

`mixed_records.bin`按原顺序拼接已保存的1条JPEG＋16条LZC1记录，1,262,152B，SHA256
`6204b05b0f4c3551ea7a9b8cf2dc52f7d1e3913eaf611f3936388cae8df7e470`。
每条记录的原路径、SHA、偏移和长度见[manifest.json](manifest.json)。未增加padding或改动header。

来源为[最新C2实际MAIN资格](../../../../src_fpga/stages/r8_stage3/pending/timing_closure_20261016/validation_c2/qualification.json)。
这是合成CSI刺激下真实RTL/DDR/CRC/native链路已经生成的输出，**不是开发板拍摄**；header中的物理
输入标识描述被模拟的FPGA入口，不能当作现实传感器或时钟资格。保存本样本没有重跑FPGA仿真。

无板检查（从仓库根目录，使用与本机兼容的已有native库）：

```sh
python3 -B -m linux.rk_debug inspect \
  --input linux/rk_debug/fixtures/c2/mixed_records.bin \
  --jpeg-version 3 --session 1 --epoch 1 \
  --lz-library /actual/compatible/liblz_native.so \
  --report-output /actual/new-output/c2-inspect.json
```

Windows把库参数换为现有`linux/lz_native/build/lz_native.dll`。预期为1条完整JPEG、16个LZ chunk、
1帧2,592,000B RAW；完整payload/RAW摘要列在manifest中。可用新的`--export-dir`导出JPEG、
完整RAW及来源sidecar。这里只验证文件格式与原生恢复，不证明DMA、MPP、HDMI或持续帧率。
