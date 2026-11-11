# 检查点复用与64线程预算修复

2026-10-23更正：原生线程值为1/2/4/8/16/32，任意合法组合直接求和<=64。
12/20/24会退回auto，不能以请求被接受认定生效；[v6.3](THREAD_VALUES_V6_3_20261023.md)补校验与读回。
v6.3已由用户安装并获新鲜回执确认，见[部署记录](../evidence/v63-deployment-20261023.md)；本次不追加编译。

2026-10-22，待用户10月23日 FinalShell 手动安装版本：`2026.10.22-checkpoint-budget-v5`。
包含上一轮v4全部配置能力。本次没有修改服务器程序、队列或正在编译的工程，也没有派发生产任务。
只读取了用户指定的“去除 LZ77 工程”聊天，现场错误以已下载原生日志核实。

## PRJ-8817 的原因与修复

高力度子任务 `auto-hdr_jpeg_high8-8403694b6756c26a4a2a-s1` 等六种子复用综合后，
在 `launch_runs -step opt_place phy_1` 报 `Run syn_1 should be up to date`。
原AL约束路径含 `../fpga_prj/constraints/...`，对应原生综合快照 `.prj` 使用规范化的相对路径。
两者指向同一文件，但TD在新进程重开时会误判综合配置不一致；单寄存器隔离工程已稳定复现。

v5在任务副本内规范化全部注册文件和IncludeDir路径，再打开AL并走原生阶段流程。
源文件、IP、ADC/SDC内容均不改变，不编辑已有DB或综合快照，不伪造状态/完成标记，不强制跳过TD检查。
共享综合仍只运行一次，子种子复制到各自独立目录；父任务和手动GUI工程不修改。
真正的源码/约束变更仍需新build；策略/属性变化按受影响阶段重跑。

本机TD6.2.3.210850原生复现和修复检查：

| 检查 | 结果 |
|---|---|
| 等价但非规范AL约束路径，使用已有gate DB | 复现PRJ-8817，未进入布局 |
| 只规范化路径，使用同一gate DB | 原生布局正常启动并完成，无重新综合 |
| 经实际 `flow.build_script` 修复路径 | synthesis REUSED，placement/reports/reopen DONE |
| 修复前后gate DB、syn_1/*.prj与历史工程AL哈希 | 相同 |

原始命令、日志和哈希在本地 `server/td/local/checkpoint-v5-probe/`。
这是单寄存器的短时控制流程验证，不证明生产HDR/JPEG物理时序通过。

## 通用线程预算

受控线程预留等于实际请求值，不乘1.25，不因CPU历史峰值额外放大。
支持所有满足下列条件的排列组合，不维护预设组合白名单：

- 每任务1–32线程；同一时刻最多8个受控任务。
- 请求线程总和不超过64：`sum(requested_threads) <= 64`。
- 综合进程与各物理种子都计入同一总和；独立综合默认8个并发槽。
- 共享综合与其后物理子任务不同时重复预留已结束的综合线程。
- 单个full任务如综合/物理线程不同，按两者较大值预留全程，确保后续阶段有预算。

8×8、32+32、8+8+16+32、31+17+16、1+3+5+7+9+11+13+15均为合法示例，
其它组合只按上述条件判断。超过64则保留队列，任务结束后自动补位。
每20秒最多放行一个任务；优先级与同级FIFO、项目并发限制继续有效。

旧TD CPU50%门槛不再参与v5准入：build-server可用112逻辑核时，它会把上限压到56核，妨碍64线程预算。
旧 `max_cpu_percent`、`cpu_growth_factor`、`unknown_td_threads` 仅兼容读取历史配置，
不再接受为远程policy字段，不再限制受控线程预算。状态回显 `cpu_budget_mode: requested_threads`、
`cpu_growth_factor: 1` 和实际 `max_total_threads`。
空闲手动GUI不再虚占16/20线程；其实际CPU占用计入整机负载预测，RSS仍计入内存预算。

内存300GiB、整机CPU目标85%、CPU affinity/cgroup容量、可用内存与新鲜采样检查继续有效。
因此64是线程准入上限；真实内存或宿主资源不足时，任务仍排队，不强杀已有TD凑预算。
线程总和不等于工具瞬时CPU硬上限；TD某阶段实际利用率由其原生算法决定。

v5 policy示例：

```json
{
  "max_parallel": 8,
  "max_threads_per_job": 32,
  "max_total_threads": 64,
  "max_synth_parallel": 8,
  "max_td_memory_gib": 300,
  "max_host_cpu_percent": 85
}
```

```powershell
./server/td/td.ps1 policy --file policy.json
./server/td/td.ps1 status
```

只在用户要求调整已部署服务时执行policy；本次未执行。build/continue、JSON配置、策略/默认恢复
等用法沿用[运行配置说明](CONFIG_UPGRADE_20261022.md)，其中v4旧CPU规则以本页为准。

## 明天更新

将新包 `td-simple-update-20261022-v5.tar.gz` 上传到 `/home/build-user/td_simple/bootstrap/`，以build-user执行：

```bash
tar -xzf /home/build-user/td_simple/bootstrap/td-simple-update-20261022-v5.tar.gz -C /home/build-user/td_simple/bootstrap
bash /home/build-user/td_simple/bootstrap/server/td/simple/apply_update.sh
```

新包不含凭据。安装器先停止新增准入，等待受控任务自然完成，旧控制器在等待期间继续回传。
保留SQLite队列、工程、资源历史、DB/bit/日志、网络认证和手动GUI；不自动重跑此前失败的六种子。
旧默认综合4槽迁移为8，CPU系数迁移为1，总线程设为64，清理已废弃CPU policy覆写。
原已明确设定的其它较低项目/资源策略仍有效，安装后从status核对实际值。

成功标志：新鲜status的 `controller_version` 为 `2026.10.22-checkpoint-budget-v5`，
`capabilities.checkpoint_path_normalization` 为true，`resource_policy.cpu_budget_mode` 为 `requested_threads`，
`max_total_threads` 为64、`max_parallel` 为8。

## 验证状态

新增检查覆盖134种64线程组合、8个综合并发、旧CPU规则不干扰、宿主/内存保护、
更新迁移、路径等价性、DB/快照/输入不修改。
控制器测试共112项覆盖通过：100项在本轮套件检查中PASS；客户端旧policy用例适配已退役字段后，
对应12项全部PASS。命令为指定Python3.12.9运行
`-B -m unittest discover -s server/td/tests -p "test_simple*.py" -v`，
客户端复查仅选择 `test_simple_client_config.py`，没有重复无关回归或派发服务器验证编译。
生产RTL仿真、生产综合/P&R/最终STA/bitgen、板级及服务器v5部署：NOT_RUN。
