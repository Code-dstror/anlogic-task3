# 双目 HDR RAW owner 独立容量短测

测试依据公开端口、合法 16×4 profile 和不透明编译闭包编写。`owner_service_carrier.v`
由实现维护者交付，测试作者只编译和校验其哈希。真实路径包含 RAW 捕获、AXI 写端、
SOURCE、目录、job 派发、调度和 RELEASE。DDR 写响应、HDR reader、PIX/JPEG 处理终态和
票据归还由公开接口 BFM 提供。 [公开合同](../../../docs/hdr_rate_seed56_20261110/OWNER_CAPACITY_PUBLIC.md)

## 运行

在仓库根使用 PowerShell 7。每次选用新的 `RunId`。省略 `-Cases` 会运行全部场景，
指定子集仍先运行四成员 `first`。每场景有 60 秒墙钟预算和 2.5 ms 仿真 watchdog。

```powershell
& 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_capacity_20261110/run.ps1' `
  -RunId full-r03 `
  -TdRoot 'D:/App/TD_Release_2026.2.210.850' `
  -ModelSimBin 'D:/App/modelsim/win64'
```

runner 将精确 argv、工具版本、固定生产 blob 核对、前后输入 SHA256、场景日志和结果
保存在 `tmp/hdr_rate_seed56_20261110/capacity_blackbox/<RunId>/`。编译使用清单中指定的
生产文件和 TD 模型，两个全局实例与测试顶层同时展开。

## 场景

- `first` 发两眼各一个 LONG/SHORT 组。独立的字节图样包含眼、角色、组和 RAW 组序，
  核对真实 AW/W/B 账本及每槽的 80 B。施加有限 W 反压及 B 延迟。两眼需分别经过
  SOURCE、acquire、job、member、context、START、RESULT、处理完成、票据归还、
  RELEASE 和 retire acknowledgment，最后进入 quiescent。
- `late-peer` 先完成同眼 A、B 的捕获，C 的 LONG 在两 bank 都占用时获负 BEGIN。
  A 真实 RELEASE 后才发送 C 的 SHORT，要求仍获负 BEGIN。D 合法接收并真实退休。
  C 两个成员都给出匹配 SOURCE，逐帧确认无 C job、无残留写入。
- `slow*` / `fast*` 保持两眼各 3,300 DFI 拍周期、SHORT 晚 100 拍和约
  2,900/3,000 拍的 LONG/SHORT 捕获终点。CAM1 相对 CAM0 分别错开 100、400、
  3,200 拍。每眼热身 30 组并按输入身份计量后续 60 组，另记共同时间窗及尾部排空。
  A/B 只改变 acquire 后约 1,950/1,590 拍的服务终态安排，并比较 SOF 与 SOURCE
  offer 的同相位输入轨迹。快条件要求两眼分别全收全退、零负 BEGIN。慢条件要求至少
  一个容量缺口，每个缺组都有对应负 BEGIN，每个已接 job 都真实退休。

统计单位是每眼一组 LONG/SHORT。两个速率仅代表 BFM 提供的服务时限下的实际控制
容量。真实 HDR reader、PIX/JPEG、DDR 与板级满幅吞吐需各自验证。STOP、取消和模式
切换在载体内固定为空闲。 [实测记录](VALIDATION.md)
