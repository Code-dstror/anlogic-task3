# IMX415 配置引脚短仿真

从仓库根目录运行。`--case` 可重复指定单例，省略时运行整套 25 例。

```powershell
& 'python' `
  'refactor/camera_raw_r1/src_fpga/simulation/blackbox_camera_20261107/run_camera_config.py' `
  --modelsim-bin 'D:/App/modelsim/win64'
```

测试依据公开端口合同。每眼独立连接一条带上拉的 SDA，总线从机只驱动低电平和高阻。夹具从 SCL/SDA 解码 START、四个字节、ACK/NACK 和 STOP，从 XCLR 及状态端口检查顺序。每例独立运行，设 60 秒墙钟上限和仿真 watchdog。

| 用例 | 验证内容 |
| --- | --- |
| `dual_same`、`dual_stagger` | 双眼同拍和错开 137 个配置时钟启动。验证每眼 203 笔和各自 SDR60/30、增益，忙时扰动模式/增益并脉冲 START。 |
| `dual_nack`、`dual_lock` | 左眼中段 NACK 或位中失锁，右眼继续写完并稳定，左眼重新完整配置。 |
| `sdr_roundtrip` | 无锁时 START，SDR60/30 两轮切换，核对 VMAX、HMAX、SHR0、增益和同模式逐笔一致性。成功后验证 abort 或失锁清除稳定状态。 |
| `nack_{001,102,203}_byte{0..3}` | SDR 首、中、末笔的地址、寄存器高字节、寄存器低字节及数据各注入一次 NACK。失败信号出现，配置保持无效，随后直接 START 并完整写完 SDR30。 |
| `wake_abort`、`wake_reset`、`bit_reset`、`bit_lock` | 唤醒等待中 abort/reset，I²C 数据位中 reset/失锁。验证总线回到空闲并可完整重配。 |
| `hdr_recipe` | 两种 SDR30 与增益请求下逐笔比较 139 笔 HDR 写入，核对等待间隔。测试 7 个好对、坏对打断、重新连续 8 个好对。 |
| `hdr_abort`、`hdr_fault` | 热身中 abort/source_fault，继续输入好对，再发起完整重配；已稳定 HDR 的 source_fault 也清除配置。 |
| `production_defaults` | DUT 使用默认参数，完整走一轮 SDR60，核对 XCLR、SCL、唤醒间隔和最后 ACK 后才报告配置成功。 |

2026-11-07 整套 **25/25 PASS**。ModelSim SE-64 2020.4 单例墙钟 2.484–4.343 秒，合计 79.594 秒。默认 SDR60 实测 XCLR 低 10 ms，SCL 高、低最短各 5 µs。`3000=00` 的 STOP 至 `3002=00` 的 START 为 25.005080 ms，末 ACK 下降沿在 122.141700 ms，首次采样 `o_config_written` 为 122.156760 ms。

结果位于 `refactor/camera_raw_r1/tmp/blackbox_camera_20261107/20261107T145405_178460Z/`。`results.json` 含命令、每例状态和墙钟耗时，以及六个生产输入与夹具、runner 的 SHA-256。`.csv` 为引脚解码记录，`.log` 为模拟器输出。首次编译源集缺少 `ui_imx415reg` 的日志保存在同级 `20261107T145243_816175Z/`，后续按原生工程清单加入该依赖。

验证范围为配置控制和串行总线。综合、布局布线、物理时序与板级均为 `NOT_RUN`。
