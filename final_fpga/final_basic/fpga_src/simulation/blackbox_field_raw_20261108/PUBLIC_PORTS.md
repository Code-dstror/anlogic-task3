# RAW external IO contract

Only public declarations and required externally visible behavior. Do not read production implementation.

```verilog
module stereo_raw_store #(
    parameter integer WIDTH=1920,HEIGHT=1080,EXTERNAL_DECODER=0,
    parameter integer RAW_EXPORT_ENABLE=0,VERIFY_DECODE_ACTIVE=0
)(
    input wire clk,rst_n,i_enable,i_stop,
    input wire [31:0] i_session,i_epoch,
    input wire [383:0] s_frame,input wire s_begin_valid,i_begin_camera,
    output wire s_begin_ready,o_begin_accepted,output wire [1:0] o_capture_slot,
    input wire [1:0] i_finish_valid,i_finish_ok,output wire [1:0] o_finish_ready,
    output wire o_job_valid,input wire i_job_ready,output wire [383:0] o_job_frame,
    output wire [63:0] o_job_lease,o_job_id,output wire [1:0] o_job_bayer,output wire o_job_time_valid,
    input wire i_retire_valid,input wire [63:0] i_retire_job_id,
    input wire i_release_quiet,output wire o_retire_ready,o_retire_done,o_retire_error,
    input wire i_req_valid,output wire o_req_ready,input wire [2:0] i_req_op,
    input wire i_req_camera,input wire [1:0] i_req_slot,
    input wire [31:0] i_req_generation,i_req_session,
    input wire [63:0] i_req_lease,i_req_job_id,
    output reg o_rsp_valid,input wire i_rsp_ready,output reg [3:0] o_rsp_code,
    output reg o_rsp_camera,output reg [1:0] o_rsp_slot,
    output reg [31:0] o_rsp_generation,o_rsp_session,o_rsp_sequence,o_rsp_epoch,
    input wire i_processing_done,i_processing_error,input wire [63:0] i_processing_job_id,
    output reg o_native_done,o_native_error,output wire [63:0] o_native_job_id,
    output wire [146:0] m_fifo_data,output wire m_fifo_valid,input wire m_fifo_ready,
    output wire o_read_quiet,o_empty,o_fault,
    output wire o_decode_start_valid,input wire i_decode_start_ready,
    output wire o_decode_release,o_decode_cancel,o_decode_run,
    output wire [127:0] o_decode_data,output wire [15:0] o_decode_keep,
    output wire o_decode_valid,o_decode_last,input wire i_decode_ready,
    input wire [39:0] i_decode_raw,input wire i_decode_raw_valid,
    output wire o_decode_raw_ready,input wire i_decode_sof,i_decode_eol,
    input wire i_decode_done,i_decode_aborted,i_decode_quiet,i_decode_active,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready,
    // Cold, exclusive RAW mode. The job descriptor is borrowed through SAFE.
    input wire i_raw_export,i_raw_cancel,
    output wire o_raw_record_valid,input wire i_raw_record_ready,
    output wire [31:0] o_raw_record_length,output wire [127:0] o_raw_record_identity,
    output wire [127:0] o_raw_data,output wire [15:0] o_raw_keep,
    output wire o_raw_valid,o_raw_last,input wire i_raw_ready,
    output wire o_raw_done_valid,o_raw_done_ok,o_raw_drained,
    input wire i_raw_retire_valid,output wire o_raw_retire_ready,
    input wire [127:0] i_raw_retire_identity
);

```

```verilog
module raw_video_record_formatter (
    input wire i_clk,i_rst_n,
    input wire i_start_valid,output wire o_start_ready,
    input wire i_abort,output wire o_drained,
    input wire [31:0] i_payload_bytes,
    input wire [15:0] i_width,i_height,
    input wire [31:0] i_sequence,i_session,i_epoch,
    input wire i_camera,input wire [1:0] i_bayer_phase,input wire i_time_valid,
    input wire [63:0] i_capture_time_ns,i_job_id,
    input wire [127:0] s_data,input wire [15:0] s_keep,
    input wire s_valid,s_last,output wire s_ready,
    output reg [127:0] m_data,output wire [15:0] m_keep,
    output wire m_valid,m_last,input wire m_ready,
    output wire o_done
);

```



`raw_video_record_formatter` 位于 DDR DFI 时钟域。完成所有写响应和真实 SOURCE 终态的 RAW10 帧由现有 owner 持有。读服务使用同一槽，送出原始 128-bit DDR 数据、低位连续 `KEEP` 和帧末 `LAST`。有效字节按 lane0 到 lane15 前进。四个连续 10-bit 样本依次占 40-bit 字的 `[9:0]` 至 `[39:30]`，该字以小端顺序占五字节。每行宽度是四样本的倍数，行间无填充。

`i_start_valid && o_start_ready` 开始封装。四拍各 16 字节的 ARAW 头由当前拍选择拼接，随后直接传递 payload。头部字段和宽度见 [ARAW v1](../../../docs/raw_video_v1.json)。`capture_time_ns` 仅在 `flags[0]` 为 1 时有效，Bayer 沿用 SDR 目录的 RGGB、GRBG、GBRG、BGGR 编号 0 至 3。头部预留字节为零，payload 长度由 owner 提供。现有 C2H 层按记录总长度校验 `KEEP` 和 `LAST`。

源在 START 接受后保持 descriptor，直到 formatter 完成或排空。帧 owner 继续持槽至准确的 C2H 退休。反压时头部拍计数停住，body 由上游保持 `VALID/DATA/KEEP/LAST`。`o_done` 表示真实最后一拍握手，`o_drained` 表示 formatter 空闲。所有信号同域，复位由共同冷复位控制。

读服务在已呈现的 payload 和 DDR 事务排空后可宣告 `i_abort`，并保持该信号到 `o_drained`。若头部已呈现，该拍保持到真实握手，随后排空；若处于 body 等待，则直接排空。负终态由读服务和现有 C2H 层传递，formatter 不生成成功或补造 `LAST`。


## ARAW binary format
```json
{
  "name": "ARAW",
  "magic": 1463898689,
  "version": 1,
  "header_bytes": 64,
  "payload_max_bytes": 16777216,
  "format_raw10": 1,
  "flag_timestamp_valid": 1,
  "byte_order": "little",
  "bayer_phases": {
    "RGGB": 0,
    "GRBG": 1,
    "GBRG": 2,
    "BGGR": 3
  },
  "fields": [
    {"name": "magic", "offset": 0, "bytes": 4},
    {"name": "version", "offset": 4, "bytes": 2},
    {"name": "header_bytes", "offset": 6, "bytes": 2},
    {"name": "payload_bytes", "offset": 8, "bytes": 4},
    {"name": "width", "offset": 12, "bytes": 2},
    {"name": "height", "offset": 14, "bytes": 2},
    {"name": "source_sequence", "offset": 16, "bytes": 4},
    {"name": "source_session", "offset": 20, "bytes": 4},
    {"name": "mode_epoch", "offset": 24, "bytes": 4},
    {"name": "camera", "offset": 28, "bytes": 1},
    {"name": "format", "offset": 29, "bytes": 1},
    {"name": "bayer_phase", "offset": 30, "bytes": 1},
    {"name": "flags", "offset": 31, "bytes": 1},
    {"name": "capture_time_ns", "offset": 32, "bytes": 8},
    {"name": "job_id", "offset": 40, "bytes": 8},
    {"name": "reserved", "offset": 48, "bytes": 16}
  ]
}

```
