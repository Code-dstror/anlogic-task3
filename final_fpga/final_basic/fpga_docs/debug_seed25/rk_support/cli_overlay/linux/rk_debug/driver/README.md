# 独立C2H debug驱动派生候选

仅用于已审核的r3 ordered source/application reset合同。它不替换旧驱动源码，不改FPGA或线上协议，
不是通用DMA/PCIe恢复器。**匹配RK内核模块构建BLOCKED；模块装载/绑定、实际reset与板级NOT_RUN。**

基线为[`ph1a_c2h.c`](../../dma_c2h_candidate/ph1a_c2h.c)，SHA256
`210a4b5397f01522e72c224257c58e34b9e196194020990fbd1f9db0103c009b`。
[`derive.py`](derive.py)验证固定基线及五份共享头依赖，生成
[`ph1a_c2h_debug.c`](ph1a_c2h_debug.c)、[精确补丁](ph1a_c2h_debug.patch)、host Python常量与
[`DERIVATION.json`](DERIVATION.json)。共享协议宏直接包含现有生成的`docs/pcie_protocol_v1.h`，
没有重新手写FPGA寄存器或改变原USER ABI2、GET_INFO/GET_OWNER、SAFE/fence/nonce/generation。

## 默认禁用与独占目标

模块名/driver名为`ph1a_c2h_debug`，misc节点名前缀为`ph1a_c2h_debug_`，仍强制显式精确
`target_bdf`，仍不自动匹配设备，仍抑制bind属性。旧模块和debug模块不能同时拥有同一端点。
本轮没有执行加载、卸载、new_id、bind或设备操作。

新增`allow_source_reset` bool模块参数，权限0444，**默认false**。未显式开启时GET_DEBUG_CAP的
source-reset能力位为0，reset请求拒绝为UNSUPPORTED。启用它是操作者对所选bit/r3 reset合同的
明确声明，不是固件认证：通用magic/caps不能识别是否存在ordered reset fence，source SHA也不是
板上固件ID。普通收包/配置调试无需开启它；CLI还需自身的显式准入选项。

## Host-only加法UAPI

原`'H'`类型使用0x40..0x45，本候选检查后新增以下编号；结构均为固定u32序列，无指针。

| ioctl | 编码/长度 | 字段 |
|---|---|---|
| GET_DEBUG_CAP | `_IOR('H',0x46,...)`，0x80204846，32B/`=8I` | version=1、user_abi=2、capabilities、reset_state、issued_source_session、observed_source_session、reset_requests、reserved=0 |
| SOURCE_RESET | `_IOW('H',0x47,...)`，0x40104847，16B/`=4I` | version=1、expected_cfg_session、reserved0=0、reserved1=0 |

capability bit0表示操作者已启用受限source reset。state为0 NONE、1 ISSUED/当前新BOOT尚未确认、
2 NEW_BOOT_OBSERVED、3 UNCERTAIN。GET_DEBUG_CAP不会写FPGA；pending或已完成状态下，只有本次
重新双采样通过才返回state2，不把上次缓存的NEW_BOOT当成当前idle证明。正常运行后的cap查询不会
把内部已经完成的状态重新锁成pending。capability是支持声明，不是当前reset准入证明。

## 一次脉冲的准入与完成

在同一已打开独占fd、同一设备mutex中，全部条件满足才允许唯一一次
`CONTROL=PCIE_CONTROL_SOFT_RESET`写入：

- 无dead/quarantine；`!running && stopped && active == -1 && ready == 0`；submitted==completed。
- 实际遍历全部slot，**每个state都必须FREE**；不能只凭GET_INFO计数猜测无LEASE/READY。
- 两次CSR采样均可达且expected CFG session匹配；CFG_ACTIVE_SESSION等于SESSION。
- 实际APP_ENABLE=0，link和user reset可用，SOURCE_BUSY/TX_BUSY/C2H_RUNNING/FRAME_ERROR均清。
- 两次READY_MASK/SENDING_MASK均为0；非零是已知BUSY拒绝，全1是不可达fault。
  r3的READY_MASK来自store_ready_valid；SOURCE_BUSY只覆盖采集活动，不能排除已READY JPEG。
- native link/BME/STOPPED存在且无OWNED/SAFE_RESULT/RECORD_BOUND/quarantine；command error为0。
- CFG已SESSION_READY，无BUSY/PREPARED/ERROR且CFG_ERROR为0；ALGO无BUSY/LOADING/ERROR，RECORD无BUSY/ERROR。
- 同一source session尚未发出请求，没有未确定的前一次请求，request计数未耗尽。

在唯一写入之前先记下issued session和request计数；写后只读CONTROL与magic确认可达。
返回0只表示**请求已发出**，不是reset完成。同session重复请求拒绝；未知读回使软件进入quarantine并
保留资源，本扩展不写BME、native控制、PCIe reset或模块状态，也不重试。既有普通C2H故障路径未改写。

真正的全FPGA quiet由r3既有ordered reset fence负责。上述主机/CSR门槛不能证明内部所有待发JPEG/LZ
为空，因而请求可能一直pending；超时必须留置，不能为了“完成reset”自动恢复grant或强清owner。
pending期间驱动阻止START和legacy写，允许只读观察；没有开放任意CONTROL写白名单。

观察完成要求新非零CFG session与issued旧session不同、完整CFG BOOT/active session一致、rearm、
APP0、native STOPPED及相同host空闲条件重新双采样通过。不能把失链、BME丢失、未知旧DMA或quarantine
用这个接口恢复；这些条件本身会拒绝请求。

## 同fd Python接口

[`driver_api.py`](../driver_api.py)的`DebugDriverAPI(receiver)`只借用已有Receiver的同一个IO对象，
不打开或关闭fd：

- `capabilities()`返回不可变`DebugCapabilities`；旧模块ENOTTY/EOPNOTSUPP或未启用能力在请求前
  可识别为`Unsupported`，不记为已请求。
- `request_source_reset(expected_cfg_session)`先检查版本/能力/host drain，随后发出一次ioctl并核对
  request计数与issued session。首次回读可能已经是state2，允许这种fast-completion；仍须调用wait。
- `wait_new_boot(expected_old_session, timeout_s)`必须属于本实例已确认的那次请求，绑定旧session、
  request计数及GET_OWNER完整身份。只读等待state2，并确认同probe/nonce/generation及host drain。
  新实例不能冒领历史NEW_BOOT。返回的新source session不改变native transport nonce。
- `ResetRejected`是已知准入拒绝；请求后的未知错误为`ResetUncertain`，不能包装成Unsupported或重试。
  deadline到期为UNKNOWN_PENDING，不关闭或释放owner。该deadline约束返回的同步ioctl之间的轮询；
  不能宣称它能取消卡在内核中的MMIO，目标内核行为仍需验证。

上层还必须保证无CFG排队、无正在解码/尚未完成的产品assembly，并在新BOOT后重建来源相关配置/记录
选择状态。该重建由session层完成，必须保持STOPPED，后续由用户明确resume；本adapter不会自动SELECT或START。

## 构建与本轮验证

复现派生身份检查：

```sh
python3 -B linux/rk_debug/driver/derive.py --check
```

匹配内核输入就绪后才使用本目录Makefile，显式提供真实KDIR；按目标选择ARCH/CROSS_COMPILE。
本机没有匹配KDIR，因此没有编译`.ko`，不把MinGW或Zig的host/UAPI产物当成模块。

本轮9项Python/真实共享C guard定向测试PASS。实际helper覆盖默认禁用、host/全部slot门槛、双采样、
已知busy/error拒绝、各读取损坏、只发一次合法pulse、read-only新BOOT、重复请求与fast completion；
adapter使用真实Receiver+FakeIO，未触及设备。精确入口：

```powershell
$env:CC='D:/App/Xilinx/2025.1/Vivado/tps/mingw/10.0.0/win64.o/nt/bin/gcc.exe'
& 'python' -B -m unittest discover -s linux/rk_debug/driver/tests -p test_debug_driver.py -v
```

最终READY_MASK/SENDING_MASK门槛补丁后，仅重跑
`python -B -m unittest linux.rk_debug.driver.tests.test_debug_driver.SharedHelperTests -v`：
1项PASS（0.593s），包含两种mask分别非零的已知BUSY拒绝及各采样位置损坏检查；
`derive.py --check` PASS。先前9项回执不冒充该补丁后的全量重跑；结果保存在本次工具回执。

另外以已安装Zig对`tests/uapi_layout.c`执行`-target aarch64-linux-gnu.2.17 -std=c11 -Wall -Wextra
-Werror -c`静态断言编译，检查原UAPI尺寸不变及新32B/16B/编号/方向。产物
`tmp/rk_debug_driver_20261016/uapi_layout.o`经readelf确认ELF64/LE/AArch64/REL；仅用户布局检查。
这不证明内核编译、并发、真实MMIO顺序、FPGA reset完成或板级恢复。本轮未修改旧qualification。
