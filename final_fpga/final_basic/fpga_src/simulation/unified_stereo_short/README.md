# 有序两槽与真 FS cadence 短测

`run.py` 对固定旧候选 `dual_hdr_merge_r1` 和当前候选使用同一组输入、同一
TD 6.2.3.210850 官方 RAM/FIFO。结果逐件记录真实源码 SHA256；旧候选只读。

接口仍是 PIX 域四个 unsigned RAW10（lane0 为低10bit），实际 valid/accept
推进，裁剪 SOF/EOL/geometry 与真正 CSI FE 分别验证。SOURCE 为 held
valid/ready，直到两条 fence 结果尾部真实消费；无消费者超时释放。DFI
RAW owner 仍为每眼两个槽、共享目录及一个 job，128bit/WSTRB16 writer
按实际 B 成功结束。DDR 和共享处理边界明确建模，未模拟 JPEG/PCIe。

候选 `FS_CADENCE_ENABLE=1` 在每个可信 FS 决策与推进 cadence；忙 fence
不能使相位少走一次。动态 N 变化在下一 FS 开始新相位，N0 禁止新 owner，
已经接纳的 SOURCE 身份、像素与结果不受影响。调用者必须给后端 DIV1，
避免再次分频。默认 `FS_CADENCE_ENABLE=0` 保留旧调用行为。

`order_rate_r4` 九项自检 PASS：旧版两眼均有 10→12→11 倒序，候选
332 检查无倒序；包括目录写到 BEGIN ACK 的窗口、错误退休、末端持有、
STOP、负 FINISH、跨代复用、序号回卷和协调 reset。原 SOURCE 回归双方
均 1289 检查 PASS；额外 cadence 23 检查覆盖 N0/1/2/3、坏/不可信 FS、
缺 FE、裁剪 SOF 后先到 FE、跳过帧 FE、held 旧 SOURCE 和恢复。

速率 A/B 固定每眼24真 FS、400 PIX 周期、两眼错相37周期。FE 在 +397
时，旧源 fence 的实际尾部跨过下一 FS，旧裁剪12→后级N2选中6；候选
FS N2+后端DIV1为12，稳态SOURCE4..19各眼8，对照各眼4。FE提前到+380
时双方均12，证明该修复针对可复现的二次分频。输入不等 owner/DDR/job，
RAW组无主动空拍；实际两槽没有拒绝，所有 BEGIN/FINISH/job/retire 对账。
这证明有界数字路径机制，**不是** 满幅持续30、板上成功率或显示资格。

```powershell
python refactor/dual_unified_r1/src_fpga/simulation/unified_stereo_short/run.py --name order_rate_new --modelsim-bin D:/App/modelsim/win64 --td-root D:/App/TD_Release_2026.2.210.850
```

本机 ModelSim 需要原生 Windows；沙箱 DLL 重定位失败原件保留在
`tmp/unified_stereo_short/order_rate_r1`。r2 的旧bench未绑定新增可选输入，
自检通过但警告分类 FAIL；r3 的“FE在整个裁剪SOF之前”超出当前 source
前置 quiet 假定，未产生 SOURCE。r4 将合法先到 FE 定义为已出现裁剪
SOF/context 后、裁剪尾部之前。没有为这些试验改共享 fence 或伪造完成。

综合、P&R、时序、bitgen、板级均 NOT_RUN。
