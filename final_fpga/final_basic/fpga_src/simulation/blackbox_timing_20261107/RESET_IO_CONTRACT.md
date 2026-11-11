# Camera RAW reset phase gate

This handoff contains public port declarations and behavioral requirements. Author the verification from this handoff. Use the listed production Verilog files solely as opaque compiler inputs. Observe the declared ports through ordinary ready/valid sampling.

## Release contract

Define R1 as the first rising local clock edge after the common asynchronous reset goes high. R2, R3 and R4 are the next rising edges. F3 is the falling edge between R3 and R4. Use reset_release_sync_data with DATA_RESET_COPIES=0 and FALLING_RELEASE=1. It asserts both outputs low without a clock, releases o_data_rst_n just after R3, and releases o_rst_n just after F3. With FALLING_RELEASE=0 both outputs release at R3. If the clock stops, it cannot advance a release. An assertion cancels any pending release, including between R3 and F3.

For the PIX builder and join, instantiate SEPARATE_DATA_RESET=1 and drive i_data_reset_n from o_data_rst_n and i_rst_n from o_rst_n. In legacy mode SEPARATE_DATA_RESET=0, the extra input is ignored and the existing i_rst_n drives both roles. For the DFI metadata gate, the production test input i_rst_n is o_data_rst_n because the entire gate and its store sample reset on rising DFI edges. A corresponding baseline instance can use o_rst_n. Compare clocked handshakes immediately before rising edges and valid output data, allowing READY to be visible between R3 and F3 in the production profile. R4 is the first common legal acceptance edge. Check asynchronous assertion on qualified VALID and READY while the clock is stopped. For metadata status held in synchronous state, check its reset effect at the first rising clock edge held in reset.

## PIX scenario

Use the production builder and join back to back. Set NEUTRAL_STATS_ENABLE=0 for the shortest case and tie unused stats, source flags and all feature inputs to zero. Use source session 1, epoch 7, a fresh nonzero sequence, camera 0, physical source kind 1, RAW10 format 1, exposure role 0 and time quality 0. For each new descriptor form the join context as {16'd1,16'd0,8'd1,8'd1,8'd1,8'd0,sequence[31:0],epoch[31:0],session[31:0]}. Set s_begin_features=0 and set s_begin_valid on both instances only when the request and both o_begin_ready are high. Connect builder m_extension_* to join s_context2_* with the corresponding READY. Send a matching one-cycle terminal after admission, with s_terminal_error=0.

Offer the first descriptor before R3 and check that both can accept at R4. The builder emits a 1024-bit v2 extension with magic 0x32585443 in bits 31:0, version 1 in 47:32, session in 95:64, epoch in 127:96 and sequence in 159:128. The join presents a 2048-bit extension after the matching terminal and source are both available, and bits 1023:0 contain the unchanged source extension. Hold downstream READY low for at least five rising clocks and check VALID and data stability. Consume one result by handshake. For a second descriptor, hold a result, stop the clock and assert reset. After clock restart and release, check that no pre-reset result transfers and a third distinct descriptor completes. If exercising the join's separate stream interface, leave m_extension_ready low, pulse i_stream_start once while m_extension_valid is high and stall m_stream_ready while m_stream_valid is high before resetting. Ignore invalid payload bits. No lane data is required with s_begin_features=0.

## DFI scenario

Instantiate jpeg_record_metadata_gate with RECORD_EXTENSION_WIDTH=1024 and its other default parameters. This exercises the production metadata store through the gate, using the vector response profile to keep the test short. Tie the mask and staging inputs to zero and select i_selected_version=2. Use the same owner and result identity and legal slot 0 for camera 0, with nonzero generation. Hold s_start_valid and its descriptor until o_start_ready. The gate reserves on the first eligible rising edge and then holds o_ring_start_valid. A real START acceptance needs i_ring_start_ready; drive it low for five rising edges after reservation to prove hold. With i_ring_start_ready already high on R4 and START held, the first reservation occurs at R4 and START can transfer at R5. There is no transfer on R1–R3.

After acceptance the owner can take one extension and the matching successful result. Supply a 1024-bit zero-filled extension with only bits 31:0=0x32585443, 47:32=1, bit 48=1, 95:64=session, 127:96=epoch, 159:128=sequence, 167:160=camera, 175:168=1 (physical), 183:176=1 (RAW10). Keep 255:192 zero on input. On successful publication the gate returns the extension with session copied into 223:192 and generation into 255:224. Drive i_ready_valid with the exact tuple, wait up to 128 local rising edges for o_header_ready, then check the result. Hold it a few cycles before pulsing i_header_fire. Only the same tuple may be consumed. Reserve a new START, stall the ring and stop the clock before asserting reset. The qualified START output must drop without a clock. After restart, complete a new record with a different tuple and verify no stale START or header is transferred. A standalone store test is optional because this gate's successful transaction exercises its real store, RAM write/read and ownership. The TOP also qualifies its retained memory fault from the same rising-edge release. It still observes real incidents asynchronously at runtime, and the cold qualification reaches the same first DFI sample as the original release.

## Opaque compiler inputs

All FPGA paths are relative to C:/fpga_workspace/anlogic-task3/refactor/camera_raw_r1.

- RTL inputs are src_fpga/rtl/reset_release_sync_data.v, src_fpga/rtl/frame_record_extension_builder.v, src_fpga/rtl/frame_record_v3_join.v, src_fpga/rtl/jpeg_record_metadata_gate.v, src_fpga/rtl/jpeg_record_metadata_store.v, src_fpga/rtl/jpeg_metadata_read_arbiter.v, src_fpga/rtl/lane_sparse_extension_checker.v and src_fpga/rtl/td_sdp_ram40.v.
- Include paths are src_fpga/rtl/include/01_include and src_fpga/rtl/include/04_include.
- For the DFI case add src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v. Bind the TD root explicitly to D:/App/TD_Release_2026.2.210.850 and compile its sim_release/common/al_phy_glbl.v and sim_release/ph1/{ph1_logic_eram.v,ph1_phy_eram.v,ph1_phy_gsr.v}. Elaborate PH1_PHY_GSR and glbl as sibling tops with the testbench. The ModelSim binaries are in D:/App/modelsim/win64. A PIX-only case has no TD primitive dependency.
- Use a separate work directory and a finite simulation timeout. Retain the exact commands and source hashes in the run outputs.

## Port declarations


```verilog
module reset_release_sync_data #(
    parameter integer DATA_RESET_COPIES = 3,
    parameter integer FALLING_RELEASE = 0
) (
    input wire i_clk,
    input wire i_async_rst_n,
    output wire o_rst_n,
    output wire [(DATA_RESET_COPIES > 0 ? DATA_RESET_COPIES : 1)-1:0] o_data_rst_n
);
```

```verilog
module frame_record_extension_builder #(
    parameter integer NEUTRAL_STATS_ENABLE = 0,
    parameter integer OBSERVATION_WIDTH = 320,
    parameter integer OBSERVATION_HEIGHT = 180,
    parameter integer SEPARATE_DATA_RESET = 0
) (
    input wire i_clk,
    input wire i_rst_n,
    input wire s_begin_valid,
    output wire o_begin_ready,
    input wire [31:0] i_source_session,
    input wire [31:0] i_source_epoch,
    input wire [31:0] i_source_sequence,
    input wire [7:0] i_source_camera,
    input wire [7:0] i_source_kind,
    input wire [7:0] i_source_format,
    input wire [7:0] i_exposure_role,
    input wire i_exposure_valid,
    input wire [31:0] i_actual_exposure,
    input wire [31:0] i_exposure_group,
    input wire i_gain_valid,
    input wire [31:0] i_actual_gain,
    input wire i_calibration_valid,
    input wire [31:0] i_calibration_id,
    input wire [7:0] i_time_quality,
    input wire i_pair_valid,
    input wire [63:0] i_pair_id,
    input wire i_job_valid,
    input wire [63:0] i_job_id,
    input wire i_write_tag_valid,
    input wire [63:0] i_write_tag,
    input wire i_qualified,
    input wire [7:0] i_processing_member,
    input wire [7:0] i_processing_mode,
    input wire [15:0] i_record_flags,
    input wire s_stats_valid,
    output wire o_stats_ready,
    input wire [159:0] s_stats_context,
    input wire [183:0] s_statistics,
    output wire m_extension_valid,
    input wire m_extension_ready,
    output reg [1023:0] m_extension_data,
    output reg [31:0] o_stale_count,
    output reg [31:0] o_error_count,
    output wire o_input_fault,
    input wire i_data_reset_n
);
```

```verilog
module frame_record_v3_join #(
    parameter integer SEPARATE_DATA_RESET = 0
) (
    input wire i_clk,i_rst_n,
    input wire s_begin_valid,
    output wire o_begin_ready,
    input wire [159:0] s_begin_context,
    input wire [3:0] s_begin_features,
    input wire s_terminal_valid,s_terminal_error,
    input wire [159:0] s_terminal_context,
    input wire [1023:0] s_context2_extension,
    input wire s_context2_valid,
    output wire o_context2_ready,
    input wire [683:0] s_f22_record,
    input wire s_f22_valid,
    output wire o_f22_ready,
    input wire [176:0] s_f23_record,
    input wire s_f23_valid,
    output wire o_f23_ready,
    input wire [207:0] s_f24_record,
    input wire s_f24_valid,
    output wire o_f24_ready,
    input wire [264:0] s_f25_record,
    input wire s_f25_valid,
    output wire o_f25_ready,
    output wire [2047:0] m_extension,
    output wire m_extension_valid,
    input wire m_extension_ready,
    input wire i_stream_start,
    output wire [127:0] m_stream_data,
    output wire m_stream_valid,
    input wire m_stream_ready,
    output wire o_lane_read_enable,
    output wire [8:0] o_lane_read_index,
    input wire [39:0] i_lane_read_data,
    input wire i_lane_read_valid,
    output reg o_fault,
    output reg [31:0] o_stale_count,
    input wire i_data_reset_n
);
```

```verilog
module jpeg_record_metadata_gate #(
    parameter integer RECORD_EXTENSION_WIDTH=1024,
    parameter integer BORROW_PENDING_EXTENSION=0,
    parameter integer STAGING_EXTENSION_ENABLE=0,
    parameter integer BORROW_HEADER=0,
    parameter integer STREAM_READ=0,
    parameter integer SHARED_MASK_METADATA=0
) (
    input wire i_clk,i_rst_n,
    input wire s_start_valid,
    output wire o_start_ready,
    input wire [31:0] s_start_writer_tag,s_start_sequence,s_start_session,s_start_epoch,
    input wire s_start_camera,
    input wire i_ring_start_ready,
    output wire o_ring_start_valid,
    output wire o_start_reserved,
    input wire [RECORD_EXTENSION_WIDTH-1:0] s_extension,
    input wire s_extension_valid,
    output wire o_extension_ready,
    input wire s_extension_shape_valid,
    output wire o_extension_read_enable,
    output wire [8:0] o_extension_read_index,
    input wire [39:0] i_extension_read_data,
    input wire s_write_result_valid,
    output wire o_write_result_ready,
    input wire [31:0] s_write_result_tag,s_write_result_sequence,s_write_result_session,s_write_result_epoch,
    input wire s_write_result_camera,
    input wire [15:0] s_write_result_slot,
    input wire [31:0] s_write_result_generation,
    input wire s_write_result_ok,
    input wire [7:0] s_write_result_error,
    input wire i_ready_valid,
    input wire [15:0] i_ready_slot,
    input wire [31:0] i_ready_generation,i_ready_session,i_ready_sequence,i_ready_epoch,
    input wire i_ready_camera,
    input wire [15:0] i_selected_version,
    output wire o_header_ready,
    output wire [RECORD_EXTENSION_WIDTH-1:0] o_header_extension,
    input wire i_header_fire,
    input wire i_header_release,
    output wire [127:0] o_header_stream_data,
    output wire o_header_stream_valid,o_header_stream_last,
    input wire i_header_stream_ready,
    input wire s_mask_req_valid,
    output wire o_mask_req_ready,
    input wire [15:0] s_mask_req_slot,
    input wire [31:0] s_mask_req_generation,s_mask_req_session,s_mask_req_sequence,s_mask_req_epoch,
    input wire s_mask_req_camera,
    output wire o_mask_rsp_valid,o_mask_rsp_ok,
    input wire i_mask_rsp_ready,
    output wire [7:0] o_mask_rsp_error,
    output wire [15:0] o_mask_rsp_slot,
    output wire [31:0] o_mask_rsp_generation,o_mask_rsp_session,o_mask_rsp_sequence,o_mask_rsp_epoch,
    output wire o_mask_rsp_camera,o_mask_rsp_qualified,
    output wire [23:0] o_mask_rsp_pixels,
    output wire [2:0] o_mask_rsp_source_type,
    output wire o_quiescent,
    output wire o_fault,
    output wire [31:0] o_stale_write_count,o_bad_extension_count
);
```

```verilog
module jpeg_record_metadata_store #(
    parameter integer RECORD_EXTENSION_WIDTH=1024,
    parameter integer BORROW_PENDING_EXTENSION=0,
    parameter integer STAGING_EXTENSION_ENABLE=0,
    parameter integer STREAM_READ=0,
    parameter integer BORROW_READ_IDENTITY=0,
    parameter integer MASK_READ=0
) (
    input wire i_clk,i_rst_n,
    input wire s_begin_valid,
    output wire s_begin_ready,
    input wire [31:0] s_begin_writer_tag,s_begin_sequence,s_begin_session,s_begin_epoch,
    input wire s_begin_camera,
    input wire [RECORD_EXTENSION_WIDTH-1:0] s_extension,
    input wire s_extension_valid,
    output wire s_extension_ready,
    input wire s_extension_shape_valid,
    output wire o_extension_read_enable,
    output wire [8:0] o_extension_read_index,
    input wire [39:0] i_extension_read_data,
    input wire s_write_result_valid,
    output wire s_write_result_ready,
    input wire [31:0] s_write_result_tag,s_write_result_sequence,s_write_result_session,s_write_result_epoch,
    input wire s_write_result_camera,
    input wire [15:0] s_write_result_slot,
    input wire [31:0] s_write_result_generation,
    input wire s_write_result_ok,
    input wire [7:0] s_write_result_error,
    output wire o_write_quiescent,
    output wire o_read_quiescent,
    output reg o_protocol_fault,
    output reg [31:0] o_stale_write_count,o_bad_extension_count,
    output reg o_bad_extension_seen,
    output reg [7:0] o_write_error,
    input wire s_read_req_valid,
    output wire s_read_req_ready,
    input wire [15:0] s_read_req_slot,
    input wire [31:0] s_read_req_generation,s_read_req_session,s_read_req_sequence,s_read_req_epoch,
    input wire s_read_req_camera,
    output wire o_metadata_available,
    output reg m_read_rsp_valid,
    input wire m_read_rsp_ready,
    output reg m_read_rsp_ok,
    output reg [7:0] m_read_rsp_error,
    output wire [15:0] m_read_rsp_slot,
    output wire [31:0] m_read_rsp_generation,m_read_rsp_session,m_read_rsp_sequence,m_read_rsp_epoch,
    output wire m_read_rsp_camera,
    output wire [RECORD_EXTENSION_WIDTH-1:0] m_read_rsp_extension,
    input wire [15:0] s_read_req_version,
    output wire m_read_rsp_shape_valid,
    input wire s_read_stream_start,
    output wire [127:0] m_read_stream_data,
    output wire m_read_stream_valid,m_read_stream_last,
    input wire m_read_stream_ready,
    input wire s_read_req_mask,
    output wire m_read_rsp_mask_qualified,
    output wire [23:0] m_read_rsp_mask_pixels,
    output wire [2:0] m_read_rsp_source_type
);
```

## Clarifications from independent interface tests

The PIX join borrows the producer's valid extension. Its SOURCE handshake occurs on the same edge as the joined output handshake; do not wait for SOURCE acceptance before sending the matching terminal. During a stalled valid joined output, compare its low 1024 bits against the producer's currently valid, stable extension.

The earliest DFI R4 reservation requires ring_ready high at R4. To test withdrawal of READY after an offer, lower ring_ready after reservation and before R5. A low ring_ready before reservation need not produce a START offer.

The DFI opaque model list also includes TD sim_release/ph1/ph1_logic_dram.v.
