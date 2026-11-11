# v5更新等待与旧任务取消修复

2026-10-23，修订程序版本 `2026.10.23-cancel-v5.1`。包括v5检查点路径修复、任意组合64线程预算和v4配置能力。

## 本次实际状态

旧v5包的24个tar条目未设置mtime，默认为0，因此GNU tar报告1970年旧时间戳。
警告不代表文件内容损坏，也没有阻止解压。元数据修正版逐文件内容/哈希与原v5相同。
本次v5.1包设置正常mtime，并包含下面的取消修复，应使用v5.1更新程序。

`WAITING_FOR_TD_IDLE`表示安装器尚在替换程序之前，停止新增准入并等现有worker退出；
Ctrl+C由安装器恢复先前pause值后退出，Python显示KeyboardInterrupt。
已通过新鲜回传核实Ctrl+C后旧v3控制器仍正常运行、调度恢复、日志继续回传。

用户随后明确授权取消所有现有编译。4条准确job cancel请求均已被服务器ACCEPTED，
排队种子137和种子11已CANCELLED；种子11此前已完成全部原生阶段，其bit/报告保留。
种子71和88仍曾保持RUNNING，不能把ACCEPTED当作进程已经退出。
实际最新终态保存在本地 `server/td/local/simple-update-20261022/cancel-for-update-*.json`。

## 取消修复

旧runner用PID、启动时间、UID和完整argv共同判断TD进程身份。
启动shell在exec同一TD进程后argv会改变，原检查可能返回false，取消不发信号而继续等TD自然结束。
v5.1专用会话终止逻辑只固定PID/启动时间/UID，并核对PGID等于原启动PID；
合法exec不再阻止取消，PID复用或另一个进程组仍会拒绝。
SIGTERM后保留10秒退出宽限，必要时只向该已核对会话发送SIGKILL。
不修改其它监护进程的严格身份检查，不全局pkill，不触碰手动GUI和已完成任务。

`stop_jobs.py`用于解锁旧runner已接受但未实际完成的取消：仅处理明确列出的受控job，
核对其td-process.json、同一job的build.tcl、PID/UID/启动时间/进程组后停止该TD会话。
它不删除文件、不改写DB终态；原worker负责保存现有日志/报告并记录CANCELLED。

## 用户在FinalShell执行

将 `td-simple-update-20261023-v5.1.tar.gz` 上传到 `/home/build-user/td_simple/bootstrap/` 后，以build-user执行：

```bash
tar -xzf /home/build-user/td_simple/bootstrap/td-simple-update-20261023-v5.1.tar.gz -C /home/build-user/td_simple/bootstrap
/home/build-user/opt/python-3.12.9/bin/python3.12 -I -B /home/build-user/td_simple/bootstrap/server/td/simple/stop_jobs.py --root /home/build-user/td_simple --jobs manual-hdr-high8-native-20261022-s71-05e8c02c2f87eecf-s71 manual-hdr-high8-native-20261022-s88-9428296489b43612-s88
bash /home/build-user/td_simple/bootstrap/server/td/simple/apply_update.sh
```

若目标已完成或已退出，停止工具会跳过。日志归档期间安装器仍可能短暂显示WAITING_FOR_TD_IDLE。
这些命令使用当前已授权的准确任务ID，不作用于其它工程；已经完成的bit、DB、报告和日志全部保留。
安装完成应看到 `Controller: 2026.10.23-cancel-v5.1`；本地共享status还需确认新鲜版本回执与RUNNING/QUEUED为0。
本机没有build-server SSH执行通道，因此旧进程的这一步停止需要用户在FinalShell执行。

## 本次验证

7项定向测试覆盖合法exec、PID复用/UID变化、进程组不匹配、退出竞争、10秒宽限后的同会话终止，
及停止工具保留已有bit/终态。
测试不启动或终止真实TD，也不触碰生产RTL。服务器v5.1部署和旧进程实际停止仍以回执为准。
