# 固定 G1 表控制短测

`fixed_dehaze_lut_control.v` 保留原 ALGO BAR 端口和字段地址，但固定表没有
加载 owner、跨域命令/回复包、FIFO、RAM 或加载状态机。`cfg_begin_valid`、
`cfg_valid`、`cfg_commit_valid`、`cfg_abort` 恒零，`cfg_status_ready` 恒一；
busy/loading/update_busy/fault/stale_reply_count 恒零。原手动 service 独立保留。

复位沿用 `u_user_reset` / `u_pixel_reset`，两侧原始复位共同组成 cohort，
分别本域同步释放。kernel 的 `core_run` / `core_ready` 只在 PIX 时钟沿改变。
PIX 有效必须有真实 core-ready、map-valid、map-generation=1、PIX session-ready
及非零 session。这个单 bit 经 USER `ready_meta` / `ready_sync` 两级同步后，再与
USER 本域 session-ready/非零 session 门控；未增加多 bit CDC。首级 CDC 约束由
TOP/SDC 配套提供，第二级仍为本域时序路径。

ALGO MAGIC、ABI 和 F21 FEATURES 位保持原值。`STATUS.LUT_VALID` 是上述实际
状态，不依赖以前是否发过 QUERY，`ACTIVE_GENERATION=1`。冷启动时无命令也可读到
STATUS=8（valid、无 busy/loading/error，DONE 尚未置位）。读取本身不发任何 PIX
事务。QUERY=5 是可选的 USER 本域命令：验证真实 USER session、非零递增 sequence、
F21 target 和既有字段范围后，同一 USER 时钟完成 DONE/response-session/sequence，
result/active-generation 都为 1。错误 session/sequence/形状分别仍为 17/18/16。
BEGIN/WORD/COMMIT/ABORT 在合法会话及序号下返回 CORE_STATE=19；不改变 PIX 状态或
表/历史。合法 QUERY 清除此前命令 ERROR。ERROR 是命令回执，不连接业务 fault。

兼容事实：现有 `linux/rk_debug/controls.py` 的 `apply()` 调用 `_lut_idle()`，只读
ALGO MAGIC/ABI/FEATURES、STATUS 和 ACTIVE_GENERATION；不要求 DONE 或先 QUERY。
因此在真实会话就绪、没有命令错误时，普通 schema2 CFG 选择 DEHAZE、generation=1
即可经过这项软件前置检查，无需 QUERY/BEGIN/257 WORD/COMMIT 或新的 Linux 算法。
软件仍须完成原 CFG/APPLIED、真实产品接收和图像验收。若主动调用旧 load-lut，19
会留下命令 ERROR，现有高层 `_lut_idle()` 会阻止后续配置；这不是固定表失效，也不能
把旧加载流程作为本 profile 的正常启动步骤。本改动未修改 Linux。

短测使用 10 ns USER / 7 ns PIX 双时钟、真实 AUTO map 和显式 TD 官方 ERAM/DSP
模型。覆盖无 ALGO 冷态 G1、USER-only/PIX-only 复位、两域 session-ready/非零门控、
字段 byte strobes、部分 COMMAND/未知地址 SLVERR、QUERY 的会话/序号/target 错误、
四种 mutation 负回执和后续 QUERY 清错。故意保持错误的 core status，同时 USER
读写、查询与负命令密集运行；真实已钉住 map 的请求及 20-bit RAM 回复持续推进，
cfg strobes 始终零。没有模拟跨域 FIFO，也没有 force 或初始化 RAM 捷径。

```powershell
& 'python' -B `
  refactor/hdr_dehaze_auto/src_fpga/simulation/autof21/fixed_control/run.py `
  --name short_r1 --td-root D:/App/TD_Release_2026.2.210.850 `
  --modelsim-bin D:/App/modelsim/win64
```

每次必须用新 name 保留原尝试。`tmp/autof21/fixed_control/short_r1/qualification.json`
为实际 PASS：11 命令、185 checks、143 BAR reads、346 pinned RAM replies、3 冷复位、
1,421 PIX cycles，owned warnings=0。日志、全部输入 SHA256 及生成 bench 同目录。
综合、P&R、时序、板级：NOT_RUN；本短测不代替 TOP/CFG 与完整 HD 图像验收。

## 独立 mapped 对象/资源探针

`probe.py --name mapped_r1 --td-root D:/App/TD_Release_2026.2.210.850` 通过仓库
`tools/run_td.py` 创建独立 `.al` 与原生 `syn_1`，线程 1，每阶段最多 120 秒，
没有主工程综合、place、route 或 bitgen。保留实际 service 和两个 release reset
实例名，PIX table-valid 注册、会话固定 1 而 readiness 动态，BAR 输入动态，114 IO。
从当前 `stream_cdc.sdc` 精确复制 ready_meta 的 7 ns datapath-only max delay 及
同端 hold-only false path，保留复制文件和原始 SDC SHA256；不改主工程约束。

`tmp/autof21/fixed_control_probe/mapped_r1/RESULTS.json` 实际 PASS：ready_meta 精确
匹配 1 个寄存器，2 条 max paths 全部 dominated、shadowed/ignored 为 0，invalid 和
no-path constraints 都为 0。ready_meta→ready_sync D、ready_sync SR recovery 和
普通本域 D/CE/SR 哨兵共 6 条路径的约束前后签名一致；reset 两链前两级也检查非空且
与例外集合不重叠。原生 `.al`/`syn_1` 已实际关闭、重开和加载同一 gate DB。

`leaf.area`：service 层级 196 logic LUT、337 FF；含 wrapper/5 FF 哨兵的设计
总计 249 LUT、342 FF、114 IO，ERAM/FIFO/DSP/DRAM 均为 0。这是 tiny leaf 数量，
不能当作完整工程的资源或节省量。原生 thread=1 读回见 `syn_1.params`。

探针 `check_timing` 还真实报告 67 个输入/45 个输出未指定 IO delay，以及两个
恒零 response 低位输出 pad dangling；未为缩小报告修改延迟或时钟。其 STA coverage
60.12%、Confidence=Synthesized，不是时序签核。mapped min 没有 endpoint；hold 范围
结论仅为首级集合与保护集合不相交，物理 hold/removal、P&R、bitgen、板级均 NOT_RUN。
