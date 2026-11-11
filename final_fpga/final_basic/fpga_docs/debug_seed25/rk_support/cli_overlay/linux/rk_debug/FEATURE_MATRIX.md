# r3实际连接功能与RK调试边界

本审计绑定源提交`8e2eecfcfc7c956f8a7c3c88a6323a23a2360c99`，工程
[`s3p95_r3.al`](../../fpga_prj/s3p95_r3.al)，顶层`anlogic2026`。依据为
[正式交接](../../docs/coordination/stage3-implementation-20261016.md)、
[r3显式清单](../../src_fpga/stages/r8_stage3/pending/area95_20261016/r3/SOURCE_MANIFEST.json)及
[实际MAIN资格](../../src_fpga/stages/r8_stage3/pending/area95_20261016/validation_lz_r3/qualification.json)。
逐字节核对了42份所审镜像源，全部匹配清单；路径、SHA和声明保存在
[source_contract.json](source_contract.json)。这是选定源的静态连接审计，未重新仿真、构建或上板。

工程的真实源在`src_fpga/stages/r8_stage3/p95/r3/`镜像内，不把同名活动开发文件当作实际编译输入。
本页提到的文件名均可由JSON的`selected_sources`解析到唯一实际路径。**source hash不是固件ID**；
当前通用magic/capability不能证明板上加载了这个提交，不能生成虚假的image/build标识。

## 固定编译选择

| 项目 | r3实际值与影响 |
|---|---|
| 器件/工具/顶层 | PH1A90SEG324-2；TD6.2.3.210850；anlogic2026 |
| 几何/相机数 | COMPILED_PROFILE=1，1920×1080，camera0一台；4K/双摄分支不是当前可用功能 |
| 源选择 | `ANLOGIC_SOURCE_SELECT=3`：普通SDR走物理camera0入口；HDR模式走虚拟LONG/SHORT LAB输入。它是编译期选择，不是CSR可改的物理HDRrecipe |
| 资源配置 | R8_STAGE1、R8_BASIC_PREPROCESS、R8_LIVE_F21、HE/F21_FIXED_CONFIG_SESSION、COMPACT_TRANSPORT、S04、S08均启用 |
| 配置能力 | schema1扩展支持掩码0x3c；schema2模式掩码0x7、使能掩码0x3f；不是任意扩展字段都可写 |
| 不在活动路径 | NR_PROCESSING_ENABLE=0；S07_PROCESSING_ENABLE=0；F24_MASK_ENABLE=0；旧RAW host窗口RAW_ENABLE=0 |
| 生产调试接口 | DEBUG_UART_ENABLE=0；UART TX绑高，无IDENT/TRACE/在线WB命令；stage3_production_boot自动完成冷态准备 |

TOP关键位置：参数与派生能力11–176；u_config约992；LIVE图像链1898起；F24/F25绑零2033–2034；
新RAW/LZ绑定1301起及3771起；software reset fence3905起；应用CSR4110起；生产启动4428起。
精确字节身份优先于行号；后续源若不同，本页不可继承。

## 完整功能矩阵

“运行时”表示RTL路径有真实配置/握手，不表示当前RK驱动放行全部CSR，也不表示板级资格。

| 功能 | r3实际连接与参数 | 分类／调试成功依据 |
|---|---|---|
| 图像输入与ISP | IMX415/cropped RAW10、已固定Bayer/增益/WB、真实SOURCE终止与颜色链；SOURCE_SELECT=3另有HDR虚拟源 | 几何、输入选择、生产WB为编译期。物理输入的曝光/gain/calibration资格不能由寄存器名称推断 |
| 基础JPEG策略 | Q=1..100；min Q=1..requested；adaptive=0/1；budget=0..16,777,216，adaptive要求非零；restart=0..65535 | 运行时CFG。完成JPEG长度反馈：超预算最多降5至min，连续低于75%预算三帧可升1至requested；看实际quality/长度，不把budget当恒定输出大小 |
| schema1基础模式 | COLOR、GRAY、GAUSSIAN、HISTOGRAM；保留旧语义与合法扩展形式 | 运行时基础选择；不是schema2独立enable位的别名 |
| schema1扩展 | HDR策略保留ratio/数值/资格位与timers；dehaze LUT generation可选；F21/F22/F23只接受编译出的完整preset | 运行时选择受限。F22/F23为旧paired preset且要求GAUSSIAN模式；任意改threshold/ROI/省略word不是“灵活调参” |
| schema2产品模式 | MONO_SDR、MONO_SDR_LZ、MONO_HDR；HDR_LZ_CONFLICT拒绝；基础mode必须COLOR | 运行时guarded CFG。HDR当前是LAB数字模式；HDR与LZ不并用 |
| schema2独立图像/分析使能 | 六位：gray、dehaze、filter、HE、multiscale、lane；lane必须同时multiscale | 运行时独立使能。filter不等同灰度，multiscale/lane不应隐式改变灰度位。真实路径为共享post-F21 filter |
| schema2扩展参数 | 完整32word扫描；只允许schema/mode/enables、HDR数值/资格/timers、dehaze generation；其他位必须0 | 算法参数从固定preset重建；不能把schema1的ROI/滤波字段直接塞入schema2 |
| F20 neutral统计 | 原增强前被真实接收的采样网格，经SOURCE owner核验后进入record metadata；1080p对应320×180采样 | 已连接；不是独立像素修改开关。record-v2/v3查看完整count/min/max/sum及来源，缺失/失败不得补零当成功 |
| F21 dehaze | 已连接LIVE F21、LUT generation/lease、neutral观察与合格历史；固定算法profile | enable与LUT内容/generation可运行时管理；系数profile固定。请求enable不证明本帧真正用到合格历史map |
| HE | 已连接原灰度/颜色保留与SOURCE合格history路径；固定session策略 | enable可调；history上下文、取消和epoch有真实门槛。首帧/无合格历史不得宣称使用了增强LUT |
| 彩色轻滤波 | `stage3_filter_color_analysis4`与真实LIVE pipeline共享窗口、持有token及cancel | schema2 filter独立控制；算术/边界profile固定，不提供任意kernel在线上传 |
| F22 multiscale | 共享post-F21分析路径，输出F22稀疏记录；r3 MAIN独立检查包含F22 | 运行时enable，数值profile固定；record-v3按同帧有效记录检查，不把CSR enable当结果 |
| F23 lane candidates | 共享post-F21分析路径，输出固定条带/ROI的候选统计；schema2可在F22上启用 | 已连接、运行时enable。不是主机AI车道识别或距离估计；本次r3单帧scene不单独证明所有F23组合 |
| F24 mask | top参数关闭，S07活动分支关闭，LIVE分支valid/data绑零 | 当前未接入；不能因仓库存在模块或v3保留字段而宣称可用 |
| F25 | 仅不活动的S07分支有接口；当前LIVE分支valid/data绑零 | 当前未接入；不应提供“启用F25成功”的命令 |
| 原始RAW管理 | 捕获写入、实际END及B响应、HDR/SDR所有者、读/释放均真实接入 | 内部功能；RAW_ENABLE=0，旧host QUERY/PIN/FETCH/REPLAY窗口不开放 |
| LZC1无损输出 | SDR隔帧选择、完整RAW10捕获、CRC/无收益RAW回退、16chunks/1,013blocks、native退休后释放 | 运行时SDR_LZ模式；完整还原恰2,592,000B。capture_time/Bayer/validity及错误terminal照真实header处理；未证明持续LZ30 |
| HDR数字后端 | 同camera LONG/SHORT目录、原子pin、完整配对、RAW14处理、共同Tone96、最终JPEG及真实退休 | LAB可达；ratio1..4等政策受校验。r3没有物理传感器recipe/生效帧资格，不能靠host填写资格位伪造 |
| JPEG record选择 | v1/v2/v3为64/192/448B头；真实USER命令→DFI决策→ACK，session/request/selection epoch一致 | 冷态/严格quiet受限。产品CFG切换不需也不应重复SELECT；F20/SOURCE用v2/v3，F22/F23用v3 |
| LUT管理 | ALGO命令/逐项数据/commit与真实pixel回执、generation和lease保护连接 | 运行时受限；只有load_permitted/算法quiet及匹配generation才可更新，不能边消费旧map边替换 |
| native C2H | 独占descriptor、完整128位身份、MWr、MRd fence、SAFE_RESULT、matching ACK、JPEG/LZ仲裁和CDC退休 | 运行时专用驱动所有者；C2H STOP/ACK不是全FPGA清空，掉链/BME异常保持quarantine |
| 应用诊断 | magic/version/capability、STATUS、CFG/ALGO/RECORD状态；部分JPEG ring诊断有RTL服务 | 先区分CSR确有连接与当前驱动白名单；不能用旧BAR物理地址或/dev/mem旁路 |
| TEST/H2C/部分计数 | TEST_LENGTH/PATTERN/TRIGGER有寄存器壳但top输出不使用；H2C数据输入绑0；base DROP/OVERFLOW输入0 | 不是当前真实payload测试器或H2C通道；0计数不能证明“无掉帧” |
| 软件reset | CONTROL bit1进入有序DRAIN/EXECUTE/WAIT_BOOT fence；不直接清product/cold ownership | 原生产driver禁止CONTROL任意写；本套件另有[独立受限debug扩展](driver/README.md)，默认禁用，必须正常pause、显式审核合同并观察新BOOT；匹配内核构建BLOCKED，实际复位NOT_RUN |

固定F22/F23 preset例：四条带，threshold40、gx_min1、ratio_shift3、min_count1；Y边界
0/67/135/202/270，ROI split240/right480。它们是编译选择，不是尚待填写的任意ROI参数。
完整固定67bit F21设置与所有32word校验以所绑`legacy_stage2_config_transport.vh`、
`mono_config_scan_v2.v`为准，catalog应引用这些源而非放宽为通用手册中的参数全集。

## 产品切换的真实顺序与可见证据

### 普通CFG路径已有硬件所有权门槛

1. `mono_config_engine_v2` PREPARE进入WAIT_IDLE，暂停新工作；只在pipeline_idle时PREPARED。
   COMMIT必须复用完整prepared tuple，随后进入WAIT_FRAME并发送remote tuple，不能用缩短的参数重提交。
2. frontend配置/PIX LUT lease/DFI job配置逐层确认；`full_raw_store` CFG_SELECT不能提前给APPLY ACK。
   HDR与LZ同时启用直接拒绝。
3. `full_raw_capture_frontend`停止新选择后，PIX冻结已产生token计数并握手返回DFI；只有
   produced/consumed fence相等、FIFO无dequeue、writer quiet及policy quiet才能select_ready。
   不是等两个周期或只观察FIFO empty。
4. `all_policy_quiet`还要求HDR与SDR owner空、读口quiet、product quiet、ticket释放、LZ region quiet且无fault。
   顶层LZ region包含LZ service quiet、source CDC清、USER无busy/native bound和RAW/LZ AXI仲裁quiet。
5. 实际切路、像素配置ACK及owner配置完成后才返whole remote ACK。新接受帧边界满足条件时，engine
   才更新epoch并给APPLIED。主机核对session/request/epoch、完整active tuple及新record真实来源。

**静态结论：普通PREPARE/COMMIT在持续receive/SAFE退休下有足够的内部门槛来阻止工作区在旧owner
未退役时切换；源码路径不要求先software reset。** SDR↔SDR_LZ↔LAB_HDR及LZ模式内配置epoch改变
都要服从这些门槛。这里没有新增跨模式仿真/板测，不能写成“所有切换场景已验证”。

对RK实施的必要约束：

- 保持唯一C2H owner和接收/释放路径运行，以便旧JPEG/LZ继续SAFE退休；先停止host grants可能让
  LZ尾部无法完成，不能把“STOP了，所以空了”作为切换许可。
- 保持记录格式和native transport session；只改变受审CFG tuple，不卸载模块、不重建owner、
  不reset来绕过超时。超时/错误意味着未确定，不是回滚成功或可重复COMMIT。
- **APPLIED不代表用户已读尽旧epoch。** native ACK可早于内核READY交给用户；旧epoch尾chunks或
  terminal可能随后才被读出。按实际record session/epoch/generation维护解码归属，不在APPLIED时
  清空旧LZ assembly或把它重新贴成新epoch。新decoder由实际记录驱动转代，完整帧与失败terminal分别处理。
- 新suite的transition许可应绑定baseline session/epoch/full tuple、proposal digest、唯一owner与
  持续排空策略；不能用`force=True`代替证据。旧Linux运行层的模式限制不由本审计自动修改。

### CSR可以证明的范围

CFG PREPARED/APPLIED、匹配response与完整active tuple能证明事务阶段；record内SOURCE和处理字段能
证明该记录属于哪代。RECORD_STATUS只说明记录选择事务owned/done/failed，不是RAW/LZ全局排空位。
普通STATUS只有link/user-reset/C2H-running/TX-busy/SOURCE-busy/error/rearm/armed；没有raw owner空、
marker计数相等、LZ尾部清空或reset-fence状态。driver GET_INFO计数也只属于host transport。

因此可以以**硬件返回的完整CFG ACK路径**作为该次受限事务的依据；不能用几个idle位自行重构或
伪造同等全局证明。普通CFG不代表旧host队列消失，也不代表新曝光发生在COMMIT之后。

### 有序software reset的单独边界

`production_soft_reset_fence`等待PIX/DFI pause ACK、各域quiet、token drain proof连续确认，才进入
EXECUTE；实际pixel data reset被观察到后进入WAIT_BOOT，最后等待非零新CFG session与rearm才结束。
没有timeout强行完成。top的product_cold_reset_n只来自冷态启动，不跟APP soft reset/PERST/link走。

reset_pending、token proof和RAW计数在当前应用CSR没有直接出口；SOURCE session改变加rearm只是
完成后的观察，不赋予主机跨越异常owner的权限。现有`c2h_legacy_policy`不允许CONTROL写；START/STOP
内部只写APP_ENABLE 1/0。软件reset当前应报告`RTL_CONNECTED_HOST_API_BLOCKED`，不能通过裸BAR绕过。

## 现有验证和调试器必须保留的缺项

r3 `validation_lz_r3`为1,149,985检查、1JPEG+16LZ chunks，独立检查全部2,073,600像素、F20/F22、
50,464B JPEG及2,592,000B RAW恢复/CRC/身份。刺激是一帧synthetic physical CSI-word，并非实物传感器。
它不证明持续SDR60/HDR30/LZ30、不证明每个F23/配置组合、物理HDR、全部模式转移或板级。

编译期关闭、CSR壳未连接、当前driver不开放、缺物理资格必须分别报告；不能把它们都写成PASS或
同一种“暂未测试”。本轮只完成源与连接审计，未修改FPGA/协议/驱动，未向FPGA对话发送消息。
