# 每个受控任务16GiB预算 v6.4

版本：2026.10.26-memory16-v6.4。2026-10-27用户FinalShell安装及新鲜GitHub回执共同确认已部署，
见[部署记录](../evidence/v64-deployment-20261027.md)。

## 行为

综合及每个物理种子的准入预算统一为16GiB。8个种子合计128GiB，16个种子合计256GiB。
预算取自全局resource_policy.memory_per_job_gib，不再取项目memory_gib与历史峰值×1.5的最大值。
因此已有队列中的48GiB字段不需要重写，升级后同样按16GiB准入；源提交、任务ID、种子和原生配置不变。
旧memory_gib保留为请求/历史记录，新请求中该字段也不覆盖全局固定预算；
后续如需改变统一预算，使用policy的memory_per_job_gib。

状态中reserved_memory_gib及活动/排队任务的effective_config.memory_gib回显实际预算；
requested_memory_gib保留旧请求值。已结束任务不被追改成“当时使用16GiB”。
升级从旧策略迁移为16GiB，并清除旧的全局memory_per_job_gib覆盖；再次安装时保留升级后的显式policy修改。

16GiB是调度预算，不是进程内存硬限制。保留300GiB实际RSS、宿主可用内存、CPU及线程预算检查。
RSS预测按已观测占用+尚未使用的预算+候选16GiB计算，避免真实用量高于16GiB时继续过量准入。
手动TD的32GiB底线、历史/实际占用余量保留；memory_growth_factor仍用于手动任务，不抬高受控种子的固定预算。
线程合法值、总64线程、20秒启动间隔和报告回传行为保持。

## 不设置固定种子数量上限

默认max_parallel=0，表示resource_budget模式，按CPU、RAM和宿主资源决定能启动多少任务，
没有固定8或16并发上限，也不再受旧任务/项目记录里的max_parallel=8限制。
max_synth_parallel=0同样取消额外综合槽数量限制。16个每个4线程、16GiB的物理种子
合计64线程和256GiB，可在其余资源充足时同时准入。
旧的24种子批次限制也已移除，种子编号仍要求非负、互异且在TD整数范围内；
单次JSON请求仍受既有64KiB传输限制，大批任务可以分批提交。

如需人为限流，policy.max_parallel可设正整数；这是用户主动的可选限制，不是内置种子上限。
手动限流模式下项目的显式max_parallel仍生效。默认安装迁移旧并发策略为0，清除旧策略覆盖，
不修改现有任务的源、ID或原始请求；活动/排队状态另回显实际max_parallel=0及requested_max_parallel。

## 验证

60项资源、策略、队列、客户端及迁移测试及1项补充案例通过。包含旧48GiB队列、历史峰值不抬高预算、
16×4线程/16GiB不受旧8并发字段限制、17个4线程任务因64线程预算被拒绝，
以及实际RSS/宿主内存保护、移除24批次上限和升级幂等。
补充案例确认18个1线程任务可准入，第19个因304GiB预测内存排队，而不是固定16种子限制。
另做44项控制器集成检查，其中取消归档用例一次出现ERROR、单独复查通过；
此次未修改归档逻辑，未把这次初始失败写成一次全绿。
2026-10-26只读状态确认：当时6任务×48GiB=288GiB，第7个因300GiB上限排队。
使用同一真实快照离线执行新准入计算，第7至16个均READY，16个共64线程/256GiB。
记录：server/td/local/memory-budget-20261026/verification.json。没有派发TD编译或修改服务器。

## FinalShell安装

将td-simple-update-20261026-v6.4.tar.gz上传到/home/build-user/td_simple/bootstrap/，执行：

```bash
tar -xzf /home/build-user/td_simple/bootstrap/td-simple-update-20261026-v6.4.tar.gz -C /home/build-user/td_simple/bootstrap
bash /home/build-user/td_simple/bootstrap/server/td/simple/apply_update.sh
```

安装器先暂停新准入，等待当前运行的任务自然结束后替换程序，再恢复原准入状态。
此前准备更新时的6个运行任务无需中断；剩余队列保留，并由新版预算继续调度。
WAITING_FOR_TD_IDLE是等待现有任务结束；Ctrl+C按既有逻辑恢复原暂停状态。
没有自动取消、重编旧任务或删除成果，也不需要重新上传校园网/SSH凭据。

完成后核对版本2026.10.26-memory16-v6.4，以及：
Memory budget: 16GiB per controlled job、Resources: max_parallel=resource-budget，
以及memory_budget_mode=fixed_per_job、memory_per_job_gib=16、max_parallel=0。
2026-10-27的新鲜回执已确认安装和策略生效；当时无运行/排队任务，未追加真实16种子并发试跑。
