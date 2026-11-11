# 06a122ee70 / seed1 收发兼容短测

v4 接收端使用发布包中未经修改的 `linux.stream_diag.records.parse_record(..., expected_version=4)`、CTX2/v4 解析器及字段定义。另执行 seed1 板调包 phase-B 的 `dual_r3_stereo.validate_color_record`，区分字节解析和旧试验只接收双目纯彩色的策略。

返程以现有 `tb_sparse_transport` 为基础，相同的带身份产品事件分别送入 `06a122ee70:refactor/dual_hdr_merge_r1` 和当前生产源的 CTX2 构造器 → 官方 ERAM 暂存 → 六个 JPEG 槽发布/代次校验和回放 → C2H formatter。仅记录真实 AXIS 握手的有效字节。末拍 TLAST 后还要收到真实完成回执才保存文件；零长/超长拒绝、两次入选后取消的最大长度探针均没有被作为记录解析。每个版本通过 69,621 项原传输断言，含 4,207 次输出受阻和 768 个扩展头回放握手。

| 槽 | 输入产品事件 | 发布版 v4 解析 | 板调纯彩色策略 |
|---|---|---|---|
| 0、3 | 左/右物理 RAW10 单曝光、`processing_mode=0x80` | 通过 | 接受 |
| 1 | 原单目 F22/C1，`0xB0`，303 个白/黄候选 | 逐个核对点序、坐标、强度、宽度和类别 | 拒绝 |
| 2 | 单目 HDR，`0x80`，LONG、qualified、pair/job、HDR_MERGED | 通过 | 拒绝 |
| 4 | 右眼 SDR `0x8F`，请求去雾，历史尚未实际使用 | 通过，产品位为零 | 拒绝 |
| 5 | 右眼 HDR `0x8F`，本帧实际使用去雾 | 通过，HDR_MERGED 和 DEHAZE_FILTERED 同时置位 | 拒绝 |

每一条完整记录均为 29,069 字节，含 2,112 字节 v4 头和可单独解码的 26,957 字节 1920×1080 JPEG，末拍有效 13 字节。六条记录在两代 RTL 的输出逐字节一致，也逐字节等于通过冻结结构独立组装的期望值。比较涵盖完整头、扩展、空白填充和载荷，另逐字段检查 SOURCE、生成号、slot、模式掩码、HDR 身份、处理位和实际点包。[源与结果指纹](evidence.json)

本试验以主机生成的 JPEG 和注入的完成事件隔离记录格式验证。F22/F23 稀疏体是定向向量。真实图像算法、传感器和发起最终 PCIe DMA 的硬件未纳入该试验。旧格式化器能携带相同的位，与旧系统能否启用新算法是两个验收条件。

主机到 FPGA 的已有 `control/run_stereo_eligibility.py` 在本次工作树重新运行。真实 BAR、CFG 服务、配置 FIFO 与 PIX 引擎完成 15,068 项检查、18 次回调，包括关闭、灰度/高斯/HE、去雾、单目车道、HDR、拒绝双目 F22/C1 和非法去雾代号。夹具提供远端回调和帧接纳。完整 TOP 的其它短门见项目 `docs/STEREO_FILTERS.md` 和 `stereo_hdr_dehaze_short/README.md`。

从工程目录复现。若冻结包位于其他位置，可设 `RK_SEED1_RUNTIME` 与 `RK_SEED1_POLICY_RUNTIME`；脚本校验原 parser 与原策略的 SHA256。

```powershell
python -B src_fpga/simulation/rk_wire_compat/run.py --name compat_review --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
python -B src_fpga/simulation/control/run_stereo_eligibility.py --name cfg_review --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```
