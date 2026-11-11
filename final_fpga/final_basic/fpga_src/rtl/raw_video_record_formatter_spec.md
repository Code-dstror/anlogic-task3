# ARAW 直传封装

`raw_video_record_formatter` 位于 DDR DFI 时钟域。完成所有写响应和真实 SOURCE 终态的 RAW10 帧由现有 owner 持有。读服务使用同一槽，送出原始 128-bit DDR 数据、低位连续 `KEEP` 和帧末 `LAST`。有效字节按 lane0 到 lane15 前进。四个连续 10-bit 样本依次占 40-bit 字的 `[9:0]` 至 `[39:30]`，该字以小端顺序占五字节。每行宽度是四样本的倍数，行间无填充。

`i_start_valid && o_start_ready` 开始封装。四拍各 16 字节的 ARAW 头由当前拍选择拼接，随后直接传递 payload。头部字段和宽度见 [ARAW v1](../../docs/raw_video_v1.json)。`capture_time_ns` 仅在 `flags[0]` 为 1 时有效，Bayer 沿用 SDR 目录的 RGGB、GRBG、GBRG、BGGR 编号 0 至 3。头部预留字节为零，payload 长度由 owner 提供。现有 C2H 层按记录总长度校验 `KEEP` 和 `LAST`。

源在 START 接受后保持 descriptor，直到 formatter 完成或排空。帧 owner 继续持槽至准确的 C2H 退休。反压时头部拍计数停住，body 由上游保持 `VALID/DATA/KEEP/LAST`。`o_done` 表示真实最后一拍握手，`o_drained` 表示 formatter 空闲。所有信号同域，复位由共同冷复位控制。

读服务在已呈现的 payload 和 DDR 事务排空后可宣告 `i_abort`，并保持该信号到 `o_drained`。若头部已呈现，该拍保持到真实握手，随后排空；若处于 body 等待，则直接排空。负终态由读服务和现有 C2H 层传递，formatter 不生成成功或补造 `LAST`。
