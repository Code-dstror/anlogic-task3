# v6.6 实测资源准入与连续回传

版本为 `2026.11.10-measured-admission-v6.6`。此更新包含 v6.5 的全部连续回传改动，
可从已安装的 v6.4 或 v6.5 一次升级。源码位于维护分支 `codex/td-server-upload-20261110`。

## 数据依据

固定结果提交 `SOURCE_COMMIT` 的125份四线程物理任务资源CSV，
共39226条采样，已逐块及逐文件核验SHA256。包含120个已完成任务和5个取消任务的已记录片段。

| 阶段 | CPU中位数，等效核 | CPU95分位 | CPU99分位 | CPU最大值 | RSS最大值，GiB |
|---|---:|---:|---:|---:|---:|
| 布局 | 1.551 | 3.452 | 4.543 | 5.039 | 7.036 |
| 布线 | 1.101 | 1.833 | 2.581 | 3.724 | 9.257 |
| bitgen | 1.418 | 3.775 | 4.053 | 4.263 | 4.983 |
| 报告 | 1.219 | 2.049 | 2.462 | 2.771 | 7.030 |

数据表明4线程设置与实际CPU使用有明显差别，布局和bitgen也有短时峰值。
新策略保留启动及运行余量，用实测资源控制并发。

## 新准入规则

- TD CPU目标为有效逻辑CPU的50%。build-server当前有效CPU为112，对应56个等效核。
- 对连续有效采样的运行任务，预留最近3个采样的CPU峰值乘1.25，且至少为请求线程数的一半、至少1核。
  新启动、采样不足或缺少进程组的任务，按请求线程数乘1.25预留。
- 历史内存峰值乘1.25后向上取整，已知任务至少预留12GiB；无历史的任务至少16GiB。
  历史峰值来自服务端已有采样及TD原生日志。当前RSS超过预留时，以实际占用继续计算。
- 请求线程总预算由默认64提升至128，单任务原生线程选项保留。每20秒采样、每30秒最多启动一个任务。
  满足当前数据特征的四线程任务可达到25个并发；实际数量随任务阶段和主机负载调整。
- TD总内存准入预算上限300GiB。继续同时检查宿主机可用内存、cgroup余量，预留至少64GiB及既有整机比例余量。
- 全机CPU的预测使用率默认不超过85%。非TD任务和手动TD进程均纳入评估。
  手动TD进程至少预留32GiB，CPU采样不足时暂缓新任务。
- CPU或内存超预算、整机余量不足、遥测缺失或过期时，队列显示具体等待原因。调度下一轮采样后重新评估。

这些是启动准入目标。已有任务的阶段切换或其他用户突然加负载，可能使实际占用短时超过目标。
此时停止启动后续任务，等待负载回落，已有工作继续运行。共享build-user账户上的其他程序也会影响实际占用。
内存单位沿用现有控制器的GiB，300GiB约为322GB。

## 网速设置

取消32MiB/分钟配额，有积压时连续发送，每批最多读取128MiB文件内容，每块8MiB。
批次之间无固定等待，结果push超时为1800秒，保留分块SHA256、成功确认后记账及失败续传。
空闲或失败时按60秒周期检查。实际速率受出口网络、GitHub及本地处理开销影响。

## 日志回放

使用上述120个完整任务，按三种确定性顺序重放，每20秒刷新资源遥测，每10秒执行一次离线准入检查，
覆盖30秒启动间隔及两次采样之间的启动决策。
调度决策直接调用新 `ResourceMonitor.allows`，每个场景都从空队列运行至全部完成。

| 场景 | 最大并发 | TD CPU峰值范围 | RSS峰值范围，GiB |
|---|---:|---:|---:|
| 外部CPU占用0核，内存余量充足 | 25 | 41.83%–44.13% | 206.31–208.49 |
| 其他任务占用60核 | 16 | 27.62%–28.57% | 132.72–133.49 |
| 可用于新增TD的初始内存余量150GiB | 12 | 28.92%–30.13% | 105.30–106.24 |

9组回放均无TD CPU超过50%或RSS超过300GiB的采样。回放假设已有同工程历史内存记录，
且不模拟资源竞争对任务耗时的影响。实际服务器并发效率需部署后观察。
`../analyze_admission.py` 可从固定结果缓存重现分析。交付目录附 `RESOURCE_REPLAY.json`，记录文件身份与结果。

## 回归验证

本地测试覆盖134项，最终全部通过。

| 模块 | 项数 |
|---|---:|
| 控制器、任务生命周期、连续回传 | 51 |
| 资源采样、准入、安装保护与迁移 | 39 |
| 客户端配置 | 18 |
| 检查点与旧预算兼容 | 7 |
| 调度与原生线程配置 | 11 |
| 完整报告与大文件续传 | 8 |

旧测试中的64线程和20秒启动间隔预期已按本次行为变化调整，旧版本兼容测试仍显式使用旧策略。
首轮控制器回归中既有失败任务归档用例曾出现一次ERROR，单独复查及最终完整51项回归通过，
本次未修改归档实现。30秒启动配置变更后，资源、迁移及实际dispatch入口已定向复验。
测试和日志回放在Windows本地完成，服务器Linux部署和实际吞吐验证待用户安装。

## 安装与正在运行的任务

将 `td-simple-update-20261110-v6.6.tar.gz` 和 `.sha256` 上传到 `/home/build-user/td_simple/bootstrap/`。
先执行校验。

```bash
cd /home/build-user/td_simple/bootstrap
sha256sum -c td-simple-update-20261110-v6.6.tar.gz.sha256
```

显示OK后执行。

```bash
tar -xzf td-simple-update-20261110-v6.6.tar.gz
bash server/td/simple/apply_update.sh
```

安装时暂缓新任务启动，等待当前TD任务自然结束，旧服务在等待期间继续回传。
然后重启控制器，恢复原调度状态和队列。SQLite、上传进度、产物及服务器已有身份包装器保留。
等待阶段按Ctrl+C会恢复进入安装前的调度状态。等待时保持FinalShell会话连接。

旧版默认64线程、16GiB预算升级为128线程、12GiB下限。
自定义更低线程预算或更高内存下限会保留，因此保留这些设置的服务器可能达不到25路。
更新后的 `status.json` 应显示以下字段。

```text
controller_version = 2026.11.10-measured-admission-v6.6
resource_policy.cpu_budget_mode = recent_peak_with_headroom
resource_policy.memory_budget_mode = historical_peak_with_floor
resource_policy.max_td_cpu_percent = 50
resource_policy.max_td_memory_gib = 300
resource_policy.max_total_threads = 128
resource_policy.start_interval_seconds = 30
upload_policy.mode = continuous
upload_policy.rate_limit_bytes_per_second = null
```

可用以下命令核对。

```bash
grep -E 'controller_version|cpu_budget_mode|memory_budget_mode|max_td_cpu_percent|max_total_threads|continuous' /home/build-user/td_simple/status.json
tail -n 20 /home/build-user/td_simple/service.log
```
