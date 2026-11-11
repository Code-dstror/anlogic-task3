# 双SDR RAW存储与共享回放合同

## RAW 产品的公开握手补充（2026-11-07）

RAW 产品使用同一个目录、槽和 reader。BEGIN 的 `o_begin_accepted` 是
响应结果电平，必须与 `s_begin_valid && s_begin_ready` 同拍解释，不是单拍事件。
无可用槽时允许返回 `accepted=0`，相机不能靠等待无限延长帧输入；重试需要新的
BEGIN 请求。`o_capture_slot` 只在接受的响应中有效。

`o_job_frame` 保持旧处理描述符格式，清除 `[383:367]` 扩展位和 bit0；冻结的 Bayer
与时间有效标志由 `o_job_bayer`、`o_job_time_valid` 返回，RAW 头使用这些边带。
冷空闲以 `o_empty` 和 `o_read_quiet` 判定，`o_raw_drained` 只证明一个已接受的
RAW 读事务完成排空，不能要求它在冷空闲时为高。

匹配的 RAW SAFE 回执接收与最终槽退休是两阶段：`i_raw_retire_valid &&
o_raw_retire_ready` 接收回执，`o_retire_done` 才表示目录所有者释放槽。
`i_release_quiet=0` 时可以先接收 SAFE，但必须保留槽占用；quiet 恢复后再完成退休。
错身份 SAFE 不能被接收。记录身份至少保持到匹配 SAFE 握手，槽在最终退休前不可复用。

下面 donor 的历史实现和验证边界按其固定源码理解；本项目的默认双目 D2 已改为
传感器 SDR30、内部捕获 DIV1，当前结果见工程 README 和本轮源码绑定回执。

合同来自固定 `6effdfaef6:refactor/dual_basic`。本文末尾验证数字为 donor
历史记录，不是本候选资格；本候选使用独立运行目录、源码身份与验证记录。

本实现只支持两个独立的视频来源，不证明曝光同步或光学Stereo Pair。单目HDR仍由原HDR目录、读服务和数值链负责；模式必须在外部受控冷会话边界选择，不得在捕获、AXI、job或共享FIFO在途时改变。

## 数据和时钟

- 两路输入在PIX125MHz各自使用40bit native RAW10，低10bit为先到像素。每4像素紧密打包5字节，没有行padding。valid/accept/SOF/EOL/abort与来源身份共同推进。
- `full_raw_capture_frontend`各保留一个真实147bit厂商异步FIFO；DDR写入和目录在DFI域，仍按128bit/16bit WSTRB传输。最大16拍burst，不跨4KiB；只有真实B响应和匹配的SOURCE成功才能提交完整帧。
- `STEREO_CAPTURE_DIVISOR`默认4，仅对Stereo新SOF准入生效；物理FS、入选帧分别计数。两眼独立选帧，不由此推导同步Pair。值1用于低帧率物理源或数字验证。模式选择通过前端本域同步后只影响新SOF。
- CSI无法无限反压。FIFO溢出/坏帧/丢失SOURCE使该帧失败；不能靠FIFO容量宣称长期吞吐。正常消费与取消均保留已呈现的token、AR、W和完整身份直到握手。

## 实际存储布局与目录

每眼使用原RAW区域的前两个16MiB槽：cam0为0x02000000/0x03000000，cam1为0x06000000/0x07000000；完整1080p RAW10有效长度2,592,000B。地址stride不是有效帧长。原其它RAW地址、JPEG六个显式槽及父工程布局不移动。

`stereo_raw_owner`使用一份现有`hdr_pair_directory`冷RAM，四条目×16个32bit字。它复用存储叶而不复用HDR长短曝光语义。槽状态为FREE→WRITING→READY→OWNED→FREE；每眼捕获独立，metadata写端口与job读取串行仲裁。没有通过复制整套公共RAW服务恢复host FETCH或BAR能力。

目录写入时借用writer在BEGIN握手前保持的完整descriptor。32bit generation分配后不回退，耗尽后拒绝新捕获，不允许回绕；lease为该非零generation的64bit零扩展。job_id为`0x8000000000000000 | lease`，与现有低位HDR pair编号分离。session/epoch必须等于已应用配置，由外部提供，不在本模块生成。

SDR capture descriptor扩展位由原`shared_raw10_frame_ingress`生成：371=time_valid，370=bayer_valid，369:368=Bayer，367=exposure metadata_valid。当前owner要求Bayer有效；从目录额外返回冻结的Bayer/time_valid sideband。给旧processing owner的384bit descriptor清除这些扩展位，bit0明确为0，不宣称Pair qualification；camera/source/session/epoch/sequence/timestamp及其它已有字段保留。曝光metadata未知不会阻止合法视频提交。

READY尚未对下游呈现时可以在STOP丢弃；一旦job VALID呈现，descriptor/lease/job保持，不能因STOP撤回。接收job后必须走读/处理/退休，不能用超时释放。失败的单侧帧不发布job，不阻止另一眼的独立目录。

## 单帧job与private读

首版每个job固定kind=MONO1、pair_id=0、member_index=0，camera仍来自真实descriptor[4]。`raw_pair_job_service`在`STEREO_ENABLE=1`时启用现有`raw_pair_replay_scheduler`，同一`raw_pair_processing_service`继续拥有唯一ticket/context/实际JPEG写完成回程。`NORMAL_REPLAY_ENABLE=0`保留父候选已裁剪的normal常量分支；HDR状态机不改。

private REPLAY=4必须匹配已被接受的活跃job：camera/slot/generation/session/lease/job全部相等。只是RAM还保留旧descriptor不构成重放权。只有一个private读在途；响应ready/valid独立保持。private RETIRE=5在真实读生产结束及真实processing完成后才成功，slot的job owner仍需单独精确退休。

STOP不拒绝上述精确活跃job的首次REPLAY：processing context可能已经被PIX接收，必须得到真实负终态。STOP已生效且读尚未启动时，reader按取消启动，不呈现AR、不输出DATA，仅输出零组失败FENCE；错误身份仍返回拒绝，不产生token。`full_raw_store.o_private_ownership_quiescent`同时要求HDR和Stereo所有权为空；未启用Stereo的配置将Stereo empty固定为1，保留单目静默语义。

`stereo_raw_reader`只有一个在途AR。取消不能撤回已呈现的AR；接受后的burst必须收到R终态。正常RRESP错误产生失败FENCE；RID/RLAST协议形状错误进入quarantine，不伪造总线静默或成功释放。内部RAW10解包后逐lane零扩展为14bit，按现有共享transport格式输出：

- DATA：`{kind2=0, reserved9=0, bad1=0, index32, last, eol, sof, keep4, zero40, raw56}`。
- FENCE：`{kind2=1, zero40, error8, ok1, job_id64, groups32}`。

此输出选择进入`full_raw_store`已有唯一DFI→PIX replay FIFO，使用现有HDR transport的通用sink和唯一外部ISP/JPEG。Stereo的sink phase必须按实际job拥有期拉高，消费FENCE/上下文后回到低相位，不能直接永久绑Stereo mode。正常SDR数值选择`cfg_hdr=0`。

**read_quiet与read lease分别表示不同事实。** read_quiet在AR/R及payload生产确实结束时成立，供ticket完成读取；private read lease仍保持。只有已有processing-result回程证明PIX SOURCE/FENCE消费、ISP/JPEG排空及最终JPEG B结果后，后端才返回nativeDone，再允许private RETIRE和job释放。这不会把“FENCE已入FIFO”当作PIX完成，也避免read lease等待processing结果形成循环。

owner退休还必须满足共同read/product/ticket/write quiet。RETIRE ready不等于done；错误job id只返回错误、不释放当前槽。共同冷复位是外部协调回收/DDR恢复边界，不是本模块制造的成功退休事件。

## 验证边界

`src_fpga/simulation/stereo_store/run.py`使用明确TD6.2.3.210850模型和ModelSim，真实官方capture/replay FIFO和目录RAM。store_r10的DIV1、DIV4各44,230检查、scheduler28检查、STOP-before-REPLAY 4,430检查及真实full-store所有权静默72检查全部通过；原始源SHA与日志在候选`tmp/stereo_store/store_r10/`。测试覆盖4KiB/尾KEEP、双源字节/像素、随机有限反压、末拍stall、迟到B、独立坏SOURCE/B、RRESP错误、取消保持AR、STOP前已接收job的零AR/零DATA负终态、六项错误身份、错误完成/退休、retired描述符拒绝和共同冷复位。自有警告为0，仅保留归类的厂商模型警告；修复前真实失败保留在stop_before_r1/r2及quiescent_r1/r2。

AXI内存与最终processing-result是明确的边界模型；整机RAW→ISP→JPEG→PCIe由独立MAIN验证负责。本文件不把小帧结果扩展为1080p持续帧率、同步Pair、P&R/时序或板级资格。综合、P&R、STA、bitgen、板级在本子任务均NOT_RUN。
