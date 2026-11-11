# TD 原生自动编译服务

2026-11-10 已制作 [v6.6 实测资源准入与连续回传合并包](MEASURED_ADMISSION_V6_6_20261110.md)，待用户安装。
默认 TD CPU 准入目标 50%、内存预算 300 GiB，按近期 CPU 峰值和历史 RSS 峰值决定启动数量。
下文 v6.4/v6.5 部署记录用于追溯，服务器实际版本以新鲜回执确认。

2026-11-10 已制作 [v6.5 连续回传更新包](CONTINUOUS_UPLOAD_V6_5_20261110.md)，待用户在 FinalShell 安装。
该版取消 32 MiB/分钟的回传配额，有积压时连续发送 128 MiB 批次，推送失败后按分钟重试。
安装完成后以服务器 `controller_version` 和 `upload_policy` 回执确认生效。

2026-11-06，camera `9202a973` 的原生 `run.logw` 确认 PHY-5016 会忽略超过 **1000** 的 seed。
本机客户端在发布显式 seed、配置文件和 seed-count 请求前检查 **0–1000**，超限直接报错。
种子数量与种子数值是不同限制。历史回执继续按原值读取，服务器当前部署身份仍按 status 确认。

2026-10-27：[v6.4内存预算更新](MEMORY_BUDGET_V6_4_20261026.md)已由用户FinalShell安装并获新鲜GitHub回执确认：
每个受控综合/种子固定16GiB，按资源决定并发，不固定8/16种子上限；16个4线程种子预算256GiB/64线程。
旧48GiB及max_parallel=8队列提示同样由新策略覆盖，批次不再固定最多24种子。

当前服务器版本2026.10.26-memory16-v6.4，原生线程1/2/4/8/16/32及参数读回能力已登记。
确认时IDLE、无运行/排队任务和回传积压，三路Git无错误，见[部署记录](../evidence/v64-deployment-20261027.md)。
此前合法五种子64线程补测在v6.2上通过；[v6.3线程保护](THREAD_VALUES_V6_3_20261023.md)另有明确验证范围。

2026-10-22 用户要求用本服务替换旧 operator/HA/阶段审计控制链。源码随 Git 发布，
由用户在 build-server 的 FinalShell 手动安装；发布不等于已经部署。
仅依赖服务器现有 Python 3.12.9、Git、SSH 和 TD 2026.2，不需要第三方 Python 包。

2026-10-23 已由用户手动部署并以新鲜GitHub回传确认 `2026.10.23-cancel-v5.1`：
IDLE、资源READY、RUNNING/QUEUED/STARTING均0，4个取消均已终态，既有12个DONE保留，pending_uploads=0。
本版修复取消时shell exec造成的身份误判；部署和取消收尾通过不代表新工程生产P&R资格。
当前更新遇到WAITING_FOR_TD_IDLE或旧任务取消未退出时，按[更新恢复步骤](UPDATE_RECOVERY_20261023.md)操作。
新版包含v4配置能力及
[检查点复用/64线程预算修复](CHECKPOINT_BUDGET_20261022.md)。
后续操作仍以 `controller_version`、`capabilities` 和实际 `resource_policy` 为准。
`2026.10.23-reports-v6` 已于10月23日由用户安装并以新鲜GitHub状态确认：IDLE、资源READY、
无运行/排队任务和回传积压，三路Git无错误，reports_profile=timing-diagnostics-v1。
本版自动补充详细时序、时钟交互、Path Skew、Noise、
器件配置、高扇出、逻辑级数等报告，带来源/哈希/生成状态清单；
v6的Clock Tree实际仅摘要；[Clock Tree v6.1修复](CLOCK_TREE_V6_1_20261023.md)
已安装，并通过服务器共享综合+四种子8线程试跑，645文件下载校验完整。
原生 `-levels`/`-expand_buckets` 自动导出详细树，见[实测记录](../evidence/reports-v61-server-20261023.md)。
摘要、截断或缺组会明确标注；旧版记录见[报告v6说明](REPORTS_V6_20261023.md)。
零问题提示的警告索引修正已随v6.2部署；v6.3也已确认安装，历史说明见[v6.2](WARNING_INDEX_V6_2_20261023.md)。

## 工作方式

- 工程分支和命令分支每 60 秒独立检查。日志/报告有积压时连续回传，空闲时每 60 秒检查。
- `feature/fpga-pipeline` 的 `server/td/projects.json` 登记项目、AL 路径、关注的源目录、线程、种子和目标。
  第一次接入会编译当前工程；随后只有该工程的编译输入或参数变化才自动排队，单改说明不重编。
  新工程在清单增加一项后连同全部源文件推送即可。清单暂时不存在时使用已登记 HDR/JPEG 默认项。
- 每个任务固定一个 Git commit，并有独立工程副本和原生 `*_Runs/syn_1`、`phy_1`。
  多种子只做一次共享综合，再排队展开独立物理种子；也可继续指定已完成任务的检查点。
  工程自带 AL、IP、ADC/SDC、宏和实现策略直接使用；不注入旧 R8 阶段审计，不升级或重新生成 IP。
- full 顺序为综合、布局、布线、bitgen、TD 原生面积/时序报告、原生工程重开；也可指定 synth/route。
  可远程修改综合/实现 Run Properties；目标有 synth/place/route/full，另有检查点接续和只 bitgen。
  没有固定编译时长上限，不因负裕量杀死编译。
  TD 退出状态、自己的阶段完成/错误标记和非空 bit 文件决定流程是否完成；时序结果单列。
- v6.6按实测资源决定并发。TD CPU 目标最多为有效逻辑 CPU 的50%，RSS预算最多300GiB，
  同时检查整机CPU与可用内存。每任务仍选择原生1/2/4/8/16/32线程，附加请求线程总预算默认128。
  每20秒采样、每30秒最多启动一个任务，资源不足保留队列。详见v6.6说明中的余量和短时超限边界。
- SQLite 持久保存队列和已处理命令。控制器重启后接管仍持锁的工作进程；异常退出的任务
  标记 INTERRUPTED，不自动重复耗时编译。需要重试时发新的 build 命令。

## GitHub 通道

| 用途 | 分支 |
|---|---|
| RTL/工程及项目清单 | `feature/fpga-pipeline` |
| 新版 build/cancel/pause/resume 命令 | `codex/td-commands-build-server-simple` |
| 状态、命令回执、日志、报告和 bit | `codex/td-results-build-server-simple` |
| 控制程序源码 | `codex/td-server` |

只使用现有仓库 SSH 权限，不复制、打印或上传 SSH 私钥。GitHub 命令是固定 JSON 动作，
没有任意 shell/Tcl/在线程序更新入口；程序更新由用户手动拉取并运行安装器。
旧的签名控制通道与新版不互相消费命令，安装器明确停用旧控制器后再启用新版。

## FinalShell 安装/更新

已知服务器路径来自本次用户目录清单及环境登记。以下操作不改变工程 checkout 的当前分支或未提交内容：
v6.4已由用户安装；下面保留安装方法，后续维护仍先等待任务空闲。Git方式需确认目标版本已发布到程序分支。

```bash
(
set -e
set -o pipefail
cd /home/build-user/fpga-source
export GIT_SSH=/home/build-user/td_simple/app/git_ssh.sh
git fetch git@github.com:OWNER/REPOSITORY.git +refs/heads/codex/td-server:refs/td/simple-upgrade
mkdir -p /home/build-user/td_simple/bootstrap
git archive refs/td/simple-upgrade server/td/simple | tar -x -C /home/build-user/td_simple/bootstrap
/home/build-user/opt/python-3.12.9/bin/python3.12 -I -B /home/build-user/td_simple/bootstrap/server/td/simple/install.py --root /home/build-user/td_simple --projects-root /home/build-user/fpga_projects --td-root /home/build-user/TD_Release_2026.2_NL --seed-repo /home/build-user/fpga-source --max-parallel 0 --wait-idle --start
)
```

安装器给旧服务写 STOP/controller_stop/PAUSE，只退出经 PID、启动时间、UID、命令行和目录
核对的旧 guardian/broker/controller/updater；不对 TD 进程使用全局 kill。
已运行的旧 worker 保持运行，新版等待旧 worker 的 lease 释放后才开始新编译。
旧排队任务不自动迁移。旧源码、状态、密钥、DB、bit 和日志均不删除。
只替换本账户 crontab 中旧 supervisor 的自启动项，新增带独立标识的新版 @reboot 项。
也可加 `--no-cron` 保持手动启动；不会修改其他用户、系统服务、TD 或许可证安装。

正常输出为 `TD_SIMPLE_STARTED ... poll=60s publish=60s`。随后查看：

```bash
cat /home/build-user/td_simple/status.json
tail -n 60 /home/build-user/td_simple/service.log
```

目录为 `/home/build-user/td_simple`（程序/状态/上传缓存）和
`/home/build-user/fpga_projects/builds/<job>`（工程/原生 Runs/日志/bit）。
安装器保留必要的本地 TD/license 环境值，供开机自启动使用，不把这些值写入 GitHub 报告。
上述为已安装简版的更新命令，复用现有 SSH，不走 HTTPS 用户名认证，不需要再传校园网密码。
首次安装才加 `--retire-legacy`；首次安装尚无 app/git_ssh.sh 时使用原 SSH 配置 fetch。
`--wait-idle` 先暂停新增准入，已有自动 TD 自然结束前，旧控制器继续每分钟回传。
它不停止 GUI、不取消 TD，也不设编译超时；等待时 Ctrl+C 会恢复原暂停状态。
不加该选项且有任务时，在停控制器前直接拒绝更新。更新保留 SQLite、工程、产物和认证配置。
已手动 pause 的服务更新后仍保持 pause；未暂停的正常恢复调度。
如果遇到 `WAITING_FOR_LEGACY_WORKERS`，看状态中实际旧任务，不删除它们的目录或锁文件。

也可把本轮不含密码的 `td-simple-update-20261026-v6.4.tar.gz` 用 FinalShell 上传到
`/home/build-user/td_simple/bootstrap/`，不用 Git 在线下载；在服务器执行：

```bash
tar -xzf /home/build-user/td_simple/bootstrap/td-simple-update-20261026-v6.4.tar.gz -C /home/build-user/td_simple/bootstrap
bash /home/build-user/td_simple/bootstrap/server/td/simple/apply_update.sh
```

本次更新完成后 `status.json` 中应有 `controller_version: 2026.10.26-memory16-v6.4`，
以及memory_per_job_gib=16、max_parallel=0、parallelism_mode=resource_budget；本次新鲜回执已确认这些字段。
该更新包只有程序，不含校园网/SSH 凭据，已有 network-auth.json 保留。
v2 已完成单种子及4种子共享综合/并发小工程实测；2026-10-22 17:03 已确认用户部署 v3 并补传原始 logw。
后续更新仍由用户手动安装并核对实际回执，不能把源码发布视为服务器更新。

## 断网与回传

用户说明周日到周四夜间会断网约六小时。本服务全天尝试，每次网络调用有短超时，
每分钟重新检查，不依赖对夜间日期边界的解释，也没有超过夜间窗口就过期的命令。
TD 工作进程不等待 GitHub，也不会因断网退出；已接收命令、源、完整日志和产物都先落本地磁盘。

每分钟发布状态、当前日志末尾和已经生成的报告。日志末尾只是实时预览；任务完成后保留并
分块上传完整日志、原生报告、配置快照、完成/错误标记和 bit。大型数据库 DB 留在服务器。
每块最多 8 MiB，每批最多读取 128 MiB 文件内容，以控制内存和单次 Git push 大小。
成功推送后才推进本地游标。有剩余文件且本批已发送数据时立即发送下一批，取消按分钟字节配额。
单次结果 push 最多允许 1800 秒，控制器退出时会终止其 Git 子进程。
网络在 GitHub 已接受 push 后中断也可安全重试，已确认的块不重传。失败或空闲时按 60 秒周期检查。
实际吞吐由出口网络、GitHub 接收速度、本地压缩和文件索引开销共同决定。
当前 `pending_uploads` 表示尚未传完的文件数，长日志可能需要多个轮询周期。

### v3 分阶段原始日志

TD 会在每次 launch_runs 时重用 `phy_1/run.log`。v3 在每次原生阶段结束、下一阶段启动前，
将该 run 的 `.log`、`.logw`、`.msg`、`.messages`、`.warnings`、`.errors` 及工程级消息文件
原样归档到任务的 `stage-logs/{synthesis,placement,routing,bitgen}/`，整目录完成后才可见。
同阶段的原生 `.tcl/.sh/.bat`、`.cfg/.prj/.params/.status` 也保存，保留真实命令、参数及状态；
QoR 建议脚本只作为文件回传，不自动执行或改变工程策略。原生报告和各 seed 子目录递归收集。
阶段归档一经生成不再被下一阶段覆盖；其完整内容在任务仍运行时也按分钟分块上传，
不受当前活动日志的 64 KiB 预览限制。wait_run 保留原生流式输出到连续的 `td.log`，不再使用 -quiet。
DB 仍仅留服务器，bit 仍由正常 bitgen 完成后发布；不增加时序审计或改变实现策略。

失败/取消返回后，worker 另外保存未完成阶段及 terminal 快照；控制器发现已退出的 worker 时
也尝试保留现有日志。强断电、磁盘故障或文件仍变化时只能保留实际落盘内容，不能承诺未写入的数据。
`capture.json` 记录来源、阶段状态、是否早于阶段启动和复制错误；result.log_capture 单列保存结果。
`warnings.csv` 给出可见 WARNING/CRITICAL-WARNING 的文件、行号、代码和原文，
`warning-summary.json` 明示同类消息省略次数。计数是日志出现次数，阶段/终态/控制台可能重复，
不是唯一问题数或 GUI 的警告总数；原始消息伴随文件不假设都是文本，也不改写。

本修复防止控制程序丢失 TD 已输出的消息，不改变 TD 自己的控制台重复警告抑制。
2026-10-22 用户提供的完整 Runs 中，syn_1/run.log 只有 67 行警告，而同目录 run.logw
有 29,538 行警告；因此不能只读 run.log，也不能把它的省略提示当作 logw 同样没有明细。
应优先查看已原样保存的 logw 和警告索引。只有 TD 从未写入任何文件的消息，以及升级前
已被覆盖的阶段日志无法恢复；未与 GUI 清单逐条比对前，warning_inventory_complete 不冒称 true。
升级后，旧任务目录中仍存在的 logw、脚本、参数和状态文件也会自动补传，不需要重新编译；
不会为旧任务伪造分阶段快照或把别的 GUI 工程目录混入其回传。
多种子接续的时序摘要按本轮目标 run 选择，不能用继承的综合 simple.timing 替代物理时序。

## 资源监控和峰值预留

每 20 秒只读采样 `/proc/stat`、`/proc/meminfo`、进程累计 CPU ticks/RSS；不是用 load 冒充 CPU%。
扫描可见进程的父子关系，统计控制器全部 TD 后代及手动 GUI/独立 TD，避免漏掉非主线程创建的子进程。
不读取环境或私钥，不给其他用户进程发信号；被权限隐藏的进程无法保证完整识别。
状态每分钟回传整机 CPU、内存总量/已用/可用、TD 汇总 CPU/RSS、各任务 PID/阶段/占用和排队原因。
每个任务有 `resources.csv` 和分阶段峰值；日志 mtime/字节数与控制器回传时间分别报告。

默认准入策略在服务器 `config.json`，更新命令把最大并发设为 8：

v4 可用 `policy --file policy.json` 远程调整准入参数，持久化覆盖存入 SQLite，重启保留；
状态回显实际策略。v5上限为8任务、32线程/任务、64总线程和RSS300GiB。
旧TD CPU50%和CPU×1.25规则已移除；宿主负载、实际CPU容量与内存检查继续有效。
项目另可设置 `max_parallel`、`priority`、`synth_threads`，详见升级说明。

| 项目 | 默认值 |
|---|---|
| 受控线程总预算 | 请求线程直接相加，最多64；任意满足范围的组合均可 |
| TD 汇总内存目标 | 300 GiB，RSS 保守求和，可能重复计算共享页 |
| 整机 CPU 目标 | 预测占用不超过全机 85%，为其他工作留余量 |
| 宿主内存余量 | 至少 64 GiB，并随全机容量提高至最多 128 GiB |
| 每受控任务 CPU 预留 | 等于请求线程数，不加倍率或历史CPU峰值 |
| 每受控任务内存预留 | v6.4固定16GiB，由全局memory_per_job_gib控制，旧项目提示和历史不抬高预算 |
| 手动 TD | 实际CPU计入宿主预测；每组内存至少32GiB并考虑历史/实际增长，空闲GUI不虚占线程 |

整段任务一直保留未来阶段的预算，不因当前综合/布局/布线某一小阶段空闲就释放并发名额。
新增任务同时检查 TD 总预算、整机外部负载、已有任务未来内存增长、线程和并发数量。
读取可见的 affinity/cgroup 限额，只收紧可用容量，不修改 cgroup 或系统配置。
CPU 首次采样、数据超过 45 秒或采样失败时不准入新任务；已有 TD 继续运行。
历史峰值持久保存在 `resource-history.json`，并学习本服务旧/新原生 run.log 的 memory peak。

依据旧控制器 QUEUE.md 的实测八种子汇总约 96.41 GiB、旧 memory.py 的后续增长保护，
以及本轮主工程进入 GP 前已出现约 9746 MB 的原生日志峰值，冷启动采用更保守的 32 GiB/种子。
这些不是当前 HDR/JPEG 全程峰值证明；v6.4如需调整统一预留，使用policy.memory_per_job_gib；旧--memory-gib只保留请求记录。
8 并发是上限，不是必须填满；手动 GUI 活跃、历史峰值变大或宿主资源不足时会少开。
上述是准入预测，不是内核硬限流；未观测峰值、外部程序突然增长仍可能超出目标。
不会为满足线程/内存预算而强杀、暂停已有TD，也不承诺绝对不会OOM。
Linux 计数与限额语义见[官方 proc 文档](https://docs.kernel.org/filesystems/proc.html)和
[cgroup 文档](https://docs.kernel.org/admin-guide/cgroup-v2.html)。

## Run Properties 和不重跑的阶段接续

详见 [RUN_CONTROL.md](RUN_CONTROL.md)：直接通过 GitHub 请求修改 syn_1/phy_1 的原生 Property，
支持只综合、综合到布局/布线、完整 bitgen，也可在现有检查点上只跑后续阶段。
没有阶段审计或额外的正确性门禁。必要的 native 完成/错误标记、退出码和 DB 存在性检查保留。

## 校园网自动认证

已通过只读 GET 和 pageInfo 查询确认实际门户是
`http://portal.example.invalid:8080/eportal/`，登录接口为 `InterFace.do?method=login`。
按该门户实际 login_bch.js/security.js 实现双重 URL 编码和 RSA 密码字段；使用虚构测试密码
与门户 JavaScript 对照得到相同密文。没有注销或重登本机 Wi-Fi，没有发送真人账号密码。

如使用本次另行交付的本地私有包，先在 FinalShell 创建私有目录：

```bash
umask 077
mkdir -p /home/build-user/td_simple/bootstrap
chmod 700 /home/build-user/td_simple /home/build-user/td_simple/bootstrap
```

把 `td-simple-private-20261022.tar.gz` 上传到 `/home/build-user/td_simple/bootstrap/`，然后执行：

```bash
tar -xzf /home/build-user/td_simple/bootstrap/td-simple-private-20261022.tar.gz -C /home/build-user/td_simple/bootstrap
/home/build-user/opt/python-3.12.9/bin/python3.12 -I -B /home/build-user/td_simple/bootstrap/private-install/server/td/simple/install.py --td-root /home/build-user/TD_Release_2026.2_NL --seed-repo /home/build-user/fpga-source --network-auth-file /home/build-user/td_simple/bootstrap/private-install/network-auth.json --retire-legacy --start
```

私有包已经带本地认证配置，安装器自动接入，无需再次输入账号密码。
私有包和原始凭据只放本地 Git 忽略的交付目录，不上传到 GitHub。GitHub 保留的是不含凭据的程序源码。

不使用私有包时，在服务器执行一次，按提示输入账号、隐藏的密码和服务名（通常直接回车）：

```bash
/home/build-user/opt/python-3.12.9/bin/python3.12 -I -B /home/build-user/td_simple/app/network.py configure --root /home/build-user/td_simple
/home/build-user/opt/python-3.12.9/bin/python3.12 -I -B /home/build-user/td_simple/app/network.py check --root /home/build-user/td_simple
```

认证信息只存 `/home/build-user/td_simple/network-auth.json`，权限 600，既不进入工程归档，也不进入报告。
未配置时自动认证关闭，正常 Git 轮询照常运行。启用后每分钟探测；已联网时不提交登录。
断网后从服务器自己的门户跳转取得 query/MAC/IP，再向固定校园网门户认证。
不使用本机成功页 userIndex，不发送注销请求，不修改网卡、Wi-Fi、路由、DNS 或系统配置。
遇到验证码/短信提示则报告需要人工处理；校园网网关不可达或学校强制断网时保留任务、继续按分钟重试。
服务器实际认证与断网恢复尚须用户配置凭据后验收，当前不宣称已经自动重连成功。

## 本地使用

普通工程更新只需要在开发分支提交并 push。需要主动重编/改线程/种子时，从本地仓库根运行：

```powershell
./server/td/td.ps1 build --project hdr_jpeg --target full --seeds 1 --threads 8
./server/td/td.ps1 status
./server/td/td.ps1 receipt --request <命令ID>
./server/td/td.ps1 receive --job <任务ID> --output server/td/local/download/<任务ID>
./server/td/td.ps1 cancel --job <准确任务ID>
./server/td/td.ps1 pause
./server/td/td.ps1 resume
```

build 默认绑定本地 HEAD，必须先把工程提交推送到 GitHub。命令 ID 会在网络发送前保存并显示；
发送结果未知时使用同一组参数和 `--request-id <原ID>` 重试，不创建重复任务。
pause 只停止新任务启动；cancel 只作用于准确任务 ID。status 显示回传年龄，断网时为最后已知状态。
完整日志/报告按块和整文件校验后重建。bitgen DONE 与时序 NEGATIVE 可同时出现；板级一直是 NOT_RUN。
旧客户端只保留 `td.ps1 legacy ...` 作为历史兼容入口，新服务不使用它。

## 检查与清理

定向测试覆盖真实本地 Git 传输、队列去重、重启接管、断网/未知 push 结果、完整日志续传、
TD Tcl 原生阶段失败、负时序分开报告及校园网认证编码。测试不启动生产 FPGA 编译。
运行：`python -B -m unittest discover -s server/td/tests -p "test_simple*.py" -v`。

2026-10-22 本轮 61 项定向测试 PASS，包含24排队/8并发、共享综合、资源增长、接续、断网和bit收发。
指定 TD 6.2.3.210850 的隔离单寄存器工程实测：只综合、复用综合继续 P&R、routed DB 只 bitgen、
修改 route 属性后仅 reroute 均正常完成。后两者实际未 launch 综合/布局；gate/place DB 保持相同字节。
bitgen 产生 4,850,262 字节 bit；初始缺 I/O 约束的探针曾正常报 BIT-8123，未关闭该检查或伪造成功。
这些只验证控制流程，不证明生产工程物理时序、资源峰值或实板通过。
门户 RSA 已与公开的实际 security.js 使用虚构密码对照一致；未向门户发送真人凭据。
初版已经由用户实际安装并收到真实 TD 综合、布局及每分钟回传；本轮增强版仍须用户下午手动更新。
小工程通过不证明生产 HDR/JPEG 的最终 P&R/STA/bitgen 或实板通过。校园网夜间自动认证仍未实测。

服务器目录归类与只读清点见 [CLEANUP.md](CLEANUP.md)。没有部署/验收回执前，不把旧控制器写成已退役。
