# 最小恢复移植与本轮短测

生产基线fixed `b68fdc2d79b9ae3579174366f0fdce89dfc9f389`，7模块仅移植fixed `b26058dd436afcf0966f2fe643ccbf7664a2e5de`的已验证差异。`PORT_DELTA.patch`和`PORT_IDENTITY.json`逐项保存差异/双源/本轮SHA。没有修改manifest/AL/SDC、共享MAIN入口或任何父候选；未推送、操作服务器或板卡。

| 模块 | 最小行为变化 |
| --- | --- |
| physical_csi_word_core | opt-in SDR新FS恢复序号信任，旧帧身份不重标；first RX只保留首错；计数耗尽严格失败 |
| physical_csi_rx_stream | 原FIFO/CDC/复位结构不变，只透传FRAME_RESYNC_ENABLE参数 |
| real_hdr_physical_csi_rx | 只在SDR stream打开恢复，HDR独立双VC权威不变 |
| production_source_identity_guard | 仅在实际quiet且消费健康FS后解除PIX隔离，不释放产品/DMA owner |
| real_hdr_camera_observe_axis | loss边沿检测在恢复后重装，使同cohort后续故障仍能被报告 |
| anlogic2026 | 旧SOURCE先负退休、分析record实际排空后才清ISP；历史重置延迟到安全恢复边界；不加新的审核状态机 |
| ph1a_rx_delay_scan | acquisition沿计作第一个评分沿，修63/64/65阈值首拍少计 |

## 保持的接口合同

WORD域32bit CSI字、lane0最低byte；RAW10每5byte为4个10bit原像素，公开40bit输出。最大WC65535，RAW10按5byte组检查。FS7/FE6与失败1..5分别计分，身份为valid位+32bit单调SOURCE；行EOL不是成功帧FE或PCIe TLAST。输出只在valid&&ready消费，stall时token/身份保持。CSI不能无限反压，真实溢出须负终结。

identity冷复位与decoder局部复位独立。FRAME_RESYNC_ENABLE默认0保留严格模式；生产仅SDR打开1。坏头否定旧帧，后续认可目标VC FS用更大SOURCE重新建信任；32bit耗尽不wrap。WORD→PIX仍用原官方FIFO和同步复位。PIX隔离只在旧SOURCE/record/已呈现像素均排空并消费健康FS后解除，边界FS不冒充新的成功产品。

## 当前源绑定验证

每项输入先复制到新的运行目录、封印SHA，结束后再次核原件与实际编译快照。ModelSim SE-64 2020.4，本机路径及Python来自ENVIRONMENT.local.md；含官方FIFO模型的runner显式使用TD `D:/App/TD_Release_2026.2.210.850`。不使用`-novopt`。

| 运行目录（候选tmp/recovery下） | 本轮结果 |
| --- | --- |
| word_recovery_r01 | 107+3 checks PASS；坏头/局部复位后的新FS可信 |
| word_strict_r01 | 107+3 PASS；默认严格隔离保持 |
| receiver_matrix_r01 | 43个逐SOURCE RAW/native退休校验PASS；quiet否决、反复4次故障、每旧owner恰好一次退休 |
| physical_r01 | 5392 checks PASS；官方8192 FIFO/crop/router/guard/fence/RAW链，有限输出与SOURCE背压 |
| adversarial_recovery_r01 | 71leaf+2饱和/13,819 checks无不符；22闭环344 checks保留已知SYNC合同probe的2项FAIL |
| adversarial_strict_r01 | 同一95场景严格对照，恢复关闭时维持原失信语义；相同已知probe FAIL2项 |
| short_alias_r01 | 16场景625 checks PASS，全部真实负终结旧SOURCE并恢复新SOURCE |
| scanner_edges_r01 | 7边界PASS，63拍失败/64与65拍成功，含生产TEST_LEN/SETTLE和tap31单码窗口 |

各运行工具警告为0。adversarial的两个已知不符明确归类`PASS_WITH_CONTRACT_EXPOSURE`，原始FAIL保持，不改写PASS。源身份、执行argv和日志路径见`RECOVERY_RESULTS.json`及各目录RESULTS.json。

独立计分复用上轮72leaf+21闭环向量，覆盖24头数据位与6ECC位纠正、不可纠正实际00097e2b、WC65535/非法边界、坏CRC/缺FE/重复FS、VC过滤、有限stall、局部复位、饱和。每个模式新增四轮坏头/CRC+stall+nextFS测试和实测40raw后续恢复，故为73leaf（含2饱和）+22闭环=95场景。常量向量/模板自包含于vectors/templates，不需要外部tmp脚本；原独立ECC/CRC/RAW10生成器SHA来源记录在vectors/PROVENANCE.json。

实际板40 WORD raw输入被候选aligner拒绝后，没有伪造ECC/CRC事件；下一干净FS真实以code5负终结仍打开的旧SOURCE1，再完成SOURCE2的12组独立golden与FE。测试使用真实窗口但前后健康prefix重建测试身份，不宣称重放板端所有绝对状态/电气。

新对齐保护后仍可表示的16类短错位（4lane×lead1/2/3/5）全部真实parser闭环：13例ECC负终结；lane2 lead2/3/5三例CRC负终结。每例SOURCE1恰好一次负终结、无成功FE/EOL，后续SOURCE2的12组数据及FE逐值正确。3个CRC例先输出11个错误RAW组，最后一组扣住；下游必须服从真实负终态，不能将部分像素提交为成功产品。

## 未扩展的边界

已知极短SYNC probe是在真实packet_done的negedge观测边界主动放下一B8 raw字。它缺下一个FE并在短窗口留有open owner；control count/terminal两项FAIL保留。该输入表示重新SYNC的数字burst间隔，不是同HS连续包，也不是IMX415 LP/HS实测。旧gap9丢FE/gap10成功仅限该具体数字相位。没有增加审核/无限等待或擅改HDR以使这个越界probe通过。

foreign非法RAW10 WC6使目标帧保守负终结，而合法VC1/WC10不影响VC0，保留受保护策略。leaf无静默timeout不证明整机挂死；原外层SILENCE_CYCLES/receive_fault→abort仍在。HDR连续短包/packet_continue由alignment专项验证；完整TOP、STOP、JOIN/record/writer及完整JPEG由主MAIN负责，不用这些叶测试替代。

本轮生产逻辑只改上述7项。本地功能为上述源绑定范围；综合/P&R/STA/bitgen/板级NOT_RUN，不移植旧bit资格。
