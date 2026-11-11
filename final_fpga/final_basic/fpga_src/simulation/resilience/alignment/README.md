# 有界 byte/word 对齐验证

本目录仿真实际候选 `src_fpga/rtl`，每次复制输入、封 SHA256、运行后再次核对；
不读取另一候选作为生产源，不修改 vendor IP/参考/工程/约束，不启动服务器或板卡。

合同：输入为同 WORD 时钟的4lane反串行字节，lane0在低8位；word/gear输出32bit，
没有ready，也不提供反压。byte-valid表示本包该lane已找到同步；word对齐数据窗口为0..5拍。
packet-done结束的是CSI包，和相机FE/PCIe TLAST不是同一边界。enable为接收控制而非stall；
停用或复位取消候选。packet-done优先于同拍采集，任何已超出窗口的lane不能饱和tap5继续发布。
没有新增端口、CDC、ERAM或数据缓存深度；word仅增加每lane一个valid历史位。

正常packet的有效字仍逐拍推进，payload内B8保留数据意义。小于等于5拍的伪SoT与合法deskew
仅靠本级数字时序不能完全区分，必须保留后级ECC/CRC/帧边界真实检查及负终结；本级不填补头。

```powershell
& 'python' -I -B refactor/hdr_rx_resilient/src_fpga/simulation/resilience/alignment/run_matrix.py --output-root tmp/hdr_rx_resilient_20261029/alignment --name matrix_r01 --modelsim-bin D:/App/modelsim/win64
& 'python' -I -B refactor/hdr_rx_resilient/src_fpga/simulation/resilience/alignment/run_hdr_shared.py --output-root tmp/hdr_rx_resilient_20261029/alignment --name hdr_controls_r02 --modelsim-bin D:/App/modelsim/win64
```

每次使用全新name，不能覆盖已完成结果。路径来自本机ENVIRONMENT.local.md。
纯RTL仿真，不使用TD器件模型；ModelSim在本机沙箱Win623时按正常提权流程原生运行。

实际结果：

| 检查 | 结果 | 日志 |
|---|---|---|
| 184场景 | 76/76合法控制精确；所有超界/长提前/不同相位伪SoT均拒绝或恢复精确；16个短提前仍产生待parser拒绝的坏数据 | tmp/hdr_rx_resilient_20261029/alignment/matrix_r01/summary.json |
| 实际候选aligner+HDR parser | 32检查，48连续短包、真实byte间隙8/12/16、WC残数、CRC跨字、坏包负终结、stall、复位通过 | hdr_controls_r02/hdr.log |
| 控制边界 | 51检查，packet-done与acquire同拍、disable/reset、byte-found取消通过 | hdr_controls_r02/control.log |

上表最终运行Errors/Warnings均0。`hdr_controls_r01`保留测试移植时未显式连空诊断输出的告警失败；
修正的是本目录测试接线，生产RTL未因此改动。

`run_matrix.py`的scoreboard独立生成头/60B payload/CRC，比较17个字；wait/done为明示模拟反馈，
不是生产parser。它对超界等风险强制“精确或无发布”，对短提前保留观察到的错误有效字并要求后续
真实parser验证负终结。包间反馈的HDR验证使用真实parser；SDR实际40槽raw拒绝后健康帧与短提前
CRC闭环位于相邻`../recovery`目录，由其日志签核，不能从本矩阵推导。

测试不签电气、实板噪声或布局根因；综合/P&R/时序/bitgen/板级均NOT_RUN。
