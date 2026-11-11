# 双目满幅 physical60 / 真 FS N2 验证

这是新夹具，保留 `tb_dual_imx415.sv`、旧 extended fixture 及其历史结果。
来源与适配范围见 `PROVENANCE.json`。生产源从当前候选实际清单和编译组
取 SHA256 快照，不继承 6f 或 06a 的资格。

默认 Q75、1920×1080、每眼8个真实 CSI RAW10 frame、固定16.666667 ms
物理周期、FS N2、每眼4个产品，两眼相差329 ns。保留原电气输出的
8.888888 ns word clock 与一拍有效一拍空闲、完整 ECC/CRC/FS/FE、实际
相机解析/crop、每眼两RAW槽、官方CDC FIFO、共享ISP/JPEG、真实v4
SELECT/2112B、DDR及native C2H SAFE/ACK。相机绝不等待下游ready。

复用旧满幅夹具的有界五通道DDR间隙、每条真实C2H末拍stall和13周期
延后ACK。R和B计数绑定真实 `rd_active && !axi_rvalid` 与
`b_pending && !axi_bvalid`；没有 `&&0` 占位。

输入截止时保存每眼 writer/SAFE/retire 和 RAW/JPEG在途数，之后才单独
排空。通过要求所有4个选中帧在固定输入窗口内到达完整JPEG和host SAFE，
并完成全部实际RAW/JPEG退休。每个可信FS的独立序位0/2/4/6必须选中，
1/3/5/7必须跳过；选中 SOURCE 与处理/完整wire逐眼同序、无重号。
独立checker核每幅完整ISP栅格、v4实际/本地逐字节、SOURCE与slot代次、
完整固定点JPEG逐字节及Pillow全解码。每眼图案各自不同，帧间图案固定，
不把它描述成运动场景或10分钟板级持续能力。

真实UART保持运行；新诊断协议使用自己的专测，本夹具不套旧UART decoder。

```powershell
# 只编译/展开
python refactor/dual_unified_r1/src_fpga/simulation/unified_dual_rate/run.py --name hd_compile_new --compile-only --modelsim-bin D:/App/modelsim/win64 --td-root D:/App/TD_Release_2026.2.210.850
# Q75 CFG/APPLIED、v4 SELECT、冷双目启动、真实坏CRC排空短门
python refactor/dual_unified_r1/src_fpga/simulation/unified_dual_rate/run.py --name hd_startup_new --startup-only --wall-timeout 180 --modelsim-bin D:/App/modelsim/win64 --td-root D:/App/TD_Release_2026.2.210.850
```

省略这两个短门参数才执行长仿真与独立oracle。长仿真启动前冻结生产、
测试及参考；输出是 `tmp/unified_dual_rate/<name>`，不能覆盖既有运行。
本轮不操作服务器、综合/P&R、时序、板卡或串口。

## 双目真 HDR 专测

在同一 runner 加入 `--stereo-hdr`。启动门使用 `--startup-only`。通过冷 DUAL/N2、v4 SELECT 和 ARM 后，经真实 BAR 提交 schema2 HDR。左右 IMX415 的 I²C 主机均运行，仿真在从机 SDA 边界给 ACK。分别从两路 PHY geared-word 边界注入带 ECC 的独立 VC0、VC1 FS，检查两眼 HDR 模式、四个实际接收计数以及会话和拓扑读回。此门止于暖机前，尚无业务 JPEG 或 APPLIED 首帧。

省略 `--startup-only` 验证完整产品。每眼输入 1944×1097 RAW12 长短成员，逐包计算 ECC 和 CRC，经生产裁剪得到 1920×1080 RAW10。测试保留独立时钟，设置 329 ns 输入错相。仿真将 I²C/唤醒等待缩短，暖机改为一对，使用仿真 DDR/PCIe 端点。暖机后两眼各一组真实产品，检查 v4 SOURCE、LONG 角色、HDR/QUALIFIED/PAIR/JOB 位、非零 job=pair、JPEG 边界和真实 host SAFE/ACK，输出二进制供独立解码。此测不签收持续每眼30或实板。

```powershell
python refactor/camera_shared_r1/src_fpga/simulation/unified_dual_rate/run.py --name hdr_startup_new --stereo-hdr --startup-only --wall-timeout 850 --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
python refactor/camera_shared_r1/src_fpga/simulation/unified_dual_rate/run.py --name hdr_full_new --stereo-hdr --wall-timeout 14400 --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

较短的 `stereo_store/run.py --case hdr` 在 16×4 几何检查四成员同时写入、服务等待、真实 B 响应、分眼组目录和负终态恢复，用标量参考逐点核真实共享合并核的 RAW14。该测试的 AXI 外部为有界存储模型。