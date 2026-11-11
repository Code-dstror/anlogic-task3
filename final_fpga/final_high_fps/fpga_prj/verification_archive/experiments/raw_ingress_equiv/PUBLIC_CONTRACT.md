# RAW10 ingress 公开接口合同

以本文、`PORTS.vh` 和不透明编译清单为输入。两份叶文件分别编译到不同工作库。
可编译和取哈希，不能打开叶实现、旧测试或内部信号。独立期望由下列端口合同给出。

## 参数与事件

| 测试用途 | WIDTH×HEIGHT | UHD_WIDTH×UHD_HEIGHT | COMPACT_CAPTURE_HEADER | FIXED_HDR_ROLE |
| --- | --- | --- | ---: | ---: |
| 一份例化切换 HD、UHD | 32×2 | 64×2 | 1 | 0 |
| 固定 CAM1 LONG / SHORT | 32×2 | 0×0 | 0 | 1 / 2 |
| 非整拍尾字的兼容门 | 40×2 | 0×0 | 1 | 0 |

所有行设置 `CONTEXT_ENABLE=EXTERNAL_SEQUENCE_ENABLE=PAIR_METADATA_ENABLE=SOURCE_TERMINAL_ENABLE=1`。
生产 HD/UHD 分别为 1920×1080 和 3840×2160。UHD 仅允许 camera0 SDR，`i_uhd` 在 SOF 冻结本帧尺寸。
SDR 的 Bayer 元数据有效。固定 CAM1 要求 `i_camera=1,i_accept=1,i_sdr_profile=0`，来源 kind、metadata valid、
source qualified 均为 1，曝光角色匹配参数，gain=256、calibration=0x56a3d02f，LONG/SHORT 曝光分别为 3200/200。

异步低有效复位清除所有权。各接口在 PIX 上升沿采样。相机数据在 `i_valid && i_accept` 时被观察，
入口没有相机 READY。合法 SOF 是首组，EOL 每行第 width/4 组。开始边 `o_frame_accept` 为 1，包括前一
终态正好被接收的同一边沿。输出在 `o_axis_tvalid && i_axis_tready` 时传输，stall 保持完整有效 offer。
只比较有效输出。复位中的 payload 无定义。收到最后的已承诺 token 后 `o_capture_idle` 回到 1。

## 数据和终态

每个 `i_data` 为四个连续 RAW10 像素，p0 在低位。按每个已接受 group 的低五个字节、低字节先进入
独立队列。行之间连续打包。DATA 每拍最多 16 字节，从 `TDATA[7:0]` 开始。KEEP 标识低侧有效字节，
无效 DATA 字节为零，LAST 只标记最后一个 DATA 拍，含恰好整拍的尾。总字节数为
`5*(width/4)*height`，每个像素组按接受顺序出现一次。

| Token | TUSER | TLAST | TKEEP | TDATA，高位在左 |
| --- | ---: | ---: | --- | --- |
| START | 1 | 0 | compact 为 c030，fixed 为 ffff | {exposure_group, epoch, session, external_sequence} |
| compact CONTEXT 1 | 1 | 1 | ffff | {gain, actual_exposure, timestamp}，SDR 的 time_valid=0 时 timestamp 为零 |
| compact CONTEXT 2 | 1 | 1 | ffff | {epoch, external_sequence, calibration_id, 6'd0, uhd, camera, flags[23:0]} |
| fixed-role CONTEXT | 1 | 1 | 合法 LONG 为 ca17，SHORT 为 ca1b | {epoch, external_sequence, timestamp} |
| DATA | 0 | 见上文 | 见上文 | 见上文 |
| END | 2 | 0 | ffff | {63'd0,1'b1,samples[31:0],byte_count[31:0]} |
| ABORT | 3 | 0 | ffff | 0 |

flags[3:0] 为 SDR 3 或 HDR 1。flags[4] 为 source_kind，flags[6:5] 为 exposure_role，
flags[7] 为 source_qualified，flags[8] 为 metadata_valid。SDR 还编码 flags[10:9]=bayer_pattern、
flags[11]=bayer_valid、flags[12]=time_valid，其他 flag 位为零。

`o_source_ready` 出复位即有效。SOURCE 由 exact camera/session/epoch/sequence 归属当前已开始帧，正常时在
全部 RAW 输入后发出一次，只有 `i_source_ok=1` 且 `i_source_error=0` 成功。匹配的好 SOURCE 和全部 DATA
都完成后才可 END。旧或重复 SOURCE 增加饱和 stale 计数。匹配坏 SOURCE、capture 中禁用/取消、错误
SOF/EOL 或 capture 输出不能按时接收，走负终态，已接受的 DATA 保持计数。一个失败帧最多一个 ABORT、
一次 drop/error 增量。几何 EOF 已被接收后，可有限停顿并恢复。若等待时故障，已呈现的末拍必须
保持并先传输，然后才 ABORT。出现复位时所有在途归属清除。

## 短测风险

- 每种整拍型配置至少一笔合法首帧，经实际入口接受至匹配 SOURCE 与完整 END。变化的像素编码覆盖
  RAW10 五种字节切分，相邻组连续送入，在行边界加入接受空洞。比对全部握手 payload/sideband。
- HD/UHD 尺寸在帧间切换。帧中改变未被采样的 i_uhd 或元数据，活跃帧的尺寸/头保持。
- 末个完整 DATA 在 EOF 后被暂停，延后或注入 stale SOURCE 后合法退休。另测匹配坏 SOURCE、
  捕获阶段 stall、早 EOL 或 mid-frame SOF、清除与下一新序号合法帧，确认终态及恢复。
- 非整拍型保留 4-byte 尾、KEEP 和零填充。限制每进程墙钟与仿真 watchdog，保留源及测试哈希。

同一输入序列允许记录两臂的有效公开事件是否逐沿一致，数值期望仍来自上述独立字节队列。
