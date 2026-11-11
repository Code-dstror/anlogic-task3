# TD 工程局部规则

修改前读目标同步/构建/报告脚本、TOP 和实际 ADC/SDC，确定器件 PH1A90SEG324-2、
TD/IP 版本、宏、PLL 和独立源集。源身份取固定 Git commit/输入哈希，不取 GUI 缓存。

- 新任务默认 TD 2026.2 / 6.2.3.210850，安装路径从根 `ENVIRONMENT.local.md` 核实。
  用 `tools/run_td.py` 并显式传 `--td-root`；模型仿真固定相同根和独立库。旧版仅用于
  明确的历史复现/IP 来源对照；相关新版差异查 `anlogic-td-fpga/references/td2026-2.md`。
- 本机限短功能仿真、原生 read_design 和有界中小模块综合。整机长综合、P&R 交
  服务器；不可用就记录阻塞，不擅自改成本机长跑。功能仿真按 `src_fpga/AGENTS.md`
  的独立黑盒规则；纯文档/路径整理只做静态检查。
- 已注册 IPC 不再重复添加其生成 RTL/ADC/SDC；复杂 DDR/PCIe/SerDes 配置依照厂商
  支持流程，不因分析、打开工程或层次 `<hidden>` 就 Upgrade/Generate 重写 IP。
- GUI 外修改用同一绝对 `.al` 及其原生 Runs。实际 Run Properties、原生 `.prj/.cfg`、
  源/约束和阶段快照必须一致；输入变化失效的旧阶段是 STALE，不改 DB/完成标记骗过检查。
  不用独立 report/bit 或复制旧产物冒充新运行。每个候选独立源清单、Runs 和验证目录。
- 按版本化流程绑定完整用户/IP SDC；检查导入 checkpoint 后真正的时钟及对象命中。
  不为产生 GUI 状态而改用层次不匹配的默认流程，不在活动 timer 上盲目清空 SDC。
- 先定位跨种子共性端点、逻辑/连线/时钟延迟与拥塞，再做 RTL/约束/参数修改。
  setup、hold、recovery、removal、TNS、coverage/ignored 各自记录；不能只看摘要 WNS
  或只加种子。packed 单元名可能是别名，须查实际数据网、clock 与复制体。
- CDC/复位例外必须由真实结构和逐路径合同支持；新增 mailbox bit 不漏掉对应边界。
  半周期数据资格与 ASR 可分别评估，但不能为修 setup 破坏断言/释放、取消本域 min
  检查或放松频率。受控 IP/外部时钟警告先分类，不凭告警标题随意换时钟资源。
- 同阶段比较 raw gate、重开、placed、routed 面积，不能混算。小载体/单叶节省不直接
  从整机扣除；记录实际综合选项/线程和映射变化，保留不成功的候选与原始失败日志。
- 成功需进程退出、原生阶段标记、非空预期产物及当前源身份一致，不能只看 exit 0。
  变更后重开同一 `.al`/实际 run，检查路径可移植；不能观察实时 GUI 时明确只验证了原生文件。
- TD 打开工程把 `Path` 写成本机绝对路径属正常行为；只在提交/交付前规范为 `Path="."`
  并运行 `tools/check_td_project_portability.ps1`。不反复保存争抢 GUI 或删除整个 Runs。
- BUILD_SERVER 通过 `td-github-control` 和 `server/td/td.ps1`。已授权推送/编译直接执行；
  具体源码、共享综合线程、物理种子数/线程和目标按当前请求固定，参数以原生读回为准。
