# RK 参数目录

`caps` 与 `SharedControls.discover()` 从当前设备读取 base、schema2、active 和 parameters。
目录显示已接通的 JPEG 质量、预算、自适应、restart 和 HDR 运动阈值与时间边界。
黑电平固定 50，曝光比固定 4。检测到画质能力位时加入 WB，HDR 档还列出 Tone 和融合预设。
4K 只公布 SDR、灰度/高斯/HE 和可用的 WB。旧 COLOR-only 4K 保持空处理掩码。

需要区分两种能力：RECORD v4的LANE_POINTS格式位说明可解析保留字段，不表示当前双目/UHD支持车道算法；
实际处理目录由CFG enables决定。目录中的固定0以access/value为准，通用去雾或车道备注不扩大能力。
共享schema2入口的base.mode固定COLOR，也不删除单独的legacy scalar模式API。

离线加载顺序为本工程 `rk_sdk`、已发布 dual_sdr 快照的 peer、提供 `dual_r3` 的快照外层与仓库根。
字段与兼容规则见 [RK HDR 画质控制](RK_QUALITY_CONTROLS.md)。
