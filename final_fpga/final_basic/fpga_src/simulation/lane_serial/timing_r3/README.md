# R3 lane 定向短测

固定 A/B worker 是 `14df01dcce` 的原始 `lane_ridge_candidates1_lutram.v`，
冻结在 `fixed_14df/`，仿真时仅改模块名。生产原 R2 源与原扩展仿真不修改。

接口保持同一个像素时钟/同步复位域：每个串行事件是 32bit
`{hint2, center_y8, gy11, gx11}` 与 quarter `x/y9`；480×270，ROI y169–269。
worker 每拍接收一个事件且无反压；4→1 FIFO 的有限容量与满溢降级合同保持。
SOURCE 失败返回 `0x81`，局部/顺序/满溢失败返回 `0x80`，取消清除发布；
成功记录最多303个40bit点，描述符在 `record_ready` 前保持。

本次只增加内部延迟：winner RMW 读出后寄存，下一拍插入并写回；单项最新写结果
转发覆盖连续同 bank/bin 的依赖，递归链只经过一次 insert。二点对维持首点不差于
次点的排序不变量。separated 使用有符号12bit差值与 ±24 比较，覆盖全部11bit x。
行选择 READ/QUALIFY/REDUCE 三拍/点，最坏四遍288拍；三点排序每拍一次交换，
再发送三点，总计不到300拍，低于相邻行结束的480拍。

```powershell
python refactor/dual_lane_timing_r3/src_fpga/simulation/lane_serial/timing_r3/run.py --td-root <TD2026.2-root> --modelsim-bin <ModelSim-bin> --name <unique-name> --only leaf
python refactor/dual_lane_timing_r3/src_fpga/simulation/lane_serial/timing_r3/run.py --td-root <TD2026.2-root> --modelsim-bin <ModelSim-bin> --name <unique-name> --only shared
```

`leaf` 包含固定14df的14帧逐点/候选逐拍 A/B、真实303项、同bin、跨行尾/头、
有限停顿、SOURCE/LOCAL/取消/恢复、FIFO full+pop、满溢及独立连续RMW注入。
RMW注入以冻结R2 insert算法维护独立24对记分板，逐拍检查写回与两份真实TD RAM读口。
`shared` 只运行两幅完整1080p4PPC：白色无主动停顿、黄色gray带有限反压；
其间插入SOURCE失败并检查恢复。逐项比较129600 quarter样本及全部发布点。

每次输出独立 `tmp/lane_timing/<name>/RESULTS.json`，包含命令、所有输入SHA256、
TD模型路径、结果和日志。本仿真不证明综合、P&R、时序或板级通过。

## 有界资源复盘：共用 row-choice / emit 寄存器

只采用一项压缩：扫描期间的 `chosen0/1` 与扫描结束后的排序/发送 `emit0/1`
共用两份27bit寄存器，删除54个重复FF。READ/QUALIFY/REDUCE、三拍排序、
RMW读寄存与单项forward均保持；一拍一个sample的递归链没有改变。

`probe_shared_emit.py` 在采用前的R3 worker上生成唯一变体，独立tiny工程使用相同
scan harness、8ns、TD2026.2、4线程及 `area_prior/partition/min_control_set=2`。
`tmp/lane_area/shared_emit_a/COMPARISON.json` 记录同阶段结果：worker在raw和reopen
均净少29 logic、54 FF，ripple/DRAM/ERAM不变；包含同一harness的tiny总Slice净少34。
该收益不能直接从主工程99.72%占用中相减，新的完整工程资源/物理时序尚未运行。

候选实际SYN在89s完成；120s总预算在随后DB reopen中到期，原失败结果保留。
单独只读native reopen补齐比较，未重新综合。采用的生产worker与已测候选逐字节相同：
SHA256 `315b5c9ef1feec82e13cf72ee43b190d0fbdaec3a15681f8d988aee12d01cb2d`。

已有worker短A/B可单独运行：`--only worker`，覆盖固定14df的14帧/303项/行重叠，
以及3002次II1 RMW写入。`--worker-source <path>` 可显式检查隔离候选而不修改生产。
本次PASS证据 `tmp/lane_timing/shared_emit_worker_a/RESULTS.json`；未重复完整HD测试。
