# 历史 legacy：新工程提交与验收

仅在用户明确选择旧签名栈/历史复现时读取。2026-10-22 起默认使用 simple 服务，
其新工程、Run Properties 和检查点接续见 [RUN_CONTROL.md](../../../../server/td/simple/RUN_CONTROL.md)。
以下签发、profile、封印和旧传输范围不是 simple 服务的要求，不据此恢复退役控制器。

在本项目提交新的TD工程时读取；状态/控制/升级仍按operations.md和ha.md。
本入口复用已登记签名客户端，不读取密钥，不因新工程来自当前仓库而自动获得发布授权。
本项目服务修复及独立验收工程的既有发布目标是Code-dstror/anlogic-task3的codex/td-server；任意对话中的业务构建仍须依据真人用户实际请求。

## 准备

用户保证TD版本和器件正确；当前服务实际为6.2.3.210850、PH1A90SEG324-2。
用户提出“提交这个工程到服务器编译”后，由Codex完成工程接入、任务JSON、入口匹配、签发及验收，不把这些操作转交用户手工处理。
若工程的目录/路径不适合服务器，在该任务的隔离副本整理AL及依赖引用，保留原工程、旧Runs和IP生成物字节；完整文件已在授权工作区内时自行补齐和规范路径。
仅在实际缺少必要源文件、受许可IP/访问通道或存在本质设计错误时报告具体阻塞，不能只返回“预检失败”。不得借整理工程修改其他任务的正式工作树或重生成受控IP。
工程位于`fpga_prj/<project>.al`，IP、ADC/SDC、源文件、头文件与初始化数据完整进入同一固定commit。
传输范围只有`src_fpga/`、`fpga_prj/`，构建脚本和旧Runs由服务规则处理。
不要把依赖放在仅本机存在的目录、被忽略的文件或服务器会替换的工具目录中。
IP已由IPC登记时不重复登记其生成RTL/ADC/SDC，不重生成已有受控IP。

若AL仍引用本机临时镜像，先读取[冻结工程工具说明](../../../../server/td/client/freeze_project.md)，
由Codex选择已有输入封印，在全新隔离目录用`freeze_project.py`预览并材料化；不让用户手写JSON。
它核对数据和已封印origin别名，保留IP/初始化字节及AL配置，只调整副本引用。
把输出并入已有隔离Git副本时，合并本包作用域的Git属性规则，不覆盖原根属性；
核对Git blob及归档字节后再取得固定commit并prepare。无法证明的Tcl `source`工作目录
须先核对实际构建上下文，工具不能靠猜测给出可移植结论。
已经自包含且受Git追踪的工程直接prepare，不为使用工具而再复制或重新生成IP。
针对当前FPGA最终候选的观察及边界见[接入记录](../../../../server/td/projects/fpga-final/README.md)，
该记录不替代发起对话选择的新固定候选，也不是服务器的项目名白名单。

从仓库根目录调用本地包装器（它自动读取本机Python、固定客户端索引并传-X utf8 -I -B）：

```powershell
./server/td/td.ps1 legacy prepare --commit <完整40位commit> --project <AL名称> --job <新job_id> --target full --seeds 1 2 3 4 5 6 7 8 --threads 8 --output server/td/local/jobs/<job_id>/plan.json
```

默认full流程到bitgen和原生重开；只做P&R选`--target route`，只综合选`--target synth`。
prepare只读取该commit，未提交修改不会混入；不推送、不启动TD、不签发。
检查Linux大小写/相对路径、当前传输范围、AL源集、IPC启用的生成文件和初始化文件、字面量HDL include，生成plan及任务spec。
宏生成的include、动态IP脚本与物理约束仍由真实TD按工程配置展开验证；PREPARED不是编译PASS。
原AL和所有注册文件保留；明确在综合和P&R中均禁用的文件不强制展开其仿真头文件或IP生成物。
启用状态未知或存在启用的重复登记时仍检查编译依赖，不根据FileSet名字猜测源集。

普通工程默认选择`td_native_full_v1`，沿用自己的AL/IP/ADC/SDC、宏和运行配置。
只做P&R或综合时，分别选择`td_native_route_v1`、`td_native_synth_v1`。
合法工程名即使沿用`anlogic2026_r8_stage1`或`anlogic2026_r8_stage2`，也不自动选择专用流程；
顶层、IP、引脚和约束文件名不绑定旧架构。标准TD工程不需要另写服务器“架构适配器”。
只有实际任务要求复现既有R8阶段专用流程时，才显式传`--profile <专用profile>`；
当前冻结Stage2任务继续显式使用`--target route --profile r8_stage2_c2h_v1`及其完整CDC/复位/约束审计，不改已有任务身份。
不把Stage2固定实例/端口/引脚匹配规则用于原生新工程。实际TD源或约束错误按文件/日志处理，
不跳过检查，也不因“架构复杂”要求用户修改服务器程序。
原生输入保留工程自有`scripts`目录和其中的HDL/约束/间接Tcl依赖；固定服务脚本写入私有目录，
不覆盖用户文件。full流程还检查bitgen完成标记、非空bit、布线DB身份和源码/checkpoint封印。
bitgen成功与时序收敛分别报告，板级NOT_RUN不能写PASS。

## 提交与监督

按用户授权推送检查过的固定commit；工具不自动push、commit、stage或修改正式工作树。

```powershell
./server/td/td.ps1 legacy submit --plan server/td/local/jobs/<job_id>/plan.json
./server/td/td.ps1 legacy status --job <job_id>
```

submit重新核对plan与固定源，核对项目远端、登记实例/启动器哈希、控制器和已有job；已存在且身份相同不重复签发。
status按本机当前时间及实际轮询周期计算回传新鲜度；不能沿用旧JSON内部的age_seconds。新签名前拒绝陈旧快照或与本机已签登记不同的runtime，保留现有任务并排查通道。
各对话共用server/td/local/relay.lock的OS锁，按job写入local/dispatch记录；首次签发前记录身份。锁忙时稍后重试，不把本地争用当编译失败。网络结果未知时重新调用不会自动再签名，应从已有.sent/dispatch记录和固定客户端回执确认实际结果。
有同名但不同source/profile/threads/seed的job时停止该次提交，换新job_id；不能覆盖旧任务。
SIGNED_REQUEST_SENT仅表示发布；接收DONE、综合DONE、P&R DONE、最终时序、bitgen和板级分别报告。
共享综合/预检通过后最多8个种子独立并发；保留CPU约50%/300GiB保护，不等首种子完成。
长时间布局若CPU活跃仍属运行；先查当前阶段、诊断和上传退避，不重启/取消现有任务。

## 接收

```powershell
./server/td/td.ps1 legacy receive --unit <s_或p_加32hex> --attempt 1 --output server/td/local/evidence/<job_id>/<unit>/attempt-001
```

默认接收result、控制器接受result、输入/checkpoint封印、时序/面积、约束审计和已封印的`.bit`；用`--file <索引中的相对路径>`选择其他文件。
阶段回传可加`--phase route`或`--phase bitgen`，保存到单独子目录；bitgen日志通过该receive入口取回。
每块及完整文件验证SHA256、长度和路径，拒绝覆盖不同文件，不执行回传代码。
索引尚未上传时先看pending_uploads，不能把它误判为编译失败。
核对result的source_commit/runtime/unit/attempt/threads与输入封印，比较原始/接受结果；报告最终setup/hold和coverage。
GitHub回传尚无独立服务器签名，传输哈希不提供服务器身份认证；不据此授权烧录或系统操作。
