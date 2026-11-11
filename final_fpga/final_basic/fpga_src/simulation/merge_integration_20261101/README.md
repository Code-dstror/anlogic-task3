# 完整主工程HDR合入验证

本目录仅含候选独立测试、协议/数值参考和有界监督器；不更改生产RTL、IP、约束、
现有MAIN_FIXTURE或原TB。旧完整HD资格保留为测试来源，不继承到当前源码。

`hdr_startup`复用2026-10-31实际3461秒PASS的lane输入及独立oracle，增加完整跳组2的
跨VC重叠。输入计划独立固定：8个retained good为1、3至9，首产品为SOURCE10；
全部10个输入group均送满1944×1097。验证真实APPLIED、两成员SOURCE、DDR、RAW14、
ISP/T96、完整JPEG逐字节和独立解码、v4、SAFE/ACK与回SDR坏CRC取消。
只替代既有电气采样/DDR/host边界，不force stable、owner或成功。

`sdr_he`复用2026-11-01已验证测试，重新对当前封印源码运行完整两幅HD：
Gray/Gaussian/前帧HE/F22/C1/v4、完整JPEG逐字节/解码、DDR/SAFE/ACK与drained reset。
`c1_reference_frozen.py`和`protocol_reference`为实际独立C1和RCD4模型；不使用旧v3
`check_main.py`给当前v4签发资格。OB/CG/RX被动解码沿用新版，RT要求0帧。

先以真实短测PASS和父代理给定生产seal SHA运行`freeze.py`，生成测试锁。测试锁必须
通过外部固定`--lock-sha256`启动；它固定生产seal SHA、每项测试/参考SHA和短门SHA。
`launch.ps1 -Mode Preflight`仅compile/elab，两case都PASS后状态为READY_TO_LAUNCH。
确认核心冻结且门禁PASS后才执行同一锁的`-Mode Launch`。每case10800秒，含独立oracle；
最多2并行，正式计划总上限21600秒。所有Start-Process均Hidden。

唯一状态为候选`tmp/extended_20261101/STATE.json`。新聊天15分钟监督任务按此状态
观测，不能接管原SDR任务或操作server。`--status`作一次身份核对；`--resume`只恢复
观察控制器，保留原worker及模型进程，以PID+创建时间采用，不重复启动活跃case。
生产/测试开始结束均逐件SHA，read/atomic自身对Windows共享冲突作7次短重试。
失败和超时保留原目录，不改正在运行的测试、清单或成功条件。

不证明持续FPS、同步曝光、电气裕量、综合、P&R、时序或板级。
