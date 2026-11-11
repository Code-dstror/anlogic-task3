# 候选本地双目启动与SDR短测

2026-11-01最新范围：保留固定`5e302ae06e`的HDR及共享ISP/RAW硬件，
本轮只调试SDR。先前未完成的HDR裁剪已撤回，不以目录名宣称HDR已删除或已修复。
生产模块不因本测试改造；只验证父代理最终冻结的候选源码。

```powershell
& 'python' -B -u refactor/dual_sdr_lane_r1/src_fpga/simulation/stereo_startup_fix_r1/run_top.py --scenario control --name sdr_control_r1 --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

`control`在真实TOP执行冷DUAL APPLY、自由RAW流中的v4 SELECT，
并检查真实APP enable后SELECT仍返回BUSY。它不生成完整JPEG/PCIe图像产品。
DDR、电气和主机边界模型在`MAIN_FIXTURE.json`中明确；源身份与实际工具版本
写入本候选独立的`tmp/stereo_startup_fix_r1/<name>/`。

保留的`RESULTS.json`描述原donor历史，不能作为本候选本次通过证据。
当前结果以新运行的`qualification.json`及其源哈希为准。
本次control为PASS（51.718秒、12检查），mono sparse短恢复为PASS
（74.844秒、371检查、两次真实负SOURCE/负writer后恢复SOURCE5）。
完整命令、边界和日志哈希见`RESULTS_SDR_20261101.json`。
未重新运行四分钟双眼完整RAW；必要的字节对齐guard由独立短测覆盖。
综合、P&R、STA、bitgen和板级均不由本短测证明。
