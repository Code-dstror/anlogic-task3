# 给Linux队友：本轮如何调试与留证

## 本轮目的和最少适配

本次使用 `1a5603c1 / seed25`，重点验证 **双目HDR能否由30/20提升到每眼约30FPS，同时回归首次/反复彩色→HDR启动**，再回归HE/去雾等全模式。全模式控制与同owner API详见[RK_DEBUG_GUIDE.md](RK_DEBUG_GUIDE.md)，版本差异另见[CHANGES_FROM_41cb5991.md](CHANGES_FROM_41cb5991.md)。

1. JPEG/CFG业务协议与8258220f保持一致，优先复用上次已经完成BOOT兼容、N2驱动、分眼接收/MPP/同屏的私有R2运行时，保持原10秒CFG预算做对照。不要同时启动第二个BAR/DMA owner。
2. FPGA UART继续DJ/v3，使用本包 `rk_support/tools/uart_observer.py` 或上版同SHA的解析器，不需要新的业务协议适配。更早只支持DJ/v1/v2的解析器仍不能用。v3没有`pixel.fs`，使用下文的配置epoch和capture_admit字段。
3. 本包固定通用SDK仍保留 `SharedDebugSession.prepare()` 的 v2/192 冷态检查，而FPGA合法BOOT默认是RCD2 v1/64。不要直接用未适配的通用shared shell做冷启动。复用已匹配私有ColdSession，或用全功能手册里的直接同fd API取得一次真实SELECT v4/2112正回执。初始schema2 mask缺省、库路径等既往Linux修正继续保留。
4. RAW仍需FA8/FAC白名单和ARAW解析；本轮未改RAW驱动。包内附源码候选，无新KO。仅在目标内核/build-id/工具链匹配的环境构建和使用，不将源码哈希当作已加载KO身份。

记录本轮实际下载bit的SHA、下载回执、boot_id/run_id、PCI BDF、设备节点、KO/kernel/app/SDK身份及测试时间。物理链路、DDR、传感器状态以新现场为准，旧bit成功不签核本bit。

已有参数发现与边界说明见 [RK_PARAMETERS.md](RK_PARAMETERS.md)，新SDK仅补全原接口目录，不新增线字段。首轮沿用旧Q75/HDR策略，先隔离吞吐修复效果，再单独调整质量/预算/阈值。

## 推荐执行顺序

| 顺序 | 操作 | 通过条件 |
|---|---|---|
| 1 | 新共同冷轮，提前开始FPGA UART采集；单目JPEG plain，再双目JPEG plain（独立冷轮） | BOOT/拓扑/SELECT/session一致；各参与眼至少一条1920×1080合法记录从DMA到解析终态；CAM0/CAM1遮挡对应正确 |
| 2 | 双目彩色首次 `mode hdr`，确认后 `mode sdr`，重复进入HDR | 两眼SYS配方写完后都完成八好pair资格，phase进入7、stable成立；四路新准入开始、PIX已发布epoch和USER ACTIVE推进，有两眼真实HDR产品 |
| 3 | 按旧现场做6轮 `mode sdr he` → `mode sdr dehaze` → `mode sdr`，然后进入HDR；另回归 `hdr`→`sdr dehaze`→`hdr` | 每笔真实APPLIED及两眼新epoch确认；排查先前第19/21笔条件，不把18/20次成功当操作次数上限 |
| 4 | 累计至少20笔模式请求，涵盖HDR多次退出与重入，并保留每笔完整记录 | 不出现相同序号长期BUSY/旧ACTIVE；不靠增加超时、自动重发或热重开规避；同时保留首帧真实序号，启动孤立SHORT可被丢弃但不能重编号 |
| 5 | 全功能表逐项验证 | `TEST_RESULTS.csv` 和全功能手册所列单/双目SDR、灰度、高斯、HE、去雾、HDR，单目原车道，RAW单/双目及冷回JPEG分别留证 |
| 6 | 正常模式已确认后取持续窗口 | SDR/RAW单目目标60、双目各30；HDR各30。建议至少两个独立的5分钟HDR窗口，并分别记录两眼真实新SOURCE、产品和退休，不计公共输出重复旧图 |

以上`mode`文字是现有匹配控制器的模式指令。若走直接API，使用全功能手册的 `apply_jpeg_mode()`，由单一CFG worker调用，同时接收线程继续消费并按原租约归还。HDR参数使用上次审定的完整JSON，不在排查时随意改曝光/计时阈值。本版保留旧孤立SHORT启动修复、八个连续好pair和两眼稳定门槛；新增双像素T96与HDR响应预取，并合入SOURCE/JPEG复位数据资格时序修正。

去雾`requested=1`不代表这一帧一定`applied=1`；初次进入/历史失效允许恒等帧。两眼分别保存首个实际DEHAZE_FILTERED、稳态实际应用数量及画面样本。HDR合并位与去雾位分别核对。车道有零候选场景，终态正确、叠加正确与识别准确率分别判定。

## FPGA串口采集方法

FPGA只发送诊断，115200、8数据位、无校验、1停止位，无软件/硬件流控。保持原已验接线和电平；不向FPGA串口发送控制数据。这个固定采集脚本的实时入口限定 **Windows COM12**，并明确拒绝RK控制口COM7；不要把`--port`误当通用串口回退选项。

在已确认COM12确为FPGA TX的Windows采集机上，从解包目录执行（本包未执行这些设备操作）：

```powershell
New-Item -ItemType Directory -Force captures | Out-Null
python rk_support/tools/uart_observer.py --listen --port COM12 --seconds 900 --pixel-layout stereo --capture captures/run01.bin > captures/run01.jsonl 2> captures/run01.stderr
```

单目改为`--pixel-layout mono`。每轮换新文件名，保留原始bin；要覆盖共同冷启动，先启动只收采集再由设备负责人走既有上电/下载流程。若Linux队友在其他机器采串口，用已确认端口的既有只收工具存原始字节，再用本包脚本离线解析；本脚本的`--input`跨平台、不打开设备、不需要串口驱动。

```sh
python3 -B rk_support/tools/uart_observer.py --input captures/run01.bin --pixel-layout stereo > captures/run01_offline.jsonl 2> captures/run01_offline.stderr
```

OB/v2每包29B，DJ/v3每包68B，一轮共97B。包间隔沿用约1秒观测，不是逐周期trace。CRC错误、尾部残片和丢样要单列；不能用坏包或不新鲜页进行精确对账。

## 应接收和记录哪些信息

| 输出键/信息 | 本轮用途 |
|---|---|
| DJ `version=3`, `fresh_mask`, `reset_n_mask` | DFI是bit0、PIX是bit1；只使用fresh&reset_n有效的对应页。SYS配置在UART FREEZE另取样，不是同一瞬间 |
| `pixel.epoch` | capture端已使用的目标epoch |
| `pixel.cfg_applied_epoch` | PIX配置引擎已确认发布的epoch；与USER BAR的ACTIVE再做对照，正常存在短暂跨域复制延迟 |
| `pixel.cfg_state` | 0IDLE，1WAIT_IDLE，2PREPARED，3WAIT_FRAME，4BOOT_BARRIER，5FAULT |
| `pixel.cfg_gates` | `remote_pending/sent/applied/fault`、`frame_apply_eligible`、`response_space/active`、`source_ready`、实时`frame_accept` |
| `pixel.quiet` | `cfg_pipeline`, `physical_source`, `maintenance`, `native_pipeline`，定位哪项旧工作排空资格仍未成立 |
| `pixel.capture_admit` | HDR顺序CAM0 LONG、CAM0 SHORT、CAM1 LONG、CAM1 SHORT；SDR为CAM0、CAM1、0、0。替代把旧FS计数当HDR全部活动的错误口径 |
| `dfi.epoch/session`, `jobs`, `last_source` | 各眼实际接作业及身份；数字0本身不证明从未处理，结合计数/窗口 |
| `dfi.begin_reject`, `pair_expire`, `bad_finish`, `bank_states` | 各眼聚合拒收、超时、负终态及bank所有权。拒收不等同某一种丢帧原因，需和实际产品关联 |
| `sensor_sys[0/1]` | index、phase、clock_locked、source_fault、written、stable、error、i2c_error；检查切换时传感器重新配置是否完成 |
| OB `sys_status`、三域`domains` | APP/ARM/BME/buffer资格、DDR状态、JPEG/RAW忙闲、descriptor/retire计数和粘滞fault。双目必须stereo布局，不能套单目PIX标志名 |

详细位表见[UART_FIELD_V3.md](UART_FIELD_V3.md)。job/admit是16bit、拒收/超时/负FINISH是8bit模数计数；RUN上升清零并含同沿事件，模式切换不清，RUN关后保持。连续样本可确定未多圈时才累加差分。新v3没有`pixel.fs`，这不是相机停帧。

## 异常时如何分层判断

| 长期冻结表现 | 优先证据 |
|---|---|
| WAIT_IDLE，target和applied都旧 | 先看四项quiet及DFI真实债务；若physical不静默，关联旧HDR SOURCE/入口；不能仅因credit_reserved=1判故障，它可能是未使用的合法预留 |
| WAIT_FRAME，remote_sent=1/applied=0 | 等远端whole ACK；局部DFI或PIX target epoch更新不能代替整包确认 |
| WAIT_FRAME，remote_applied=1/eligible=1 | 查真实CAM0新配置准入；应不再被新处理忙闲阻挡。UART瞬时frame_accept=0不能证明没出现过脉冲 |
| PIX cfg_applied_epoch新，USER ACTIVE长期旧 | 保存响应/ACTIVE复制相关BAR状态、response_active/space、SDK等待日志；短暂不同是跨域延迟，长期不同需定位 |
| 新epoch记录已收到、host held=2、buffer_armed=0 | 先确认CFG是否已真正APPLIED。不能绕过SDK校验直接交付未确认epoch，也不能将之后的N2背压断流直接当成去雾算法故障 |
| 模式确认正常但HDR约25/25或30/20 | 另行按四路准入→各眼job→完整产品→退休同窗统计，记录拒收、bank状态、租约归还和解码丢帧；本轮已修改确定的吞吐瓶颈，若仍出现此现象请保存同窗数据继续定位 |

出现超时后保留原owner的故障状态和原保护STOP结果；不要追加APPLY/CANCEL/STOP、第二fd或同boot热重开。新测试由负责人走既有共同冷恢复。完整留证：bit/程序身份，所有请求/响应时间，CFG_STATUS/ERROR/REQUEST_SEQUENCE/RESPONSE_SEQUENCE/session/epoch/APPLIED_FIRST_SEQUENCE及SHADOW/ACTIVE各32字，owner held/pending、native submitted/completed/leased/quarantined、最近每眼完整记录、UART原始bin、预览/录像状态。网页CANCELLED_BY_STOP是错误后的同步状态，不能直接等同FPGA收到了CANCEL。

## 结果填写

新bit所有板级项从NOT_RUN开始。通过须有真实首事务、模式确认、两眼正确身份及恢复/正常收尾；观察违背合同记FAIL，设备/驱动阻塞记BLOCKED，缺关键证据记UNKNOWN。像素/画质、持续FPS、RK ISP和HDMI分别判定。测试完将填写后的CSV、UART、原始记录及相关日志一起回交，保留失败现场而非只截HUD。
