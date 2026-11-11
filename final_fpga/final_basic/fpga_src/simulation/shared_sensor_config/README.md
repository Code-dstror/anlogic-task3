# IMX415 共享配置引脚仿真

在仓库根目录使用 `ENVIRONMENT.local.md` 中的 Python 和 ModelSim 运行，每次给 `--name` 一个新名称。

```powershell
python refactor/camera_raw_r1/src_fpga/simulation/shared_sensor_config/run.py --modelsim-bin $env:MODELSIM_BIN --name shared_config_check
```

测试台根据 SDA 和 SCL 解码 START、4 个字节、每个 ACK 和 STOP。两眼分别连接可注入 NACK 的开漏从端。SDR60 逐笔比较固定提交 `01cc78af` 的模式表、复位增益和启动命令。SDR30 在同一顺序上检查 HMAX 533→1066 及 SHR0 1129，并比对其余字节。HDR 逐笔比较同一提交的 139 笔固定配置。

短等待用例覆盖 START 后输入变化、三处 NACK、I²C 写入中止、唤醒阶段复位、双总线写入时单眼失锁，以及 HDR 连续八组配对和坏组重新资格。另一眼采用生产默认分频和复位／释放／唤醒等待，在 25 MHz 下测量 STANDBY 的 STOP 至 XMSTA 的 START。

每次运行在 `refactor/camera_raw_r1/tmp/shared_sensor_config/<name>` 保存编译用源快照、SHA-256、命令、日志和 `qualification.json`。历史 oracle 明确读取父工程固定提交，生产 DUT 则使用本隔离工程。综合、布局布线、STA 和板级状态均为 `NOT_RUN`。
