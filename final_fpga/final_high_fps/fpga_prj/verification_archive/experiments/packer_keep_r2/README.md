# KEEP 解码局部对照（未采纳）

基线为eade457d生产jpeg_byte_packer，候选只将16项KEEP编码写成逐位计数阈值。
32个可能的5位计数编码做了精确枚举。未改生产RTL，也未启动功能黑盒。

TD6.2.3.210850、PH1A90SEG324-2、同一载体、SYN4、area_prior/partition、
min_control_set2、add_map_lut_struct on、8ns时钟。载体保留全部payload位的可观察性。

| 同AL原生opt_gate及重开 | 基线 | 阈值候选 |
| --- | ---: | ---: |
| Slice | 117 | 117 |
| LUT | 122 | 125 |
| FF | 204 | 204 |
| ERAM / DSP | 0 / 0 | 0 / 0 |
| 最差本域setup估计ns | +5.036 | +5.087 |

原始与重开面积一致，没有面积收益，候选不进入生产。初次脚本遇到Windows默认编码读取错误，
尚未启动TD；改用显式UTF-8后两臂分别44.000/40.625秒完成，单臂90秒看门狗。
本载体无物理min端点资格，hold/recovery/removal、P&R、bitgen和板级NOT_RUN。

复现：`run_ab.py --name <new_name> --td-root <TOOLS_ROOT>/TD_Release_2026.2.210.850`，
用本机登记Python执行。源码与命令哈希及原件见
[RESULTS.json](../../tmp/packer_keep_r2/keep_a1/RESULTS.json)。
