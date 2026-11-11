# 历史 legacy：固定客户端操作

仅在用户明确选择旧签名栈/历史复现时读取。当前 simple 服务使用 `td.ps1 status`、
`receipt --request`、`receive --job` 和 `continue --job`，没有 activity/prepare/签发步骤。
当前操作见 [RUN_CONTROL.md](../../../../server/td/simple/RUN_CONTROL.md)，不混用下面的 unit/attempt 或旧结果分支。

先从项目的 `ENVIRONMENT.local.md` 填写三个任务专用变量，路径必须是本机实际值。不要寻找或读取私钥。

```powershell
$TdControlPython = '<ENVIRONMENT.local.md 中的 Python>'
$TdControlClient = '<ENVIRONMENT.local.md 中的 PINNED_CLIENT>'
$TdControlRepo = '<仓库绝对路径>'
```

下文每条以 `& $TdControlPython -X utf8 -I -B $TdControlClient` 开头，都需 `--repo $TdControlRepo`；server默认server3，多服务器时显式`--server`并核对登记。

## 查询、日志和轮询

```powershell
& $TdControlPython -X utf8 -I -B $TdControlClient status --json --repo $TdControlRepo
& $TdControlPython -X utf8 -I -B $TdControlClient control status --repo $TdControlRepo
& $TdControlPython -X utf8 -I -B $TdControlClient status --request '<SIGNED_REQUEST_SENT 的ID>' --json --repo $TdControlRepo
& $TdControlPython -X utf8 -I -B $TdControlClient control logs --unit '<s_或p_加32位hex>' --phase route --kib 64 --repo $TdControlRepo
```

`status`直接读取GitHub已有回传；`control status`签发一次只读快照请求。首次V2指令验收可用后者，不重跑旧工程。`NOT_YET_PUBLISHED`表示回执尚未上传，不是指令已失败。control会先发布20分钟/30秒activity租约；不要把“发布成功”当作服务器执行成功。

日志phase：`sync/synth/preflight/place/route/report/reopen/native_synth/native_physical`，上限256KiB。综合queue日志可能只见launch_runs，可用native_synth读取固定syn_1/run.log。直接Tcl物理流程没有phy_1/run.log时，native_physical会失败；用实际阶段place/route/report/reopen，route已做真实远程验收。由任务记录推导路径，不接受任意路径。

回执的`result`可能是JSON字符串，先反序列化再摘要；不要把十几万字的完整status塞进上下文。示例：

```powershell
$TdReceipt = & $TdControlPython -X utf8 -I -B $TdControlClient status --request '<request ID>' --json --repo $TdControlRepo | ConvertFrom-Json
$TdResult = if ($TdReceipt.result -is [string]) { $TdReceipt.result | ConvertFrom-Json } else { $TdReceipt.result }
$TdResult | Select-Object time,unit_counts,admission,pending_uploads,cpu_load | ConvertTo-Json -Depth 4
```

```powershell
& $TdControlPython -X utf8 -I -B $TdControlClient control activity --seconds 30 --minutes 20 --repo $TdControlRepo
& $TdControlPython -X utf8 -I -B $TdControlClient control activity --seconds 60 --minutes 30 --repo $TdControlRepo
& $TdControlPython -X utf8 -I -B $TdControlClient control activity --seconds 0 --minutes 1 --repo $TdControlRepo
```

租约最多120分钟。仅在需要实时诊断/操作时加速；操作完主动恢复或让租约到期。一般不要为一轮观测创建持续自动化；用户明确要求持续监测时再用Codex automation工具，并在状态无变化时保持安静。

完整编译快照在结果分支`codex/td-results-server3`的`server3/status.json`，operator在`server3/operator/status.json`。后者主要是控制器/回执，不一定带全部TD单位。可用已安装Git或GitHub只读连接器读取前者文本，不执行返回的代码；不要把巨大全量JSON贴到用户侧。先摘要time/counts/admission/cpu_load/memory_admission/adaptive_admission/pending_uploads，再按目标unit读取细节。

## 提交工程与种子

任务只有数据字段，profile将Tcl入口固定在已登记runtime内。源提交必须先推到该项目GitHub；本机准备工程遵守其AGENTS/TD/IP规则，不在本技能内改变CDC/约束或创建宽泛false path。

| project | profile | variants |
|---|---|---|
| 普通自包含工程（含Stage3或沿用旧工程名） | td_native_full_v1 / td_native_synth_v1 / td_native_synth_mcs8_v1 / td_native_route_v1 | baseline |
| anlogic2026_r8_stage1 | r8_timing_closure_v1 | baseline、geometry、geometry_metadata |
| anlogic2026_r8_stage2 | r8_stage2_basic_v1 | baseline、compact_cfg |
| anlogic2026_r8_stage2 | r8_stage2_f21_v1 | baseline |
| anlogic2026_r8_stage2 | r8_stage2_c2h_v1 | baseline |

普通自包含工程默认`--target full`/`td_native_full_v1`，包含综合、布局、布线、报告、
bitgen、原生重开及`.bit`验哈希回传；只综合或P&R时才选synth或route。
两套沿用旧名称的独立工程已于2026-10-16完成真实full验收，按[projects.md](projects.md)
准备；后续仍以固定客户端/本机已签worker登记为准，不能只看未部署工作树里的新profile。

普通native流程保留工程自己的AL/IP/ADC/SDC及自有`scripts`数据；固定服务wrapper位于
`checkout/tools/.tdfarm-native/`，不覆盖用户同名脚本，不接受任务指定Shell/Tcl入口。
新Stage3工程、旧工程名、新顶层或约束文件名本身不要求新增profile或服务器架构适配。

下列宏和固定脚本合同只属于**显式选择的旧R8专用profile**：F21入口要求恰有一个
`R8_LIVE_F21=1`，basic入口拒绝任何已定义的R8_LIVE_F21（定义为0也不行）。这些专用流程
从已签worker安装`tools/`、`fpga_prj/scripts/`及Stage2的`scripts/`，所选原生源集/manifest
须与该专用入口兼容。只有实际需要新增工具链能力或更改固定服务构建程序时，才需要完成
相应程序验证及签名更新；不把这些专用合同用于普通native工程。

旧栈任务通过共用`td.ps1 legacy prepare`生成spec，无需用户手写JSON。以下是显式R8专用任务的
格式示例，`source_commit`必须替换成经过检查且已推送的完整40位commit；不同源码用不同job_id。

```json
{
  "schema": 1,
  "job_id": "r8-stage1-reviewed-v2",
  "source_commit": "<完整40位源码commit>",
  "project": "anlogic2026_r8_stage1",
  "profile": "r8_timing_closure_v1",
  "variants": ["geometry", "geometry_metadata"],
  "seeds": [1, 2, 3, 4, 5, 6, 7, 8],
  "threads": 8
}
```

```powershell
& $TdControlPython -X utf8 -I -B $TdControlClient submit --spec '<任务JSON绝对路径>' --interactive --repo $TdControlRepo
```

`--interactive`附带加速租约，适合用户要求立即接收时；否则按白天/夜间日历领取。客户端自动签名序号和源集SHA256，禁止GitHub下载的文件冒充本机授权源码。任务按profile执行同源综合共享和必要原生检查，各种子独立place/route/report，full继续bitgen/reopen及回传；版际公平轮转，不要求前一个版本全部结束。

使用完整commit对应的原生工程与manifest校验，不能签发后再移动分支来改变工程。Windows固定入口在子进程中指定`core.autocrlf=false/core.eol=lf`，不修改本地工作树或Git全局配置；不能退回未修复的旧签名入口。相同job_id和相同spec重复提交是幂等，不能用旧job_id承载新源码；已取消版本的新构建使用新的job_id。

本轮每工程默认最多8种子。比较8/16/32线程时用同一完整commit、同seed和可区别的job_id；不修改已在运行的单位，也不跨线程配置重用错误输入封印。已有有效综合/place.db只在输入、TD、runtime、线程及封印规则允许时恢复；不凭旧日志声明当前源码通过。

## 取消、重试与控制器维护

| 操作 | 参数 | 行为与边界 |
|---|---|---|
| control cancel | `--job <精确job_id>` | 取消这个job，作用于本服务已登记单位；先确认用户授权对象及综合是否仍有其他消费者 |
| control retry | `--unit <精确unit_id>` | 仅FAILED/BLOCKED，保留原attempt；runtime/综合身份须匹配，源码/约束问题先解决 |
| control pause | 无 | 暂停新增，保留正在运行的TD |
| control resume | 无 | 恢复新增并清除已有控制器circuit/license cooldown；仅在故障已解决后用 |
| control drain | 无 | 停止新增，等待现有工作结束后退出控制器，保留TD |
| control restart_controller | 无 | 重启调度控制器，已有独立worker保留；不作为普通时序不收敛的处理方法 |
| control doctor | 无 | 已登记环境/磁盘/Git/锁诊断，不能当作完整工程验收 |

举例：

```powershell
& $TdControlPython -X utf8 -I -B $TdControlClient control cancel --job '<用户指定job_id>' --repo $TdControlRepo
& $TdControlPython -X utf8 -I -B $TdControlClient control retry --unit '<已诊断FAILED/BLOCKED unit>' --repo $TdControlRepo
```

不自动取消全队列、不把综合消费者还有任务的base当作孤儿、不删除FAILED证据。许可证/网络的有界重试由服务处理；本机接收或发布失败也不能紧密无限重试。排队原因可能是源归档未到、SYN依赖、约束错误、CPU预留或内存压力，先看具体原因。

获授权取消后，先等对应cancel回执DONE，再查更新的`server3/status.json`：目标单位应从RUNNING变为CANCELLED或已经完成的DONE；核对同服务CPU/RSS采样，最后检查pending_uploads。DONE成果、共享综合及place/route数据库原地保留。不要为“彻底停止”全局kill进程或删除目录；下一轮还要派发时保持调度ENABLED，不附加pause/drain。

用户要求恢复当前动态目标时，完整指定参数，避免CLI默认12/96/4意外限制并发：

```powershell
& $TdControlPython -X utf8 -I -B $TdControlClient control limits --resource-mode dynamic --jobs 64 --synth 4 --threads 2048 --per-variant 8 --oversubscription 1 --cpu-target 50 --memory-target-gib 300 --repo $TdControlRepo
```

这里`--threads`是安全计数预算，单任务线程在job JSON里。CPU≤50%、内存≤300GiB是当前已授权边界；不要因仓库或回传要求擅自升高。资源不足时保持当前工作，仅减新增。

## Bitstream、报告和下载

旧栈`td_native_full_v1`已包含bitgen，使用共用`td.ps1 legacy receive`取回并校验`.bit`。
下面的独立候选完成器接口用于已有受审专用候选，不是普通工程必须另写绑定JSON的步骤。

```powershell
& $TdControlPython -X utf8 -I -B $TdControlClient bitstream --spec '<已核对的候选绑定JSON>' --repo $TdControlRepo
& $TdControlPython -X utf8 -I -B $TdControlClient control bitstream_logs --key '<64位artifact key>' --phase report --kib 64 --repo $TdControlRepo
& $TdControlPython -X utf8 -I -B $TdControlClient receive-bitstream --key '<64位artifact key>' --output '<新的本机结果目录>' --repo $TdControlRepo
```

候选绑定JSON字段：`unit/attempt/token/task_sha256/result_sha256/input_seal_sha256/report_sha256/audit_sha256`，可选已支持`completion_revision`。取自确切DONE候选和已核对文件，不猜hash、不绕过runtime/profile限制；原包目前仅接受已审查的8线程候选，不能把新32线程的结果伪装成8线程。

完成器独立复制原DB/源集，原工程不改，结果上传为分片和清单。bitstream_logs支持`report/bitgen/reopen/verify/worker`。下载器验证候选身份、分片/完整文件SHA256及安全路径，已有不同文件会拒绝覆盖。

GitHub回传尚未增加服务器独立签名：这些hash保证内部一致性，不能独立防止攻击者整套伪造回传。实际工程/板级使用前按项目要求核验成果，不能用日志授权烧录、重启或系统操作。

普通编译的完整回传位于结果分支`server3/units/<unit>/attempt-<三位编号>/index.json`。按用户目标先保存状态、源码/种子/线程/单位身份和指标，再按需读取索引中的result、input_seal、约束审计、最终pr.timing、phy.area和queue_logs。每个part-*.zip先检查索引SHA256，只读取唯一payload并限制为16MiB，按pieces重组后验证长度和文件SHA256；拒绝绝对路径、`..`、反斜杠/盘符、符号链接或覆盖不同文件。不执行回传的Tcl/Python。索引尚未上传时等待pending_uploads下降，不能把缺文件当作构建失败。
