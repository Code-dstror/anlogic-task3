# 安路 FPGA 赛道赛题 3

本仓库用于嵌入式芯片与系统设计竞赛安路 FPGA 赛道赛题 3 的开发与联调。

## 团队分工

- 我负责 RK3576/Linux 侧：主机工具、板端软件、推理与部署。
- 队友负责 FPGA 侧：图像采集、数据通路与 FPGA 工程。

## 当前链路方向

当前暂定以 PCIe 作为 FPGA 与 RK3576 间的主链路，MIPI 作为备选链路。

此选择处于 **proposed（候选）** 状态，尚需与 FPGA 队友共同确认；在接口、带宽、时序和实现边界明确前，不视为最终架构决定。

共享接口约定见 `interface/`，候选架构决策见 `docs/decisions/`。

## IMX415 camera 导航与验证边界

IMX415 camera 是独立于 PCIe 工程的采集验证工程。其输出为 RGB888 的
128-bit AXI-Stream（RGB AXI），不包含 JPEG 编码或 PCIe 传输；因此不改变
现有 Linux、PCIe、协议及测试边界。

- 独立 TD 工程：[fpga_prj/imx415_camera.al](fpga_prj/imx415_camera.al)
- 设计接口与实现范围：[doc/imx415_camera_design.md](doc/imx415_camera_design.md)
- 验证记录与限制：[doc/imx415_camera_validation.md](doc/imx415_camera_validation.md)
- 重建、使用和上板前检查：[doc/imx415_camera_bringup.md](doc/imx415_camera_bringup.md)

已提交的 camera TD Tcl 脚本为
`fpga_prj/scripts/sync_imx415_camera_project.tcl`、
`fpga_prj/scripts/diagnose_imx415_camera.tcl` 和
`fpga_prj/scripts/build_imx415_camera_project.tcl`；详细操作仅见 bring-up
文档。

验证边界：来源提交 `6b398c144e7a563ea3d9fa6085ac3142813be2a7` 记录的
ModelSim 行为回归通过。当前 Linux 环境未重跑 ModelSim 或 TD。历史 TD 物理流
曾完成 bitstream 生成，但 setup WNS 为 -2.923 ns、hold WNS 为 -1.659 ns，
时序尚未收敛；现有 bitstream 不能视为正式上板验收版本。IMX415、PHY、真实
图像采集和板卡验证仍未完成。
