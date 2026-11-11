# 历史 legacy：HA R2受限维护与VCS探针

仅用于用户明确选择且实际登记的旧 HA R2，不是 simple 服务的诊断/自修复接口。
新服务仅有固定 build/continue/cancel/pause/resume 等动作，不支持下面的维护探针命令。

先确认HA R2已由用户在FinalShell登记，Windows固定客户端也已激活。
当前旧580客户端不能使用以下功能。路径读取工程ENVIRONMENT.local.md，不沿用
聊天中另一个安装实例。所有命令经固定客户端，用python -I -B。

```
trusted_client.py maintenance diagnostics --repo <repo>
trusted_client.py maintenance td_probe --repo <repo>
trusted_client.py maintenance td_build_probe --repo <repo>
trusted_client.py maintenance repair_log_modes --repo <repo>
trusted_client.py maintenance vcs_probe --repo <repo>
trusted_client.py maintenance logs --request <ID> --phase compile --kib 64 --repo <repo>
trusted_client.py maintenance cancel --request <ID> --repo <repo>
trusted_client.py maintenance repair_control_primary --repo <repo>
trusted_client.py maintenance repair_control_reserve --repo <repo>
```

诊断只读本服务固定状态/日志。探针独立执行，按现有负载预算预留1核/8GiB，
限时、限日志和内存；不暂停已有TD。日志阶段只允许worker/probe/version/compile/run。
取消操作只触及该维护任务新建的进程组。控制缓存修复只保留重命名指定cache，
不删工程/DB/源归档，受正在抓取的锁及每日次数限制。不能发任意Shell或Tcl。

SIGNED_REQUEST_SENT不是执行完成。看对应status回执，维护任务被取消时原指令
回执DONE、details.state=CANCELLED。回传server3/maintenance/<ID>有结果及限长日志。
VCS初期只编译/运行内置固定SV，未覆盖工程仿真、PH1模型等价或速度对比。
provider可通过签名operator更新；后续增加新功能时用本机已批准版本执行
ha refresh-client，不需再去FinalShell操作；核心/信任变更使用独立经验证登记路径；有已授权可用连接时Codex自主执行，无通道时才报告访问阻塞。

完整流程和精确R3 worker资格见项目tools/README_td_maintenance.txt。

固定 td_build_probe 会领取绑定commit/hash的小源集，在本服务维护目录的tmp内跑综合、P&R、bitgen和重开，并回传bit/报告。其专用编译预算为1核/8GiB/600秒，结果下载须检查长度和SHA256；负时序仍如实报告。repair_log_modes只处理固定自有operator/controller日志与已定义轮转文件，保留内容、拒绝链接/非本账户文件。
