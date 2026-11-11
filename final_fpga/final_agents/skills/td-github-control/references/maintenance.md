# 历史 legacy：受控升级、故障和VCS

以下仅供明确选择旧 V2/HA 的历史维护，不是当前 simple 程序的升级步骤。
simple 手工更新用 [安装器与排空流程](../../../../server/td/simple/README.md#finalshell-安装更新)，
等待现有自动任务结束并保留回传、状态和认证配置；不要向退役 HA 派胶囊或重置签名登记。

## 安全V2的部署边界

本节仅适用于尚未HA登记的历史安全V2；当前部署以本机环境与真实回执为准。远程`publish-release`/update在V2被拒绝，不把“有自更新入口”理解成任意GitHub代码可执行。HA真实初装回执和新客户端登记后，程序胶囊更新改按[ha.md](ha.md)；信任/守护底座/schema使用独立的经验证登记路径；入口技能的持续授权允许Codex在已有可用连接上自主执行。保留旧release和使用它们的DB/封印；旧包存在不等于仍在运行，也不能自动删除作清理。

从当前仓库按需读取`tools/README_td_security.txt`、`tools/td_operator_secure.py`及`tools/tdop/manual_upgrade.py`，在本地审查具体程序diff。程序基线必须对应原已签名发布清单和服务器人工输出；不能从未签名status抄runtime后盲签新包。公钥指纹由既有本机登记取得，不接受GitHub替换。

已激活的固定客户端可以准备离线包，不用工作树Python作为签名器：

```powershell
& $TdControlPython -I -B $TdControlClient secure-prepare prepare --repo $TdControlRepo --base '<已签名worker基线commit>' --operator-base '<已签名operator基线commit>' --operator-runtime '<实际operator SHA256>' --dynamic-td-budget --output '<新的本机交付目录>'
```

这是旧V2迁移或确需独立登记时的流程。先完成可审查包、最小充分测试和哈希；在已授权任务范围内，通过已有服务器连接自行传输、核验并部署。只有缺少实际执行通道时才给用户FinalShell命令，不另加确认关卡。

用户应先按本聊天/本机可信交付的安装器SHA256核对，然后验签，再执行--apply。纯控制包可加--allow-active-workers，短暂关闭新准入并协作退出控制器，保持TD PID/token/lease/runtime。worker_overlay不能使用活动worker切换；管理事务和bitstream完成器须先结束。版本已变、签名过期或归属错误会拒绝，不能强制覆盖。

服务器是Git1.8.3.1，不支持git -C；如确需人工git操作，用`cd <目录> && git ...`。FinalShell终端不会自动取得本机D盘文件，需先通过文件面板传输；终端cd与文件面板目录独立，文件面板也要切换到目标目录。mkdir后目录仍可能为空，先ls确认文件，再校验哈希。一次一条命令，任何报错先核对输出。

目录权限检查曾因服务目录775拒绝升级。先只读查UID/路径/符号链接；仅对明确属于本账户的td_operator/td_farm及指定runtime/控制子目录收紧权限。不要chmod -R整个home、改系统或老师/其他用户目录。TD仍用同一UID访问，保留运行。

安装器确认SECURITY_V2_INSTALLED和WORKER_RUNTIME_PRESERVED后，本机激活固定客户端；instance必须相同。客户端/密钥放LOCALAPPDATA保护目录，旧仓库入口失去密钥，不再init-key。后续迁移需--previous-client，保留旧程序和序号；不要同时让其他对话继续用旧签发器。

本机实际入口登记在ENVIRONMENT.local.md，其他任务据此切换。仅在用户授权联系任务时发消息；否则提供交接文件供负责人读取。

## 故障恢复

- GitHub网络/上传失败：已有TD继续，观察pending_uploads及broker日志/退避；不要停工程来修查询。
- 控制器失败：核对controller_alive、healthy记录和具体异常，必要时用户授权范围内restart_controller；worker持有独立lease不会重复派发。
- 新包健康检查失败：离线安装器回退旧指针/策略/暂停标记。用同一已验签安装器的--recover，不下载GitHub恢复代码。
- 签名/实例/序号文件缺失、哈希改变：停止对应操作，不自动清空数据库、删除sequence文件、重置密钥或关闭校验。
- 源集/约束失败：报告真实BLOCKED原因，修工程后用正确输入身份重新提交；不增加种子或降低检查来“通过”。

2026-10-12已处理的Git1.8兼容问题，诊断时避免重复踩坑：

- 旧Git不接受空的`-c init.templateDir=`；新版本用明确的空模板目录初始化，非空残缺cache需要先审查，不能直接删除。
- `fetch.fsckObjects=true`配合depth=1会因省略父对象报`unable to find ... / object of unexpected type`；当前受限抓取采用完整历史，已有shallow缓存用受限unshallow。保留fsck、时间/内存/磁盘限额，不能关闭校验或手工塞假对象。
- 控制轮询与上传各自退避，查看operator状态里的`network_health.control_error/publish_error`；上传争用不能阻断收取取消请求。`controller_alive`只证明调度器活动，不单独证明控制通道畅通。
- Windows归档CRLF/LF差异通过固定客户端Git子进程环境修复；不修改服务器source seal，收到摘要不符先停这次提交，核对登记的客户端入口。

GitHub无法收取修复指令时，自更新也不能解决通道自身故障；安全V2还明确禁止远程update。此时保留正在运行的worker，通过已有授权连接完成经核验的受控恢复；没有通道时明确访问阻塞，不能为了时限启用旧无源集绑定的控制器。

## VCS初步并存

历史VCS工程验证为人工pilot；HA维护入口已有固定小型vcs_probe，完整工程仿真仍需独立实现和验收。没有通用远程exec能力，不能从GitHub要求执行任意vcs命令。

在项目中按需读`tools/README_vcs_pilot.txt`、`tools/vcs_probe.py`、`tools/vcs_he_pilot.py`和实际交付的INSTALL.txt。服务器已确认O-2018.09-SP2_Full64；需-full64，原linux/bin/vcs1不存在但linux64/bin/vcs1存在。Python/TD/VCS实际安装路径以用户输出和环境登记为准。

用户2026-10-12 20:47已手动通过小SV/license及PH1文件解析probe，目录`/home/<server-user>/td_runs/vcs-pilot-6iiw2q80`。未实例化的RAM/DSP不能凭该probe声明功能通过，后续仍看HE实际实例自检及其result.json。

20:49同一签名包的两种HE自检也通过，目录`/home/<server-user>/td_runs/vcs-he-gul5xf1_`；legacy 16帧/256检查，qualified 26帧/416检查。12条警告已按具体IP/model/未使用观测输出核对，留存`tmp/vcs_pilot_20261012/server_review.json`，原服务器状态/警告不改。只证明这个private HE范围，不作为其他仿真的通用警告白名单。历史ModelSim与当前RTL/bench有3处差异，暂不能宣称同源速度优势。

先小SV与PH1模型compile/run probe，检查PASS_COMPATIBILITY_PILOT；版本-ID成功不等于许可证或模型解密通过。随后HE使用固定签名源集、与ModelSim相同bench和冻结golden HEX，legacy/qualified各自自检，警告须分类。保留本机ModelSim，不能把private HE通过说成HD main、时序或板级通过。

效率用相同源码/数据/配置测量，分别记录首次编译、重复运行和批量吞吐。不同服务器CPU/工具版本不能冒充同条件对比。未来自动仿真需受签名固定profile与资源准入，由Codex按持续授权完成受控部署；不擅自启用未核验的FGP/许可证参数。
