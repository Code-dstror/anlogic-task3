# 打开、依赖与静态检查

原生入口为 `fpga_prj/al/rfcamera_fusion_r1.al`。全部 253 个注册项和 5 个 include 目录
均位于本目录；生产清单有 408 个输入，另保留原工程已有的空 SDC 占位文件等配套文件。
IP 元数据引用的生成 Tcl、RTL 和 ROM 初始化文件已随包携带，不需要回到父工程查找。

TD 使用 2026.2 / 6.2.3.210850，器件 PH1A90SEG324-2。需要本机合法安装的 TD 及器件库；
历史功能仿真使用 ModelSim SE-64 2020.4 和同一 TD 根下的模型。脚本使用 CPython 3.12，
可选工具依赖参考 [requirements-windows.txt](requirements-windows.txt)。本机实际路径由使用者指定。

从 `final_high_fps` 目录执行以下静态检查，仅使用 Python 标准库：

```powershell
python -B fpga_prj/tools/verify_delivery.py
python -B fpga_prj/tools/generate_geometry_control.py --check
python -B fpga_prj/tools/generate_rate_control.py --check
python -B fpga_prj/tools/generate_raw_video_protocol.py --check
python -B fpga_prj/tools/generate_quality_control.py --check
```

归档检查同时核对原始封印、路径迁移、非注释内容等价、交付文件字节、原生源顺序/宏/器件/运行参数和 bit 身份。
`SOURCE_SEAL.json` 保留原路径作为身份锚点，新目录使用 `fpga_prj/SOURCE_MANIFEST.json`。
质量 JSON 的 `extends` 已指向包内同字节基础协议文件；四个生成器只调整路径。

如后续需要整体 read_design，显式指定本机新版 TD 根：

```powershell
python -B fpga_prj/tools/run_td.py fpga_prj/scripts/check_read_design.tcl --td-root '<本机TD根>' --workdir fpga_prj/al --log fpga_prj/tmp/read_design.log
python -B fpga_prj/tools/run_td.py fpga_prj/scripts/check_shared_hdr_owner.tcl --td-root '<同一TD根>' --workdir fpga_prj/al --log fpga_prj/tmp/hierarchy.log
```

此步骤在本次纯路径整理中为 NOT_RUN。本地仅短仿真、read_design、有界小模块综合；
整机长综合和 P&R 仍使用仓库原来的服务器入口，未为此归档新建编译任务或修改登记。
TD 会在 `fpga_prj/al/rfcamera_fusion_r1_Runs/` 生成独立结果，勿用历史完成标记替代新检查。
TD 保存后可能将 Project Path 写成绝对路径，交付前应恢复为 `.` 再检查。

本 `.al` 保留源工程默认 SYN16/PHY4，服务器随附 bit 实际使用 SYN4、PHY4、seed54。
服务器原生设置、AL 文本和 stage 日志见 [seed54 原件索引](server_seed54_20261111/FILE_INDEX.json)。
同一源码与同一参数也不构成跨平台 bit 逐字节可重复性的承诺。

RK SDK 是原 peer SDK 的增量层，沿用 Receiver、ioctl、DMA owner 和运行内核；
本包附上本工程全部 RK 增量源文件及 RAW 驱动源文件，不包含另一台设备的内核、KO 或旧资格包。
参见 [RK 使用说明](../fpga_src/rk_sdk/README.md)，4K 需使用本工程新版 SDK。

`verification_archive` 保存原测试和优化源码；其中 A/B 候选不属于生产源。
重跑历史门需在原仓库布局按其记录固定输入/peer 依赖，不把移动后的测试脚本宣称为已独立可运行。
历史 SHA 标识原始输入；当前文件 SHA 见 `DELIVERY_FILES.json`，路径映射与非注释内容校验值见 `provenance/RELOCATION.json`。
