# 准入、SOURCE退休和真实metadata资源短仿真

`run.py`读取本候选当前源码，保存完整输入SHA、TOP准入/defer原码及真实fence实例接线；不读取旧Runs、不改生产RTL。
TOP的fence drop/stale输出仅在测试台连接监视器，不反馈业务。`default_nettype none`防止接线遗漏被隐式wire掩盖。

```powershell
& 'python' refactor/hdr_rx_resilient/src_fpga/simulation/resilience/admission/run.py --name unique_name --modelsim-bin D:/App/modelsim/win64
& 'python' refactor/hdr_rx_resilient/src_fpga/simulation/resilience/admission/analyze.py refactor/hdr_rx_resilient/tmp/resilience/admission/unique_name
```

只用自有RTL，无TD器件模型。本机ModelSim在受限沙箱有已知WinError623，需受控原生启动。每次必须新run名。
输出在本候选`tmp/resilience/admission/`：源码副本、bench、命令与日志、逐拍trace、逐FS disposition、RESULTS。
若运行期间输入源码变化，结果明确STALE。

60场景包括原41准入/退休条件场景，以及18个真实extension builder+V3 join正负终态场景和1个真实CFG快照范围场景。
新场景中资源ready由真实builder/join产生；特征0/F22/F22+F23，统计/record stall为0/1/7拍，并与STOP/CFG交叉。
负统计只计真实error_count，不得永久锁住builder；真实admission的camera_done来自SOURCE握手，RESULT BFM必须等STATUS。

这仍是PIX子系统仿真，非完整TOP：camera事件/context、JPEG算术、sparse record内容生产、真实广播/CDC/DDR/PCIe为边界外或BFM。
原条件资源拉低场景保留其名称，不作为T05缺号原因。详细结论见`docs/ADMISSION_FINDINGS_20261029.md`。
