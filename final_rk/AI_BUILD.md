# V5 单目 AI 构建入口

目标环境为 RK3576 Debian 12／ARM64／Linux 6.1.99 BSP。实际运行以完整 V5 包 `reproduce.sh` 和原依赖为准。原生重建需要匹配该 BSP 的编译器、头文件和库，依赖表见精简源码包 `docs/依赖与构建说明.md`。

以下命令从解压后的精简源码包根目录运行，产物放到独立目录。选择 ARM64 BSP 上的原生编译器，或提供配有目标 sysroot 的 ARM64 交叉编译器。

```sh
out="$(mktemp -d)"
bash linux/native_build_sources/rga/build_v5_rga.sh "$out"
file "$out/liby26_prepared_rgb2.so"
```

`CXX` 可指定编译器，`RGA_INCLUDE_DIR` 和 `RGA_LIBRARY_DIR` 可指定目标 BSP 的头文件和链接库。脚本使用与 V5 构建记录对应的 `prepared_rga_required.cpp`，输出 `liby26_prepared_rgb2.so`。重建后先核对 ELF 架构和动态依赖，再做部署验证。原包的 SHA256 用于识别原有二进制。

精简包恢复的原入口位于 `linux/control/ai_helper/candidate/src/ai/`。

| 原入口 | 用途 |
|---|---|
| `depth_roi/build_linux.sh`、`depth_roi/native/CMakeLists.txt` | C++ 精确区域取距 |
| `y26_rk_app/build_exact_pack.sh`、`build_gmc.sh` | GMC 数据整理与光流，使用 OpenCV 的 `pkg-config` 配置 |
| `y26_rk_app/build_topk.sh`、`build_tracking.sh` | 候选筛选和跟踪批处理，编译选项以实际使用版本为准 |
| `y26_rk_app/native/CMakeLists.txt` | 旧 RKNN 桥和候选接口，输入头文件与库路径由 BSP 提供 |
| `y26_rk_app/build_prepared_shared.sh` | 旧候选 RGA 构建，使用候选源码 `prepared_rga.cpp` |
| `y26_rk_app/build_replay_shared.sh` | 固定视频回放的 MPP/GStreamer 候选入口 |
| `y26_rk_app/build_linux_display.sh` | 旧显示候选占位，脚本会退出并提示原构建边界 |

本补件按 V5 原包恢复构建文件，并新增对应 RGA 源文件的独立编译命令。全套原生库统一重建仍需 Linux 成员补齐准确的 BSP 和构建记录。本次验证范围为源码、路径及归档校验，ARM64 编译和上板结果待对应环境记录。
