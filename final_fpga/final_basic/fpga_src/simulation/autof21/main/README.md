# 自动 F21 的 TOP 与数值验证

`run_main.py --mode sdr --autof21-short` 通过真实 TOP 的 BAR/CFG、CSI
word 电气边界和实际接收/处理 owner，验证 G0 ON→OFF→ON 的三次真实 APPLIED、
G1 PREPARE 接受/G2 拒绝、真实 PERST 冷复位后固定 G1 自动可用、两次负 SOURCE
以及 SOURCE5 的恢复 processed SOF。整个场景没有 ALGO BAR 写入，内部 loader
begin/word/commit 也必须始终为零。它在恢复帧输出 SOF 后结束，没有完整 JPEG
或前帧去雾历史的数值资格。

`run_history.py` 默认短 smoke：四次前景服务，每次两行；仍提交三次完整
320×180 原始观察，对 432 个 map tile 和实际插值 RGB/Y 独立逐字比较。
`--full-hd` 则是四个完整 1920×1080 前景帧，后三帧实际使用三份不同历史，
包括双线性插值、保护、截断、最终拍 stall 与三次 pin 释放。原始观察与前景像素
均由确定性输入生成，不从 DUT 输出生成 expected。

标量权威从既有根目录 `preprocess_dehaze_reference.py`、官方指导
`numerics.py` 与 `tables_1920.json` 逐字复制到 `oracle/`；来源和 SHA256 在
`oracle/PROVENANCE.json`。原冻结 `verification_reference/` 未修改。
运行时只读取候选内的这些权威，每次把实际 RTL/IP、TD 模型、数值权威、MIF
与生成输入的绝对路径/哈希写入 source identity，结束前复核。

长组合入口 `run_batch.py` 同时运行完整 SDR F22/F23、HDR、SOURCE 坏帧恢复
MAIN 及其独立完整 JPEG oracle，以及完整 HD F21 多帧数值测试。它只按子进程
结束事件等待，不查询服务器。长组合须在根任务冻结源后启动，不能把短 smoke
当成完整 HD 结果。所有 runner 必须显式指定 `--td-root` 与 `--modelsim-bin`。

这些验证不启动综合、P&R、时序收敛或板级操作；各自保持 NOT_RUN。
