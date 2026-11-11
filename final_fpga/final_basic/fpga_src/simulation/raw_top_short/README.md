# RAW 顶层短门

本夹具用当前 `anlogic2026`、`MAIN_FIXTURE.json` 和本工程源清单。复用已有 DDR AXI 存储模型、PCIe 端点边界和主机 BFM。RAW 用例在裁剪和解析事件输出注入 12×6 RAW4 栅格及可信 FS/FE，沿实际 SOURCE fence、RAW writer、DDR、RAW reader、ARAW formatter、跨域与 native C2H 传送。传感器配置仍由两套现有共享控制器推进，模型给从机 SDA ACK，缩短 I²C 分频和等待周期。

小栅格保留 RAW 存储所依赖的 `%6` 和四像素几何。RAW 夹具选用非 F21 的非紧凑顶层配置通道，使用 `defparam` 保留固定 HD 的 CFG 前端、CFG 服务、闲置 JPEG ingress 和 RGB adapter 参数。注入的裁剪栅格具有已知 Bayer 相位，夹具把 Bayer 资格与实际配置完成和无配置错误绑定。七条已知 ModelSim 警告来自非 F21 备用预处理器的六个开放观察端口及汇总，原样保存。另一个 JPEG 冷控制用例使用生产几何和 F21/紧凑配置宏，只有真实 v2/v4 SELECT 和 STEREO APPLY 控制，没有注入图像。

RAW 用例从真实 CFG BOOT 会话开始，经 BAR 发布 RAW 产品和拓扑，保留 BOOT v1 记录选择。单目检查 SDR60 与有效 divisor1，双目检查两眼实际应用 SDR30、公布 D2 与有效 divisor1。每眼一幅不同测试栅格。夹具用 ARAW 首拍断言替换主机 BFM 的 AJPG/LZ 专用头部检查，继续使用其真实 posted byte、fence 和 SAFE 检查。检查 64 字节 ARAW 头、90 字节 RAW10 LE5、实际 SOURCE 会话/epoch/序号/相机及所有 154 个主机字节。Native AXIS 最后一拍停五周期，主机 BFM 等实际读 fence 完成后读取 SAFE。SAFE 后再延迟十三个 USER 时钟发 ACK，等待原 RAW 槽按同一 identity 退休。

## 本轮结果

| 独立运行 | 状态 | 检查 | 耗时 |
|---|---|---|---:|
| `compile05` | PASS_ELABORATION_ONLY | 12×6 编译和展开 | 11.953 s |
| `raw04` 单目 | PASS | 72 项，CAM0 seq257，一条 154 字节记录，5 周期末拍停顿 | 单双目共 85.953 s |
| `raw04` 双目 | PASS | 123 项，CAM0 seq257、CAM1 seq521，各一条 154 字节记录，共 10 周期末拍停顿 | 同次运行 |
| `jpeg01` | PASS | 21 项，原 v2 192 字节头与 v4 2112 字节头冷选 | 14.157 s |

三次运行均绑定 404 项生产输入，TOP SHA-256 为 `ae520552eb1a865d338c4b8b26cccd46e8c4ec580b13325635a4c24434984f5c`。封存元数据更新后逐一核对当前 404 个清单成员及两个功能运行各自记录的 528 项 RTL/IP/头文件/TD 模型输入，内容哈希全部一致。`raw04` 每组 226 条 ModelSim 警告含七条小尺寸备用支路警告，`jpeg01` 有 318 条模型及展开警告。两个功能运行均无未列入夹具范围的自有警告。 [编译](../../../tmp/raw_top_short/compile05/RESULTS.json) · [RAW 命令及逐例日志哈希](../../../tmp/raw_top_short/raw04/RESULTS.json) · [JPEG 冷控制](../../../tmp/raw_top_short/jpeg01/RESULTS.json)

`raw04` 保存主机 fence 实际提交的三条记录。用 RK 的 `parse_raw_video` 和 `unpack_samples()` 独立读回，逐条核对 12×6、相机、会话 1、epoch 0、序号及 72 个 10-bit 样本，216 个样本全部匹配。 [原件哈希与解码结果](../../../tmp/raw_top_short/raw04/rk_decode.json)

早期短运行留存在独立目录。`raw01` 的 12×6 夹具缺少固定 HD 才取得的 Bayer 资格，启动后一直未发布 RAW；`raw02` 走到 native 首拍，由原主机模型的 AJPG 头检查拒绝；`raw03` 的记录文件名类型未通过 ModelSim 展开。`raw04` 使用该夹具已知的 Bayer 相位、ARAW 首拍断言和固定文件名。改动均位于此夹具内。

## 复现

```powershell
$python = 'python'
$runner = 'refactor/camera_raw_r1/src_fpga/simulation/raw_top_short/run.py'
& $python -B $runner --name tiny_compile --compile-only --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
& $python -B $runner --name tiny_raw --case raw --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
& $python -B $runner --name jpeg_cold --case jpeg --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

`--case raw` 在同一编译库下分别启动单目和双目。`--case mono` 和 `--case dual` 可单独重跑。编译展开上限 30 秒，每次功能调用上限 180 秒，仿真另有固定周期 watchdog。`tmp/raw_top_short/<name>/` 保存输入和模型哈希、命令、各自日志和 `RESULTS.json`。本门覆盖裁剪输出后的控制及数据链；实际 CSI/DDR/PCIe 电气、持续帧率、综合、P&R、物理时序和板级均另行验证。
