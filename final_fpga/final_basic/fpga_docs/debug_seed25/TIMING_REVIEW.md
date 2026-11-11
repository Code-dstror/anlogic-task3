# seed25时序与资源核验

固定源 `1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba`；GitHub结果提交 `0a6ce37ac5dab18599beb5d8c91801d7e1557ca4`，缺失的9份原件由用户从同一服务器任务目录手动复制补齐，来源和SHA见MANUAL_RECEIPT.json。
任务 `manual-camera-r2-hdr-rate-20261110-syn16-48s4t-8e64f48baa674f98-s25`，一次16线程综合检查点复用，当前物理种子25、4线程。placement/routing/bitgen/reports/reopen均DONE，板级NOT_RUN。

核对同一phy_1的final_timing.rpt、simple.timing、controller-reports/timing_detail.rpt与例外报告；Confidence=Routed，Both(Slow/Fast)，STA coverage 99.85%。
最终setup/hold TNS均为0；所导出的路径组违例端点数均0，四类详细路径未发现负数或负零。

| 检查 | 最低已报告余量 | detail展开路径数 | 最差路径行号 |
|---|---:|---:|---:|
| hold | +0.007 ns | 1652 | 10287 |
| recovery | +2.838 ns | 40 | 188573 |
| removal | +0.002 ns | 358 | 9987 |
| setup | +0.001 ns | 2510 | 119 |

报告目录：`server_evidence/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/`。
具体端点、角、行号及原件SHA在TIMING_VERIFICATION.json。展开条数是工具选出的路径数，不等同全设计独立端点数。
最终controller-reports/run_parameters.txt读回seed25、thread4；thread-phy_1.params是设置seed前的线程快照，不能用其中继承的seed2代替最终种子。
128条DDR写数据0.350ns min guard全部命中且Dominated，未被Shadowed/Ignored。

**当前有效约束和工具报告精度下，种子25时序收敛；setup仅1ps、removal仅2ps，余量仍很小。** 报告顶部SWNS=+0.001ns、HWNS=+0.002ns；其min摘要包括removal检查。逐路径Check Type为hold的数据保持检查最小+0.007ns，removal最小+0.002ns，因此二者并不矛盾。三项path_skew余量+6.546/+6.667/+5.823ns，Period Check WNS=+5.972ns。
不把STA通过解释为板级全功能或其他种子必然通过。覆盖边界、I/O及原有例外见同目录check_timing/exception原件；不声称100%全板签核或零警告。

| 同阶段资源 | 上版41cb5991 | 本版1a5603c1 | 差值 |
|---|---:|---:|---:|
| 原始综合Slice | 63022（97.98%） | 63334（98.47%） | +312 |
| 综合重开Slice | 62484（97.15%） | 62791（97.62%） | +307 |
| 布线后Slice | seed56：61450（95.54%） | seed25：61733（95.98%） | +283 |
| ERAM | 230/272 | 236/272（86.76%） | +6 |
| DSP | 146/240 | 151/240（62.92%） | +5 |

布线后对比来自不同种子，因此差值同时包含布局映射差异。FF和LUT细分以原生simple.area及phy.area为准，不把全部内部lut节点数当成物理LUT容量占比。
本版布线后寄存器71942/128640（55.93%），LUT6等效统计57200/64320（88.93%）。

check_timing中无时钟网络、无效约束、组合环、无路径约束均为0；保留2个相机local clocks、3类dummy节点、2个PCIe时钟静态PLL频率差异、1项异步max-delay检查、4类shadowed/ignored检查、38项无input delay、57项无output delay。PCIe当前按125MHz检查，静态PLL参数为62.5MHz；本轮未改该约束或频率。UART握手/例外不意味着全部I/O和板级电气获STA覆盖，传感器MCLK、训练及接收仍由实板验证。
实际物理日志仍有PHY-5054系统时钟结构、CLKST-5093 DDR GCLK级联、PHY-5031/5050/5060相机MCLK及区域时钟资源、USR-6144 PCIe频率检查和TMST-7700严重检查提示。保留原件与上述覆盖边界，不能把最终无负裕量写成“无警告”，也不能用外部MCLK未覆盖端点推断传感器电气已通过。

本次149份完整制品、217077653字节已核验：140份来自GitHub客户端的分块/整文件SHA验证，另9份来自手动回传压缩包，其归档SHA与所附服务器sha256sum一致；已有文件和reports.json里的报告SHA交叉匹配。合并本地清单VERIFIED_ARTIFACTS.json剩余缺件0项。原始ARTIFACT_INDEX/DOWNLOAD_RECEIPT中的9项pending保留为当时GitHub通道状态，不表示本包缺件。关键bit、四类STA、物理检查与资源原件已完整。日志警告不因完成状态而抹除，保留stage-logs及run.logw供后续复盘。
