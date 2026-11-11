# 真实 TOP 运行恢复 MAIN

本候选2026-11-01仅运行SDR sparse短恢复。HDR硬件保留、调试不启用，
先前未完成的HDR裁剪已撤回。测试中`SDR_WAKE_CYCLES=4`只缩短已单独
验证的传感器等待，生产默认值保持600000。
当前精简只读UART只保留OB/CG/RX；旧RT捕获器已退役，短测不再等待
或引用其40拍RAM，仍检查实际RX首错身份不被第二次故障覆盖。

```powershell
& 'python' -B -u refactor/dual_sdr_lane_r1/src_fpga/simulation/run_main.py --mode sdr --runtime-recovery short --runtime-profile sparse --name sdr_sparse_short_native_r2 --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

可选入口，保留普通 `--mode hdr/sdr` 行为：

```powershell
& 'python' -B -u refactor/hdr_rx_runtime/src_fpga/simulation/run_main.py --mode sdr --runtime-recovery short --name runtime_short_unique --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
& 'python' -B -u refactor/hdr_rx_runtime/src_fpga/simulation/run_main.py --mode sdr --runtime-recovery full --name runtime_full_unique --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
& 'python' -B -u refactor/hdr_rx_runtime/src_fpga/simulation/check_main.py --mode sdr --runtime-recovery --run-directory refactor/hdr_rx_runtime/tmp/main/runtime_full_unique --output-directory refactor/hdr_rx_runtime/tmp/main/runtime_full_unique_oracle
```

运行恢复场景自动选原生产只读UART decoder，避免用历史可写UART测试模型的波特率解码115200串流。短模式直接观察RX/RT寄存器/存储；没有声称完成完整UART分片发送，长模式沿用完整UART结束检查。

刺激的固定顺序：真实FS1和32行RAW建立实际context/native/JPEG owner，包头处注入00097e2b，检查旧SOURCE和writer真实负终结、无成功host record、写响应已结清及真实quiet。FS2在隔离下消费，预裁剪坏CRC行产生真实ABORT清crop，不能准入。FS3再次实际入场、经过恢复历史采样，随后再次注入坏头并退休。FS4同样丢弃。FS5作为恢复输入。

`short`到FS5实际processed SOF、历史采样/清除后结束，资格状态为PASS_SDR_RUNTIME_SHORT；没有完整JPEG或成功帧退休结论，完整oracle拒绝该状态。
短模式可显式选择`--runtime-profile none/gaussian/sparse`，对应schema2 enables0、
legacy MODE_GAUSSIAN=2与schema2 enables48；默认sparse。
该选项只接受short，full保留固定48及独立图像黄金。schema2 enable2表示dehaze，
不是legacy Gaussian；`runtime_top_fix_20261029_m2_r1`保留其PREPARE拒绝的失败，
未进入恢复场景。所有选择仍覆盖两次真实JPEG
START、负SOURCE/负writer、隔离解除与SOURCE5的历史采样；不能据短模式宣称JPEG
成功载荷已逐字节通过。

`full`将FS5完整发送，沿原实际JPEG接收、SAFE/ACK/slot退休和应用STOP检查结束。成功RAW/ISP/processed/F22/F23轨迹只包含FS5；两次坏帧像素在runtime_partial_pixels.txt中，带sequence标签且不参加黄金图像比较。oracle显式固定SOURCE5（普通仍SOURCE1），要求运行标志与资格中的full模式一致，不能从输出回填期望。

监视器另外检查两次receive_fault、两次busy期间隔离、两次独立历史请求经外部输入/F21 descriptor/内部pipeline/HE/output SOF采样，以及同cohort首错RX身份不覆盖。所有驱动仅使用既有接收器geared_word电气边界fixture；无force内部fault、quiet、owner、reset、completion。物理SoT/电气采样、持续满速和板级不在该TOP fixture范围。
恢复FS消费后先独立等待并断言quarantine已经解除，然后才发送用于缩短测试的坏CRC行；
因此解除隔离不依赖该CRC错误。CRC行只结束这个已被明确丢弃的裁剪raster，完整正常
边界帧的自然退出另由`runtime_recovery/README.md`所述实际crop/router/RAW链覆盖。

2026-10-29定位记录：`runtime_top_diag_20261029_r2`中，3.025908ms的真实局部
cleanup脉冲同时看到F22pending/F23valid=11，下一拍reset将它们清为00；SOURCE
直到3.030052ms才负终结。JOIN仍拥有该帧并记录terminal，context2已PRESENT，
但失去两份稀疏记录，故JPEG停在S_RESULT且result_ready=0。`anlogic2026.v`
的LIVE regular cleanup现先以真实像素排空闭合SOURCE，待该SOURCE实际消费、
record extension与JPEG结果退休之后，再调用原同步局部clear helper。旧失败目录
保留；上述记录路径缺陷不作为none模式板上失信机制的唯一归因。

当日真实TOP短测none、F22/F23、legacy Gaussian分别通过205、205、161项检查，
每路均两次负SOURCE/负writer、两次history采样/清除，恢复到SOURCE5。
记录位于`docs/validation/runtime_top_short_20261029.json`。三路366份实际RTL/IP
输入均与最终生产字节一致；none/F22/F23使用命名profile加入前的测试入口，其
精确测试源码已按原source_identity SHA256保存在各run的`input_snapshot/`。
不把这些旧入口资格冒称为最终测试文件的逐字节资格。综合、P&R、时序和板级
在这些短测中均NOT_RUN；长MAIN和独立完整JPEG oracle是后续门。

结果以每个唯一运行目录qualification.json为准。r1的历史失败来自未选只读UART decoder导致旧测试模型解码失败，原记录保留；不能把它计为生产恢复缺陷或覆盖为PASS。
