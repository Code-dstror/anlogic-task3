# camera_raw_r2 · 1a5603c1 · seed25 调试包

固定源码：`1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba`，目标PH1A90SEG324-2。
已核验种子25在当前有效约束下时序收敛：setup **+0.001ns**，hold **+0.007ns**，recovery **+2.838ns**，removal **+0.002ns**；setup/hold TNS=0。Slow/Fast两角、四类检查及例外原件已核对。余量很小，板级全部 **NOT_RUN**。

比特流：[bitstream/camera_raw_r2_1a5603c1_seed25.bit](../../fpga_prj/bit/camera_raw_r2_1a5603c1_seed25.bit)，4,850,315字节。
SHA256：`eee7eff50323a8a5c7ddc850d3873e1dda13473debbfe8a690bcb6bab17ac362`。详见[物理时序和资源](TIMING_REVIEW.md)与[TIMING_VERIFICATION.json](TIMING_VERIFICATION.json)。
布线后Slice **61733/64320（95.98%）**，ERAM **236/272**，DSP **151/240**。
Windows用Get-FileHash、Linux用sha256sum比对bitstream内.sha256；本目录文档清单为SHA256SUMS.txt；完整final_basic文件清单见../SHA256SUMS.txt。

阅读顺序：

1. [Linux交接重点](LINUX_HANDOFF.md)：冷启动、HDR30/30复测、模式切换、UART采集与异常留证。
2. [相比41cb5991 / seed56的改进](CHANGES_FROM_41cb5991.md)：两像素T96、HDR响应预取、SOURCE/JPEG时序修正及RK参数目录。
3. [全功能调试手册](RK_DEBUG_GUIDE.md)：单目SDR60、双目SDR30、单双目HDR30、灰度/高斯/HE/去雾、单目原车道与单/双目RAW10。
4. [已有可调参数](RK_PARAMETERS.md)、[UART DJ/v3字段](UART_FIELD_V3.md)、[测试结果模板](TEST_RESULTS.csv)。

`rk_support` 是固定源码的SDK/CLI叠加、串口解析器和RAW驱动源码候选；不是含全部MPP、HDMI、KO和内核的独立RK镜像。继续使用上轮已匹配的私有R2运行环境。通用SharedDebugSession的BOOT v2/192前置检查与FPGA默认v1/64的差异仍需按手册使用兼容owner或直接同fd API，不能覆盖现场已修好的ColdSession。

`examples/hdr_q75_reference.json`为手册的原Q75 HDR配方示例；先沿用现场上一轮批准的策略进行同条件对照。完整配置需要等待APPLIED和每只活动眼的新epoch真实记录。首轮不要同时修改质量、预算和HDR阈值。

本bit所有板级项为NOT_RUN。RAW是经DDR槽的未压缩RAW10，尚不代表无损压缩或RK ISP已调通。bitgen和STA各自验收，不代替图像质量、满幅持续帧率、实际DMA或显示验收。

本目录由原调试包整理而来，仅附关键原始报告；比特流统一放在../../fpga_prj/bit。迁移和证据范围见[目录检查](../RELOCATION_CHECK.md)。
