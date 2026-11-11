# 未接入生产的2PPC颜色原型

`color_wbccm2.v`、`color_gamma2.v`、`wide_color_pipeline2.v` 只用于专用A/B验证，没有登记AL/manifest或替换现有生产模块。最终测试原字节SHA保留，测试后仅从生产RTL目录移到本目录；runner只调整源路径，没有改算法或再次运行测试。

数值和有限反压已通过，但实际SDR最短输出行距未获权威证明，不能签核原CSI FIFO下的无loss/60fps。因此本批明确不采用，不改变HMAX/VMAX/INCK或Tone96，不作为batch的完成项。

结果入口：`docs/COLOR2_PROTOTYPE_RESULTS_20261030.json`、`docs/COLOR2_PROTOTYPE_20261030.md`。
