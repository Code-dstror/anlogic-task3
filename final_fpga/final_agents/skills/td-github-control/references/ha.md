# 历史 legacy：TD HA 与签名程序更新

本页只适用于用户明确选择的旧 HA 栈。2026-10-22 默认 simple 服务没有这个在线更新通道，
程序发布不等于部署；更新按 [simple/README.md](../../../../server/td/simple/README.md) 手工执行。
不能因旧目录、旧登记或本页仍存在就重新启动退役 HA。

当前服务器实例的事实以 ENVIRONMENT.local.md、登记记录和新鲜回执为准。首次安装参考项目交接和安装器；已有HA不重复初装。入口技能的持续授权允许Codex通过已有授权连接自主完成经验证的登记与恢复。缺少实际连接时才请求用户执行。源码已push、载体验签或本机测试PASS均不等于服务器部署成功。

初装用 ha_bootstrap.py/programs.tar/package.json 三文件，独立bootstrap SHA256
由可信本机交付；旧V2 manual_upgrade.py不是本载体的服务器安装入口。
实际 operator/worker 前任改变即重新准备，不能改摘要。服务器成功后才激活新
固定客户端、迁移原钥匙并更新环境索引；此前不改其他任务的签发入口。

## 部署后操作

沿用 operations.md 的本机Python/客户端/仓库变量和 -I -B：

```powershell
& $TdControlPython -I -B $TdControlClient ha status --repo $TdControlRepo
& $TdControlPython -I -B $TdControlClient ha prepare --repo $TdControlRepo --commit '<完整已审查源码commit>' --target operator --output '<新本机目录>'
& $TdControlPython -I -B $TdControlClient ha publish --repo $TdControlRepo --package '<准备目录>' --validation '<匹配的本地PASS记录>'
& $TdControlPython -I -B $TdControlClient ha status --repo $TdControlRepo --request '<更新ID>'
```

prepare仅构造本地未签计划，并在受保护客户端中登记摘要。检查实际diff并完成
受影响验证后才publish。publish消耗独立更新序号，签名固定前任、文件/归档/
资格摘要、core ID、有效期、server与安装实例。GitHub同仓库更新分支为
codex/td-updates-server3。签名发布不是部署回执；核对DONE、实际主/备/worker ID
和新鲜进程健康。未签结果仍可能被攻击者伪造，不能据此信任陌生程序/钥匙。

operator只更新控制代码，保留已知构建字节；worker保留控制代码，需真实同源
预检和映射对象资格、匹配构建文件集合，等待所有队列/worker lease/bitstream
空闲，再经小环境探针与试启动。reserve是单独的明确签名目标，备用活动时拒绝
覆盖。支持`--base-operator/--base-worker`显式选择本机已登记或已签版本，不能
从不可信回传盲抄陌生ID。

V2的status/logs/submit/cancel/limits/activity照常用，仍无通用exec或任意Tcl。
控制/worker更新不能替换公钥、重放围栏、守护底座或数据库schema。程序需要
这些变化时走经验证的独立登记/迁移；有已授权连接时Codex自主完成，不偷偷扩大胶囊权限。不要对旧runtime的失败unit
盲retry；新构建入口/source/封印身份应生成新job或明确检查点迁移。

## 主备与故障

两个守护进程通过OS锁选唯一主导者，并可互相恢复。主导者死亡后采用原broker/
任务/lease；主程序三次失败可启用已冻结备用，不能为接管重跑已完成TD。
更新预备、切换、试启动与提交均落盘，失败回退原指针、worker配置/凭证和原
暂停意图，保留所有DB/日志/失败候选。程序版本故障与源码/约束故障要区分。
信任/序号缺失不自修复为零；未知锁、归属或PID/argv错误不全局kill。

原CPU约50%/300GiB准入和外部负载保护保留。完成后立即调度回传，任务日历仍
白天5分钟、夜间2小时；轻量控制/更新白天60秒、夜间10分钟。活动租约30/60秒
自动到期。夜间收到加速指令前最多等10分钟，不能声称Git push能即时唤醒不轮询
的内网服务。更新签名有效3小时，忙碌中延期并过期时需要重新签发。

旧Git使用完整抓取/fsck、固定工具、隔离config、空template/hooks与配置白名单，
不用git -C/空templateDir/depth1。可修复已知空/refs-only残缺init（保留原缓存并
限每日次数）及缺失的固定remote；未知内容/链接/URL变化不自动清除。
主/备/更新缓存分开，上传退避不会阻断控制读取。

HA R2增加固定VCS远程自检provider，只有工具真实登记并核验后可用；当前服务器
事实仍以ENV和回执为准。完整VCS工程仿真未实现。后续扩展须有固定编译器/
模型/golden/source绑定、独立队列和lease、统一资源准入；保留本机ModelSim。

R3最终七文件构建入口来自3f52dcc5afe013567ed58a0eecdd3dfd9e2b426b，资格已对
实际组合worker工具和原生最终gate/physical报告重查。交付目录worker/中有精确
选择和资格数据。ha prepare用--select控制改动范围；不能把中间debug_shadow_review
报告冒充最后queue_constraint_audit。新worker实际DONE/ID/合同确认前不能派发R3。

ha refresh-client --runtime <本机已签ID>通过受保护批准记录刷新Windows启动器，
保留原钥匙和两套序号；ha use-base只选择本机已登记/签发的前任ID。刷新后核对
启动器摘要并更新ENV，不从未经签名的服务器回传接受陌生程序或工具。
