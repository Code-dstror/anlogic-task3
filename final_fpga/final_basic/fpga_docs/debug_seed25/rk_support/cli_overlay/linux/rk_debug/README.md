# RK3576 FPGA 调试套件

这是独立的调试程序目录，复用仓库已有严格解析器、原生LZ库、C2H Receiver和MPP封装，
不改旧生产运行入口。流启动、配置与受限source-reset都由明确的`run/shell`会话发起；
`display-info`另做显式只读显示查询。导入、帮助、catalog、文件inspect均不打开DMA设备。
当前开发板未连接，本文不把脱板结果称为RK板测通过。

FPGA功能基准为已选定r3（源`8e2eecfcfc7c956f8a7c3c88a6323a23a2360c99`、`s3p95_r3.al`）。
参考聊天「FPGA工作-final」只读使用，没有向其发送询问。后续时序实现可能更换内部源，
调试时仍以实际只读能力、完整CFG回执和每条记录身份为准，不把本地source hash当固件ID。
收尾时已只读核对更新至`d2a4d0bb2`的C1/C2时序候选：RK交互协议保持冻结；本程序实际CLI
也检查了最新C2的JPEG＋LZ输出。后续候选仍须沿用该协议门，不能仅凭候选名字转移板级资格。

## 能测试什么

完整来源审计见[FEATURE_MATRIX.md](FEATURE_MATRIX.md)和[source_contract.json](source_contract.json)。

| 内容 | 程序入口与观察 |
|---|---|
| JPEG v1/v2/v3 | 显式冷态记录选择；完整长度/marker/SOURCE检查，按同epoch统计，保存完整`.ajpg`/JPEG |
| JPEG压缩参数 | requested quality、min quality、adaptive flag、byte budget、restart MCU；区分请求/活动配置与实际帧quality |
| 基础图像模式 | COLOR、GRAY、旧灰度GAUSSIAN、HISTOGRAM；受实际能力及schema组合约束 |
| schema2独立处理 | GRAY、DEHAZE、彩色GAUSSIAN_IMAGE、HISTOGRAM、MULTISCALE、LANE，lane依赖multiscale |
| F20/F22/F23 | 同一完整记录中的neutral/sparse摘要和错误终态；不重建不存在的完整分析图像或伪造AI识别 |
| F21 LUT | 先真实APPLIED关闭F21，再按明确新generation加载完整257项及真实COMMIT回执，最后显式启用 |
| SDR／SDR_LZ／HDR | 完整schema2事务；保持接收以便硬件所有者排空，再核实真实APPLIED及新SOURCE产品 |
| HDR policy | ratio、black、motion、qualification mask、64/32/32位timers；当前r3只具备数字LAB HDR源，物理HDR未资格 |
| LZ77 RAW流 | 严格LZC1头、分段/块身份、stored/raw CRC和native解压；全部成功才输出2,592,000B RAW10 |
| HDMI | 完整JPEG送显式MPP封装，再NV12 pack到既有GStreamer/KMS；不强制占plane，不声称stdin完成即屏幕呈现 |
| RAW诊断与存储 | 完整RAW独立保存，可选有限张静态PGM（RAW10值右移2位）；不是ISP/去拜耳或实时RAW HDMI |
| 生命周期 | 同fd启停、正常pause/resume、故障留置；配置超时不重试、不换owner或清DMA隔离 |

当前FPGA的ROI/条带/部分算法系数为编译期preset，catalog会显示其固定值；随意修改这些值会被拒绝。
F24/F25、生产UART、H2C/TEST数据壳、旧RAW host窗口未接入当前运行路径，不能把保留寄存器或
模块文件当成可用功能。USB/4G按用户要求排除，视觉AI模型本体不在本套件中。

## 目录

| 文件 | 职责 |
|---|---|
| `cli.py`、`__main__.py` | 一次运行、交互shell、脚本、状态断言、离线检查 |
| `catalog.py`、`controls.py` | 实际可调范围、完整proposal、只读active、唯一CFG/LUT事务 |
| `session.py`、`transport.py` | 一个Receiver、独立接收与控制worker、安全复制/RELEASE、正常停止 |
| `products.py`、`offline.py` | JPEG/LZ分类、双epoch native owner、CRC/完整帧统计、有界独占导出 |
| `consumers.py` | 有界JPEG解码/HDMI、JPEG/RAW录制、有限静态RAW预览 |
| `display_info.py` | 显式modetest路径的只读connector/plane查询，不切换显示模式 |
| `driver_api.py`、`driver/` | 同fd受限source-reset接口和独立debug驱动候选；默认禁用，匹配内核构建仍BLOCKED |
| `journal.py` | 有界事件与新报告文件；不把图像二进制塞进JSON |
| `examples/` | 完整配置和分步测试模板，运行前审查参数/预算/能力 |
| `driver/`、`driver_api.py` | 默认禁用的受限source reset扩展、精确派生补丁及同fd接口；非PCIe/DMA故障恢复 |
| `fixtures/c2/` | 随Git保存的最新C2合格混合记录样本，无板检查不依赖本机tmp |
| `tests/` | 脱板控制、接收、模式切换、文件产品和CLI边界测试 |

这些源不是自包含复制的SDK：从仓库根目录使用`python3 -B -m linux.rk_debug ...`，保留
`linux/`包的原目录关系。构建库、内核和MPP输入见[现有构建指南](../../docs/linux/BUILD_AND_DELIVERY.md)。

## 无板先运行

以下命令只读源码/文件。输出文件必须是新路径，原始r3仿真产物保持原样。

```sh
python3 -B -m linux.rk_debug --help
python3 -B -m linux.rk_debug catalog --output /actual/new-output/catalog.json
python3 -B -m linux.rk_debug inspect --help
```

最直接的无板试运行见[随附C2样本](fixtures/c2/README.md)：从单个`mixed_records.bin`还原JPEG
和完整RAW，不需要开发板或MPP。Windows使用已构建的Windows native库，RK使用匹配ARM64库。

真实r3资格列出的1条JPEG＋16条LZ位于
`tmp/r8_stage3/area95_20261016/r3_lz_main/`。不是所有名为`actual_record.bin`的文件都为JPEG，
检查器按magic分类且不进行搜索重同步。明确使用资格文件可以逐项核对原始输入SHA：

```sh
python3 -B -m linux.rk_debug inspect \
  --qualification src_fpga/stages/r8_stage3/pending/area95_20261016/validation_lz_r3/qualification.json \
  --repo-root . --session 1 --epoch 1 \
  --lz-library /actual/host-compatible/lz-library \
  --export-dir /actual/new-output/r3-products \
  --report-output /actual/new-output/r3-inspect.json
```

Windows必须使用已有Windows `lz_native.dll`，不能加载ARM64 `.so`；RK使用匹配的AArch64库。
缺库时明确失败或标明没有LZ decoder，不静默切到Python慢速codec。源/epoch在离线检查中是
调用者指定的验证条件，不是从记录bytes推导出的DMA安全授权。

已按原r3产物验证的参考值：RAW 2,592,000B，SHA256
`073287a8ff7f0b5607fdb64c0d320ebfdf03eaa7141ffb4a60ac6e5994a45014`；
JPEG payload 50,464B，SHA256
`98fae3c05d7681a620f4cf2deed161120092ce69dffb6f2ecd6d01f7527374a3`。
这些是数字刺激帧，不是摄像头实拍或持续帧率证据。

## 连接开发板后的顺序

1. 读取本次boot、kernel/DT、模块与FPGA镜像来源、实际BDF、能力和显示资源；旧设备名不作默认目标。
2. 在匹配SDK中构建/核验专用C2H模块和自有MPP shim。当前本机缺这些匹配输入，实际构建仍BLOCKED。
3. 先使用纯接收模式检查记录；按所选版本获得冷态SELECT ACK，再START。不要同时运行另一个接收器。
4. 再加可选解码、显示与录制，分别核对错误和drop计数；显示参数必须来自现场，不停桌面或强制modeset。
5. 使用一份受控配置，读requested/active/actual-frame三类结果。需要证明某模式有效时，等待同一
   source session/epoch的完整JPEG或RAW；累计总帧数不能证明切换后的新帧出现。
6. 结束先等当前配置事务有明确结果，再正常STOP并消费安全完成。失败/超时保留owner与进程，
   不在异常finally中关闭FD、卸载驱动或重置硬件。

真实命令的精确参数由`run --help`与`shell --help`列出。至少显式提供device、expected BDF、
record版本、CFG/drain/command预算、新report文件。纯收包不需MPP；开启解码必须另给MPP shim和
预算，HDMI还需pixel库、connector、plane及colorimetry。LZ模式必须有native库，HDR需
`--allow-lab-hdr`明确承认数字LAB来源。本文没有执行任何设备命令。

## 实际调用示例

以下设备命令供板连接、目标身份和匹配软件准备好后使用，本文没有执行它们。
在仓库根目录的Linux shell运行。先把所有`<...>`占位替换为现场值；这些占位不是可用默认值。
`OUT`必须是已经存在、没有符号链接的输出父目录。每次选择新的报告文件和录制目录，不能复用旧路径。

```sh
DEVICE='/dev/<EXPLICIT_C2H_DEVICE>'
BDF='<dddd:bb:ss.f>'
OUT='/absolute/<EXISTING_OUTPUT_DIRECTORY>'
CFG_S='<POSITIVE_CFG_TIMEOUT_SECONDS>'
DRAIN_S='<POSITIVE_DRAIN_TIMEOUT_SECONDS>'
COMMAND_S='<POSITIVE_WHOLE_COMMAND_TIMEOUT_SECONDS>'
RUN_S='<POSITIVE_RUN_SECONDS>'
```

`BDF`使用小写规范格式，例如格式为`dddd:bb:ss.f`，以本次设备清单为准。
CFG预算用于实际协议等待；command预算用于等待整条用户命令，包括LUT的多次事务。
run时长限制不是取消在途CFG的授权：命令结果未确认或排空失败时，程序保留owner和进程。
录制、解码和显示的预算也必须按实际系统配置，不能从示例推导已满足帧率或时延。

### 先查询，再纯收包

只读主机清单不打开`/dev`或BAR；输出包含本次boot、内核、PCIe和DRM等信息。

```sh
python3 -B -m linux.rk_debug preflight \
  --output "${OUT}/preflight-001.json"

python3 -B -m linux.rk_debug run \
  --device "${DEVICE}" --expected-bdf "${BDF}" --jpeg-version 3 \
  --config-timeout "${CFG_S}" --drain-timeout "${DRAIN_S}" \
  --command-timeout "${COMMAND_S}" --max-seconds "${RUN_S}" \
  --max-records 200000 --report-output "${OUT}/capture-001.json"
```

纯收包会严格解析完整JPEG记录并统计来源，不加载MPP或pixel库，不声称已经解码像素。
若计划切到LZ，启动时就要显式提供匹配主机架构的`--lz-library`。达到record预算会正常停止，
同批额外安全完成的丢弃计数可见；它不等于无限持续采集测试。

### 查询显示资源，再显式解码与HDMI

`display-info`只执行指定可信程序的`-M DRIVER -c -p`查询，返回原始stdout/stderr、status、
程序身份和输出预算。它不打开Receiver或MPP，不安装工具，也不modeset。
实际查询仅支持Linux；Windows不会回退为其他显示或网络接口。

```sh
MODETEST='/absolute/<TRUSTED_MODETEST_EXECUTABLE>'
DISPLAY_QUERY_S='<SECONDS_BETWEEN_0.01_AND_30>'

python3 -B -m linux.rk_debug display-info \
  --modetest "${MODETEST}" --timeout "${DISPLAY_QUERY_S}" \
  --driver rockchip --max-output-bytes 65536
```

从查询结果和本次NV12来源核对connector、plane与colorimetry。查询成功不代表plane可被占用，
也不代表实际屏幕已经呈现。程序复用BSP DRM/KMS，不强制modeset或停止桌面。

```sh
MPP_SHIM='/absolute/<AARCH64_STREAM_MPP_SHIM.so>'
PIXELS='/absolute/<AARCH64_NATIVE_PIXEL_LIBRARY.so>'
MPP_MS='<INTEGER_MILLISECONDS_1_TO_7999>'
CONNECTOR='<VERIFIED_CONNECTOR_ID>'
PLANE='<VERIFIED_PLANE_ID>'
COLORIMETRY='<VERIFIED_GSTREAMER_COLORIMETRY>'

python3 -B -m linux.rk_debug run \
  --device "${DEVICE}" --expected-bdf "${BDF}" --jpeg-version 3 \
  --config-timeout "${CFG_S}" --drain-timeout "${DRAIN_S}" \
  --command-timeout "${COMMAND_S}" --max-seconds "${RUN_S}" \
  --decode --mpp-library "${MPP_SHIM}" --mpp-timeout-ms "${MPP_MS}" \
  --pixel-library "${PIXELS}" --connector-id "${CONNECTOR}" --plane-id "${PLANE}" \
  --gst-colorimetry "${COLORIMETRY}" --consumer-queue-depth 2 \
  --consumer-close-timeout 1 --report-output "${OUT}/hdmi-001.json"
```

`MPP_SHIM`指本仓库接口对应的shim，不是随便选一个BSP MPP动态库。
colorimetry是GStreamer接受且与实际数据匹配的值，程序不猜满范围或有限范围。
队列深度2、sink关闭预算1秒是上述调用的明确选择，可在允许范围内调整；它们不是板级资格。
如果只需解码，不提供pixel、connector、plane和colorimetry四项即可。

### 同一owner交互调参

```sh
python3 -B -m linux.rk_debug shell \
  --device "${DEVICE}" --expected-bdf "${BDF}" --jpeg-version 3 \
  --config-timeout "${CFG_S}" --drain-timeout "${DRAIN_S}" \
  --command-timeout "${COMMAND_S}" \
  --config linux/rk_debug/examples/mono_sdr.json \
  --report-output "${OUT}/shell-001.json"
```

在`rk-debug>`提示符逐条输入。`configure`接受一行JSON，或`@文件路径`；它没有eval功能。
初始`--config`也在接收worker启动后提交，等待真实APPLIED期间仍持续接收。

```text
caps
active
configure @linux/rk_debug/examples/mono_processing.json
configure {"base":{"quality":82}}
status
pause
status
resume
quit
```

`caps`对应实际能力与catalog，`active`通过控制worker读取活动配置；`status`显示会话快照、
requested/last_applied、完整产品计数和consumer状态。相同schema允许局部patch；切换schema时
要给完整extension，程序将整组32word提交，不把字段变成独立寄存器滑块。
`load-lut N`与`query-lut`也是shell命令，其中QUERY是有序协议操作，不是纯内存状态查询。

普通参数或能力拒绝会打印错误并保留正常会话，可继续输入命令。CFG/LUT结果未知则进入故障留置，
不再通过重试猜测完成。`quit`、正常stdin EOF或Ctrl-C请求正常停止；等待输入时主线程仍轮询故障与停止事件，
不要求再按Enter。故障留置后EOF、Ctrl-C或SIGTERM都不是安全释放证明，程序不会据此自动退出。

### 运行场景与有界断言

脚本格式为`{"version":1,"steps":[...]}`，最多128项，连同初始`--config`一起计入上限。
脚本先完整读取并检查字段，再准备消费者和打开Receiver。命令被拒绝后，不继续执行依赖它的剩余步骤；
可以正常排空并写FAIL报告。观察目标超时也可正常排空，区别于在途事务超时留置。

```sh
python3 -B -m linux.rk_debug run \
  --device "${DEVICE}" --expected-bdf "${BDF}" --jpeg-version 3 \
  --config-timeout "${CFG_S}" --drain-timeout "${DRAIN_S}" \
  --command-timeout "${COMMAND_S}" --max-seconds "${RUN_S}" \
  --script linux/rk_debug/examples/scenario_processing.json \
  --report-output "${OUT}/processing-001.json"
```

脚本可用操作：

| 操作 | 参数与含义 |
|---|---|
| `configure` | `configuration`对象，格式与shell的JSON一致 |
| `active`、`discover`、`query-lut` | 无额外参数；交给唯一控制worker |
| `load-lut` | 明确的非零uint32 `generation` |
| `pause`、`resume`、`source-reset`、`status` | 无额外参数；reset另有下述准入条件 |
| `wait` | 明确`seconds`，范围0..60；不代表硬件完成 |
| `expect` | `path`与`equals`或`at_least`之一，立即检查状态快照 |
| `wait-for` | 同上，另给正数`timeout_s`，持续检查快照，不重试硬件命令 |
| `wait-product` | `kind`为`JPEG`或`RAW`，`epoch`固定写`active`，另给`timeout_s`；可给`at_least`1..64 |

例如下面几步检查切换后的实际产品以及错误计数，不能用单纯sleep代替：

```json
{
  "version": 1,
  "steps": [
    {"op": "configure", "configuration": {"base": {"quality": 80}}},
    {"op": "wait-product", "kind": "JPEG", "epoch": "active", "timeout_s": 10},
    {"op": "expect", "path": "active.base.quality", "equals": 80},
    {"op": "expect", "path": "products.counters.rejected", "equals": 0}
  ]
}
```

`active.base`是活动配置`configuration`的便捷路径。`wait-product`锁定该步开始时的真实
`active.session/mode_epoch`，只统计`observed_products`中相同来源的完整产品，不重贴旧帧epoch。
常用计数器包括`jpeg_frames`、`raw_frames`、`rejected`、`lz_crc_failures`、`lz_negative_terminals`、
`analysis_negative_terminals`和`analysis_frame_errors`，路径前缀均为`products.counters.`。
累计计数断言用于错误/数量检查，不能独自证明某次切换已有新产品。

断言只证明检查时的指定目标；PASS不自动覆盖全部算法、后续帧、物理显示或曝光质量。
示例的10秒是可修改的显式观察预算，不是协议常量。run总预算还要覆盖配置、LUT和全部观察步骤；
时限或停止信号使脚本未执行完时，报告为FAIL，`script_steps`列出计划/完成数量。

### LZ、录制与有限RAW预览

```sh
LZ='/absolute/<AARCH64_NATIVE_LZ_LIBRARY.so>'

python3 -B -m linux.rk_debug run \
  --device "${DEVICE}" --expected-bdf "${BDF}" --jpeg-version 3 \
  --config-timeout "${CFG_S}" --drain-timeout "${DRAIN_S}" \
  --command-timeout "${COMMAND_S}" --max-seconds "${RUN_S}" \
  --lz-library "${LZ}" --script linux/rk_debug/examples/scenario_lz.json \
  --jpeg-record-dir "${OUT}/jpeg-record-001" --raw-record-dir "${OUT}/raw-record-001" \
  --raw-preview-dir "${OUT}/raw-preview-001" --raw-preview-max-frames 1 \
  --raw-preview-max-bytes 4194304 --report-output "${OUT}/lz-001.json"
```

这三个目录必须全新、互不相同且互不嵌套。录制只接收完整产品并保留SOURCE；磁盘/队列预算和丢帧
见consumer/recorder报告。RAW预览最多16帧、64MiB，示例进一步限为1帧、4MiB；PGM只是RAW值右移2位，
不支持把它称作彩色ISP、实时RAW显示或质量提升证据。

### F21新generation与HDR LAB模板

可用模板见[examples](examples/)：

| 文件 | 使用边界 |
|---|---|
| [mono_sdr.json](examples/mono_sdr.json) | 完整schema2 SDR起点，处理开关关闭 |
| [mono_processing.json](examples/mono_processing.json) | 独立处理开关示例；仍受现场能力mask约束 |
| [jpeg_budget.json](examples/jpeg_budget.json) | 明确JPEG质量、adaptive、byte budget和restart示例 |
| [scenario_processing.json](examples/scenario_processing.json) | 依次检查灰度、HE、彩色filter、multiscale、lane的新epoch完整JPEG |
| [scenario_dehaze_generation1.json](examples/scenario_dehaze_generation1.json) | 先关闭F21并APPLIED，再加载generation1、启用并检查新epoch |
| [scenario_lz.json](examples/scenario_lz.json) | SDR→SDR_LZ完整RAW与CRC检查→返回SDR |
| [mono_hdr_lab_template.json](examples/mono_hdr_lab_template.json)、[scenario_hdr_lab_template.json](examples/scenario_hdr_lab_template.json) | 完整HDR语法模板，需审查LAB输入策略后使用 |

generation1不是“取下一个代次”的自动指令。先查询当前有效代次，选一个严格更大的非零uint32，
在自己审查的新脚本中同时修改`load-lut.generation`和配置的`dehaze_lut_generation`；不能只改一处。
LUT加载前必须由本控制owner确认F21关闭且APPLIED，加载完成也不会自动启用F21。未知失败不自动ABORT。

HDR模板的ratio2、qualification15、timers0只是完整合法语法，不证明适合当前LAB帧对。
使用前核实ratio、black/motion、时间窗口和输入配对条件，并写入自己的完整配置/脚本；mask15是策略要求，
不是物理曝光已合格的声明。实际调用还必须明确加入`--allow-lab-hdr`，例如：

```sh
HDR_SCRIPT='/absolute/<REVIEWED_HDR_LAB_SCRIPT.json>'

python3 -B -m linux.rk_debug run \
  --device "${DEVICE}" --expected-bdf "${BDF}" --jpeg-version 3 \
  --config-timeout "${CFG_S}" --drain-timeout "${DRAIN_S}" \
  --command-timeout "${COMMAND_S}" --max-seconds "${RUN_S}" \
  --allow-lab-hdr --script "${HDR_SCRIPT}" --report-output "${OUT}/hdr-lab-001.json"
```

### 显式source-reset：先pause，成功后仍由用户resume

生产C2H驱动没有此debug扩展；独立[debug驱动候选](driver/)默认禁用source-reset。
候选代码和用户态接口不等于可用已部署模块：当前缺匹配RK内核构建输入，实际内核构建仍为BLOCKED，
板级复位为NOT_RUN。受限接口不开放任意CONTROL写，不绕过`/dev/mem`，不解绑、重载模块或重启机器。

只有部署了匹配、显式启用且合同已核对的候选驱动后，才使用下面的会话开关。开关本身不会复位。

```sh
python3 -B -m linux.rk_debug shell \
  --device "${DEVICE}" --expected-bdf "${BDF}" --jpeg-version 3 \
  --config-timeout "${CFG_S}" --drain-timeout "${DRAIN_S}" \
  --command-timeout "${COMMAND_S}" --allow-source-reset \
  --config linux/rk_debug/examples/mono_sdr.json \
  --report-output "${OUT}/source-reset-001.json"
```

按以下顺序逐行检查，不把整段无条件管道输入shell：

1. 输入`active`与`status`，确认SDR，并在`observed_products`看到当前SOURCE session/epoch的完整JPEG。
   若此前是HDR/LZ，先通过完整CFG切回SDR并观察新产品；不能把STOP当作模式切换授权。
2. 输入`pause`，等正常返回STOPPED，再输入`status`核对。没有正常停止证明时不调用reset。
3. 输入`source-reset`。成功会确认新BOOT/source session并重新建立该来源所需记录选择，状态仍为STOPPED，
   不自动START，也不继承旧SOURCE身份。
4. 输入`status`检查成功回执和新来源，再显式输入`resume`。确认新来源完整JPEG后，最后用`quit`正常结束。

旧生产驱动不支持、候选开关关闭或前置条件不满足时，返回`Unsupported`/`ResetRejected`等已知未写拒绝，
shell保留会话；核对状态后仍可显式`resume`。请求可能已经写入而完成未知时，会FAULT并留置owner，
不能继续resume或把重发当作恢复。
脚本也可用`{"op":"source-reset"}`，必须在确认SDR产品、`pause`与STOPPED断言之后，成功后单独安排`resume`。

## 模式切换为何与旧runtime不同

本调试套件核对了r3实际RAW/LZ配置门槛。PREPARE暂停新工作，DFI选择要等待捕获token fence、
writer/owner/ticket/LZ/CDC/AXI quiet，完成whole ACK并到真实接受帧边界才APPLIED。
因此转换期间继续接收、释放安全完成，不能先停host grants来等待“全空”。

每个命令先构造完整base/32word extension，验证当前快照、实际能力、固定preset与LUT代次。
在PREPARE成功后、COMMIT写前，用同一fd的回调授权一个候选decoder epoch；确认真实APPLIED后
才标记确认。最多保留两个epoch，旧epoch未完成的LZ尾段不会因为APPLIED而被清空。
只有新边界已观察、旧assembly为空且主机完成队列已消费后才退休旧decoder；已退休epoch不复用。

配置线程不持有阻塞接收的锁。数据预算达到时仍归还同批额外安全完成，正常STOP并明确报告discard，
不把预算结束当成DMA故障。pause/resume保持同probe nonce和记录版本，不重复SELECT。

源码审计与软件mock不能代替实板跨模式验证；`SOURCE`时间与主机时间没有校准时，不计算虚假的
传感器到显示延迟。新主机到达时间也不会把旧尾段变成新曝光。

## 结果判读

- `APPLIED`表示真实CFG回执及完整active读回匹配；MMIO写成功和请求已排队都不是APPLIED。
- `JPEG COMPLETE`表示严格记录/marker结构通过，像素正确性另由显式MPP解码和图像检查证明。
- `LZC1 PARTIAL`不是完整RAW；`COMPLETE`需全部块/CRC/尾终态正确。失败terminal、缺段、错epoch分别计数。
- `observed_products`按实际SOURCE session/epoch统计JPEG/RAW与最后quality/processing_mode。
- 故障/退出报告中`ownership_retained=true`时必须保留调试进程；没有自动重启、softreset、重绑定或释放隔离内存。
  RUNNING状态中的true表示本会话正在持有设备，仍可通过`quit`等路径申请正常排空退出。
- 无断言的采集只标`COMPLETED_WITHOUT_ASSERTIONS`；脚本检查失败不能因正常close而变成PASS。
- 摄像头曝光、Linux AF_UNIX权限、MPP/HDMI物理输出、TF介质性能、持续SDR60/LZ30/HDR30及板级
  恢复仍按实际目标分别标NOT_RUN，不能从离线结果抬高资格。

本轮具体命令、93个用例的分轮关系、源身份、r3/C2样本检查与构建/板级限制见
[VALIDATION.json](VALIDATION.json)。原始最终日志在[evidence](evidence/README.md)。
