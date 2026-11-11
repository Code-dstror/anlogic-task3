# TD 远程运行配置升级

2026-10-23更正：原生线程值为1/2/4/8/16/32，任意合法组合直接求和<=64。
12/20/24会退回auto，不能以请求被接受认定生效；[v6.3](THREAD_VALUES_V6_3_20261023.md)补校验与读回。
v6.3已由用户安装并获新鲜回执确认，见[部署记录](../evidence/v63-deployment-20261023.md)；本次不追加编译。

本页保留v4配置能力说明。当前交付已更新为v5，优先使用
[检查点复用与64线程预算修复](CHECKPOINT_BUDGET_20261022.md)及v5更新包；
下面v4的CPU50%/增长系数、综合4并发与旧policy示例不再适用于v5。

2026-10-22。交付版本 `2026.10.22-run-config-v4`，供用户10月23日在 FinalShell 手动更新。
服务器最后已知版本为 `2026.10.22-stage-logs-v3`；本次开发未部署、未提交新编译，未调整正在运行的三组工程。
只读取了用户指定的“去除 LZ77 工程”聊天，调研依据为当前 simple 源码和本机 TD 2026.2 官方命令/配置。

## 调研结果与改动

| 项目 | v3 的行为或缺口 | v4 的处理 |
|---|---|---|
| 每任务线程 | 客户端、清单校验、服务器策略均硬编码1–8 | 统一支持1–32；旧默认8迁移为32，保留用户更低限制；总线程仍最多64 |
| 综合与物理线程 | 共享综合使用首个种子的线程数 | `synth_threads` 可单独指定，物理线程仍由 `threads`/`seed_threads` 指定 |
| 手动build默认值 | 不带可选参数也发送full/8线程/seed1，覆盖项目清单 | 只发送显式覆盖，未指定时继承清单；continue仍默认父任务单种子 |
| 原生策略 | 能改单项属性，但没有策略选择字段 | `td_strategies` 通过TD原生 `set_strategy` 选择综合/物理策略，再设置显式属性 |
| 恢复默认 | 旧AL和父任务中的覆写可能残留 | `td_reset` 显式清除指定Run旧覆写，再应用策略和本次属性 |
| 多值Run属性 | 只接受单个标量 | 支持标量列表，按Tcl list传递；值作为数据转义，不作为命令执行 |
| 配置文件 | 只能为单项Run Properties传JSON | `--config` 一次传运行配置，命令行显式值优先；清单也支持相同运行字段 |
| 项目并发 | 只有全局并发上限 | 每配置可设置 `max_parallel`，共享综合和物理任务计入同项目并发 |
| 启动顺序 | 仅按入队时间 | `priority` 高值优先，同优先级按入队顺序；不会抢占已有TD |
| 队首资源不足 | 立即返回，后续小任务也无法启动 | 跳过暂不可启动的任务，允许后续符合资源预算的任务启动 |
| 综合槽占满 | 复用综合的P&R候选也可能被挡住 | 只有需要重新综合的候选才检查综合槽 |
| 全局准入策略 | 只能服务器改config.json并重启 | `policy --file` 远程持久化更新允许的准入字段，回执和status回显 |
| 配置生效与兼容 | 无功能能力表；不支持的新字段可能导致轮询报错或永久等待 | status公布 `capabilities`；新版客户端先核对能力和快照年龄；每job回显配置、等待原因 |
| 修改调度设置 | 整个project参与编译指纹，单改排队属性也会重新编译 | 优先级、项目并发和内存预留不进入编译输入指纹；新字段缺省保持旧身份 |

源码、顶层、宏、IP、源清单、SDC/ADC、器件和已有AL运行属性本来就可以通过Git提交远程更新。
它们不需要再逐项做成控制器命令；编译输入变化使用新build，不能用旧检查点冒充新输入。
自动化继续使用各工程独立的 `syn_1`/`phy_1`。自定义多个Run的工程先在AL中准备对应自动化入口。
远程不接受shell/Tcl钩子，内部多种子由外部持久队列替代；TD安装位置、许可证和网络认证仍由服务器本地管理。
没有新增固定编译超时、强杀负时序任务或自动重试失败编译的策略。

## 配置示例

将以下对象保存为本地JSON文件，通过 `--config` 发送；不要为了试用而修改当前正式项目清单。

```json
{
  "target": "full",
  "threads": 32,
  "synth_threads": 16,
  "seeds": [1],
  "priority": 100,
  "max_parallel": 1,
  "memory_gib": 64,
  "td_reset": ["syn_1", "phy_1"],
  "td_strategies": {
    "syn_1": "RuntimeOptimize",
    "phy_1": "RuntimeOptimize"
  },
  "td_options": {
    "phy_1": {"route": {"fix_hold": "on"}}
  }
}
```

```powershell
./server/td/td.ps1 build --project hdr_jpeg --config fast32.json
./server/td/td.ps1 build --project hdr_jpeg --config fast32.json --threads 16
./server/td/td.ps1 continue --job <父任务ID> --config route-change.json
```

上述命令会创建编译任务，只有用户要求编译时才执行。配置名称不代表耗时承诺。
32线程是TD请求值，不保证所有阶段用满；空闲的手动GUI仍按既有未知TD规则预留资源。
高力度六种子可使用 `threads: 8`、`seeds: [1,11,71,88,101,137]`、`max_parallel: 4`。
综合策略不同仍使用独立综合；相同配置的多种子只共享一次综合。

远程准入示例 `policy.json`：

```json
{
  "max_parallel": 8,
  "max_threads_per_job": 32,
  "max_total_threads": 64,
  "max_synth_parallel": 4,
  "max_cpu_percent": 50,
  "max_td_memory_gib": 300
}
```

```powershell
./server/td/td.ps1 policy --file policy.json
./server/td/td.ps1 receipt --request <请求ID>
./server/td/td.ps1 status
```

policy只调整后续准入，不暂停、取消或修改运行中的TD。CPU50%/RSS300GiB、8任务和64总线程仍为上限。
`priority` 范围为-100至100，默认0；项目 `max_parallel` 为1至8。
其他可调policy字段包括综合并发、整机CPU目标、最小空闲内存、任务内存预留和CPU/内存增长系数；
完整允许字段和范围集中在 `common.py` 的 `POLICY_LIMITS`，并在status能力表公开字段名。
调度配置在任务入队时固定，修改清单不会暗改已排队或运行的任务；需要另一套参数时发新的明确请求。
`ACCEPTED` 只代表请求被接收；实际AL、native Runs、build.tcl、日志和结果决定运行状态。
TD对某些拼写错误可能不报错，参数读回与日志仍需按所选TD版本判断，不能把接收成功说成算法已生效。
原生检查已证明，`set_strategy` 切回默认仍保留先前显式属性，且故意拼错的属性可以原样set/get；
因此本版没有增加会误判有效性的通用“读回成功即通过”检查。恢复默认需要显式 `td_reset`。
原生命令依据：本仓库官方TD2026.2 [SWUG105](../../../references/vendor/安路科技_TD_技术文档/2026.2/SWUG/SWUG105_TCL_Command_User_Guide.pdf) 的 `set_strategy`（物理第35页）；
实际运行以本机6.2.3.210850隔离工程探测为准。

## FinalShell 更新

将本地交付包 `td-simple-update-20261022-v4.tar.gz` 上传至 `/home/build-user/td_simple/bootstrap/`。
在服务器以build-user用户执行：

```bash
tar -xzf /home/build-user/td_simple/bootstrap/td-simple-update-20261022-v4.tar.gz -C /home/build-user/td_simple/bootstrap
bash /home/build-user/td_simple/bootstrap/server/td/simple/apply_update.sh
```

安装器先停止新增准入，等待现有自动任务自然完成，期间旧控制器继续回传日志。
更新保留认证、SQLite队列、资源历史、工程、DB、bit和日志，手动GUI不关闭。
若等待过程中按Ctrl+C，恢复原暂停状态；更新后原已pause的服务仍保持pause。
包内不含校园网或SSH凭据，无需重新输入密码；不要上传以前的私有初装包覆盖现程序。

确认 `status.json` 的 `controller_version` 为 `2026.10.22-run-config-v4`，
并在本地 `td.ps1 status` 中看到新鲜快照、`capabilities` 和有效 `resource_policy`。
程序更新不会把当前8线程任务自动改成32线程，也不会自动追加快速/默认/高力度编译。

## 验证状态

本机TD6.2.3.210850隔离工程仅配置/关闭/重开检查PASS：默认布局effort恢复medium、
RuntimeOptimize/TimingHigh策略可设、显式route参数可覆盖策略并持久保存、综合32线程/物理8线程分别保存。
探测未调用 `launch_runs`，不启动综合/P&R。原始记录保留于本地
`server/td/local/run-config-v4-probe/strategy.log` 和 `reset-verified.log`。
指定Python3.12.9运行 `-B -m unittest discover -s server/td/tests -p "test_simple*.py" -v`：
105项PASS，约96秒。覆盖客户端配置/兼容、调度/policy、指纹迁移、原生脚本/检查点、日志与本地Git成果收发。
其中29项为本次新增定向用例。测试使用本地Git和模拟TD，不向服务器派发任务。
生产RTL仿真、综合、P&R、最终STA、bitgen、板级：NOT_RUN；服务器v4部署：NOT_RUN。
