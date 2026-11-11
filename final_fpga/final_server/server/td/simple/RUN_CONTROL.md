# 远程 Run Properties 与 TD 阶段接续

v6.6 已准备 [实测资源准入更新](MEASURED_ADMISSION_V6_6_20261110.md)，部署后默认请求线程总预算为128，
同时受TD CPU50%、内存300GiB及整机余量约束。以下64线程等数字属于对应版本的历史行为。

2026-10-23更正：原生线程值为1/2/4/8/16/32，任意合法组合直接求和<=64。
12/20/24会退回auto，不能以请求被接受认定生效；[v6.3](THREAD_VALUES_V6_3_20261023.md)补校验与读回。
v6.3已由用户安装并获新鲜回执确认，见[部署记录](../evidence/v63-deployment-20261023.md)；本次不追加编译。

本地统一入口 `server/td/td.ps1`；代码在 GitHub，TD 在 build-server 正常调用原生 AL/Runs。
2026-10-22 17:03 已确认用户部署分阶段日志 v3；之后实际版本和任务状态仍以共享入口的回传为准。
v5已交付32线程上限、策略/默认恢复、配置文件及调度入口，并修复检查点路径比较与64线程预算，详见
[检查点/预算升级](CHECKPOINT_BUDGET_20261022.md)及[配置说明](CONFIG_UPGRADE_20261022.md)。当前v6.3已确认安装，实际线程合法值见首段。

## 直接改 Run Properties

`server/td/projects.json` 每个工程可加 `td_options`；也可用一次 build/continue 请求覆盖属性，
不必为了修改综合/实现参数先在 GUI 保存 AL。以下文件内容是 `--td-options` 接受的 JSON：

```json
{
  "syn_1": {
    "gate": {"map_mode": "area_prior", "pack_effort": "high"},
    "rtl": {"min_control_set": 2}
  },
  "phy_1": {
    "place": {"effort": "high", "logic_level_opt": "off"},
    "route": {"fix_hold": "high", "post_route_opt": "medium"},
    "bitgen": {"compress": "off"}
  }
}
```

在工程清单中把该对象作为 `td_options` 值；命令行则把它存为独立 JSON 文件，例如 `td-options.json`：

```powershell
./server/td/td.ps1 build --project hdr_jpeg --target full --threads 8 --td-options td-options.json
```

控制脚本在开始编译前调用 TD 自己的 `set_param -run <run> <section> <name> <value>`，
实际修改综合/实现属性；随后只执行 TD 自带的 launch_runs/wait_run 流程。
未指定属性沿用工程已有值；continue 的属性覆盖会合并父任务已有属性。
原生 AL、Runs 的 .prj/.cfg、执行 Tcl、属性设置日志均回传，便于确认实际设置。
参数名和值按服务器当前 TD 2026.2 的 GUI/文档填写；不能把旧版参数表当成新版保证。
TD 的 set_param 对部分拼写错误不报错，因此“命令接收”不等于该参数对算法有效。
线程/种子用独立参数配置，不能通过 td_options 绕过每任务线程限制（v3为8，v4为32）和64线程总预算，
也不接受 tcl_beforestep 等任意命令钩子。每个外部种子关闭 TD 内部多种子再展开，避免重复并发。

## 新工程从哪里开始

| 命令目标 | 实际执行 |
|---|---|
| build --target synth | 综合，保存 native gate DB 和原生报告 |
| build --target place | 综合、布局，保存 place DB |
| build --target route | 综合、布局、布线，保存 pr DB |
| build --target full | 综合、布局、布线、bitgen，回传 bit |

build 是新构建；工程源码、ADC/SDC 或生产输入改变时使用它。
纯控制器/文档 push 不改变工程输入，不会额外触发当前单种子工程重编。

## 已完成的工程继续，不从头开始

```powershell
./server/td/td.ps1 build --project hdr_jpeg --target synth --threads 8
./server/td/td.ps1 status
./server/td/td.ps1 continue --job <已完成综合任务ID> --target route --threads 8
./server/td/td.ps1 continue --job <已完成布线任务ID> --target bitgen
```

也可从综合一次直接接 full：

```powershell
./server/td/td.ps1 continue --job <已完成综合任务ID> --target full --seed-count 24 --threads 8
```

这会复用一次综合检查点，24 个独立物理种子持久排队，最多 8 个并发，不重新综合 24 次。
16 个种子用 `--seed-count 16`，8 个种子用 `--seed-count 8`；每个种子有独立 AL/Runs。
`--seeds 2 5 9` 可选任意种子编号；`--seed-threads 2:4 5:8` 可逐种子覆盖默认线程。
一批最多 24 个，不是整个持久队列只能存 24 个。资源不够时并发自动少于 8。
直接 build full/route/place 多种子也会自动创建一次共享综合，再展开物理种子；回执中的 synthesis_job
指明该前置任务。综合未完成时物理种子只排队，不复制正在写的 DB；综合失败时不启动物理种子。
综合线程数采用首个种子的配置；已有综合任务则用 continue，无需创建新的共享综合。

continue 默认只接续指定父任务的那个种子，不会意外扩展成父项目清单中的全部种子。
父任务必须已停止，完成阶段必须有真实原生标记和非空 DB；运行中的 DB 不复制。
部分失败任务只要已有完成的综合/布局检查点，也可以从其后接续。
父任务目录及 DB 不修改；复制到新任务独立目录后，由 TD 自己 reset/rollback 必要阶段。
v5先规范任务副本AL中的注册文件/IncludeDir路径，与原生综合快照一致，
修复等价路径导致的PRJ-8817；不编辑gate DB、综合快照或完成标记，也不强制跳过TD新鲜度检查。
复制的旧 bit 不作为新产物；只有本次 bitgen 完成才发布新 bit。
阶段显示 REUSED 与本轮 DONE 分开，`reused-from.json` 指明来源，继承报告标记 inherited_from。
继续命令使用父任务固定源码，不偷偷替换成 GitHub 最新 HEAD；源码/ADC/SDC 改了应新 build。

## 属性改动只重跑必要阶段

```powershell
./server/td/td.ps1 continue --job <已布线任务ID> --target full --td-options route-only.json
```

route-only.json 仅含 `{"phy_1":{"route":{"post_route_opt":"high"}}}` 时，复用综合和布局，只重跑布线/bitgen。
改变布局参数或 seed 时，保留综合，重新布局/布线；改变综合参数时，必须重新综合。
只修改 bitgen 参数时，复用 routed DB，只重新 bitgen。
bitgen-only 不接受会使已有布局/布线失效的修改，避免拿旧结果伪装新配置成功。
普通 full 接续会自动从最早受影响阶段重跑；没有每次都 reset syn_1 的行为。

## 日志、报告和 bit

每分钟回传当前主日志和 syn_1/phy_1 原生日志末尾、已经产生的报告、原生属性/配置、
面积/时序/例外/时钟报告、完成/错误标记、资源采样与阶段进度；不是只等编译结束才上报。
完整日志最终分块续传；运行中的末尾预览为每日志 64 KiB。DB 保留服务器供接续，不传到 GitHub。
v3 在阶段切换前保存不可覆盖的 stage-logs，已经结束的阶段日志可在下一阶段运行中完整续传；
原始 .logw/消息伴随文件一并保存，失败/取消另留终态快照，warnings.csv 提供可见警告的文件/行号。
run.log 省略的重复警告可能仍完整保存在 run.logw，应优先读原始 logw；TD 从未落盘的消息才无法恢复。
CSV 计数不是唯一警告数或 GUI 总数，不声称已经逐条对齐 GUI 消息清单。
本轮 bitgen DONE 后 bit 自动进入回传；大文件每轮 32 MiB 预算，积压时按分钟继续。
没有数据时不伪造报告；网络断开时本地保存，恢复后补传。“每分钟”不是逐行即时视频式推流。
失败或取消时上传已经落盘的日志/报告；尚未生成的 routed STA 或 bit 不会伪造。

```powershell
./server/td/td.ps1 receive --job <任务ID> --output server/td/local/download/<任务ID>
```

阶段完成、时序负裕量、bitgen 和实板分别报告；这里没有增加任何阶段审计。
