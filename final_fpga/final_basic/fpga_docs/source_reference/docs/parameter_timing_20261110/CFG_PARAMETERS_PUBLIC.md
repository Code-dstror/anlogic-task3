# Public black-box contract: existing RK parameter transactions

Only this contract, public `docs/pcie_protocol_v1.json`, and the author's own new test code may be read.
Production RTL, vendor model implementations, old benches/runners and internal hierarchy are opaque.
Compile them and take hashes; return implementation-revealing compile errors to the maintainer.
This task exercises current functionality; it does not open black-level adjustment or change the wire ABI.

## Interface and production profile

Module `mono_config_service_v2` parameters:
`PROFILE=1, MAX_WIDTH=1920, MAX_HEIGHT=1080, REMOTE_CONFIG_ENABLE=1, EXT_WIDTH=1024,
EXT_STRIPS=4, EXT_COMBINATIONS=0, EXT_SUPPORTED=8'h34, V2_SUPPORTED_MODES=3'b101,
V2_SUPPORTED_ENABLES=6'h3f, LIVE_GRAY_FIXED_ENABLE=0, LIVE_BASIC_MODES_ENABLE=1,
COMPACT_EMPTY_EXTENSION_ENABLE=0, COMPACT_STAGE2_EXTENSION_ENABLE=1,
LANE_GAUSSIAN_ONLY=1, CFG_DIAG_ENABLE=0, STEREO_CAPABLE=1, APPLY_SOURCE_FAULT_ENABLE=1`.

| Domain | Public ports |
|---|---|
| clocks/reset | input `user_clk,user_rst_n,pixel_clk,pixel_rst_n` |
| USER input | `i_stereo_mode,write_valid,read_valid`, `write_offset[11:0],read_offset[11:0]`, `write_data[31:0]`, `write_strobes[3:0]` |
| USER output | `o_user_transaction_idle,o_user_stereo_compatible,read_response_valid,user_initialized`, `write_response[1:0],read_response[1:0]`, `read_data[31:0],user_session[31:0]` |
| PIX input | `pipeline_idle,frame_accept,i_apply_source_fault`, `frame_sequence[31:0]`, `m_config_ready,s_config_ack_valid,s_config_ack_ok`, `s_config_ack_data[1183:0]` |
| PIX output | `source_ready,pause_new_jobs,pixel_initialized,config_fault,s_config_ack_ready,m_config_valid`, `source_session[31:0],mode_epoch[31:0],config_stale_ack_count[31:0]`, `m_config_data[1183:0],active_config[1183:0]` |
| PIX output fields | `active_mode[1:0],active_quality[7:0],adaptive_quality,minimum_quality[7:0],frame_budget[24:0],restart_mcus[15:0],active_schema2,active_legacy_gaussian,active_product_mode[1:0],active_processing_enables[5:0]` |
| observation | input `diag_observer_rst_n[1:0],diag_source_fs,diag_source_gates[15:0]` tie zero; output `diag_domains[447:0],diag_domain_reset_n[1:0],o_apply_diagnostics[11:0]` need not inspect |

Independent continuous USER/PIX clocks, e.g. 8/10ns. Both active-low resets initially asserted for multiple edges.
`i_stereo_mode` is cold-selected before release; use a separate coordinated reset/session for each topology.
Compiled PROFILE is always 1, while dual runtime reports profile 2, camera_present 3 and enables 0x0f.
Mono reports profile 1, camera_present 1 and enables 0x3f. Product modes are SDR=0 or HDR=2.
All sampled ports use the domain's rising edge. Present stable values before that edge.
BAR offsets are user-page relative byte addresses, 32-bit aligned, full writes use strobes 0xf.
A write offer lasts one USER edge; sample response with the offer. Reads pulse read_valid and await read_response_valid.

After reset, acknowledge the real BOOT tuple at `m_config_*` with the exact tuple through `s_config_ack_*`, OK=1.
Hold valid/data until that interface's handshake. Poll SESSION_READY before issuing commands. A remote ACK model represents
the downstream whole configuration owner, not a physical sensor model. Keep pipeline_idle high for initial BOOT.

The public config tuple is `{extension[1023:0],base_identity[159:0]}` with request ID bits31:0,
session63:32, mode65:64, quality72:66, adaptive73, minimum80:74, budget105:81,
restart121:106, reserved127:122=0, epoch159:128. Extension is exactly the 32 words in the protocol schema.
Use actual SESSION and monotonically owned request sequence. BEGIN/PREPARE_EXT, COMMIT, STATUS and ACTIVE addresses/codes
come from the public JSON. COMMIT must use the exact prepared request identity. A transport write ACK is not CFG APPLIED.
Before PREPARE negotiate `CFG_HOST_CAPABILITIES` at 0x274 with FRAME_APPLIED bit0=1 and only device-advertised
CFG_FEATURES bits. Minimal value1 is sufficient. This is an existing ABI requirement (docs/s01_config_transaction.md),
not a newly added behavior. Missing FRAME_APPLIED is INVALID and must not be mistaken for a parameter-range test.
The initial handoff omitted this prerequisite; cfg_002's otherwise-legal requests without negotiation are retained
as a contract/fixture failure, not a production defect or positive coverage of the requested parameters.

PREPARE pauses new work and waits for `pipeline_idle=1` (old work drained) before READY. READY remains BUSY.
COMMIT sends the complete tuple. Delayed remote request/ACK must retain identity and hold ACTIVE/epoch unchanged.
A positive matching remote ACK alone is not APPLIED. At least one subsequent PIX edge must establish frame eligibility;
then an actual `frame_accept` pulse with `source_ready=1` publishes the new tuple/epoch and source frame_sequence.
After the matching whole ACK, **pipeline_idle may be zero due to newly started work; it must not block APPLIED**.
Premature frame_accept before the matching ACK cannot publish the new epoch. For HDR the pulse models an actually qualified
LONG boundary of the required running camera set, not configuration ACK or arbitrary physical FS.
`i_apply_source_fault` denotes terminal failure, not training. Once owned apply is active, fault wins over frame_accept,
produces ERROR/RESET(6), clears BUSY/READY/APPLIED, retains old ACTIVE and requires a coordinated restart for recovery.
Fresh reset/BOOT must then allow a legal positive transaction. Do not equate source_ready alone to admission:
before COMMIT, no new work may enter while pause_new_jobs is high.

## Existing legal parameters and invalid controls

Basic: mode COLOR=0 for schema2; Q1..100, minQ1..Q, flags0/1, budget0..16777216 bytes,
restart0..65535 MCU. flags1 requires nonzero budget. Unknown flags/partial reserved forms invalid.
Default Q75/minQ1/flags0/budget0/restart0. Adaptive budget is not a hard output size bound.

HDR: ratio4, black_long50, black_short50, qualification15 remain fixed. Motion base0..16383,
shift0..15, delta0..0xffffffff (64-bit field's high word zero), wait/age1..0xffffffff nanoseconds.
Public example: motion64/3, delta50000000, wait100000000, age1000000000.
SDR has all HDR fields zero. Dehaze generation is0 or1 if enabled, otherwise0; both select the built-in profile.
Processing enables: gray1, dehaze2, Gaussian4, HE8, F22=16, lane32. lane requires F22 and only mono supports 16/32.
Other bits and schema2 reserved words must be zero. No LZ product, no dynamic black or exposure ratio.

Expected negative PREPARE is ERROR with prior ACTIVE/epoch intact and no downstream config offer. Use independent sessions
or the documented new-request recovery when the chosen case owns a terminal error; never hide a failure by unsolicited retry.
Verify legal first transaction across real BAR/CDC/service to USER APPLIED, then consecutive legal updates, edge values,
at least one finite request/ACK stall, illegal flag/budget/minQ/range/high-delta/zero-wait/black and unsupported dual lane.
Include the public historical counterexample: valid whole ACK followed by a genuine new frame while pipeline_idle remains0.
Use a short mode sequence HE→dehaze→HDR→dehaze with real tuple/epoch checks, not full image simulation.
Bound the test (e.g. <=1ms simulation and <=60s wall per run) and retain original FAILs with DUT/contract/fixture/tool classification.
This does not qualify pixel algorithms, camera I²C, full-HD frame rate, DDR or board behavior.

## Opaque compile list

Repository root `C:/fpga_workspace/anlogic-task3`; target root `refactor/camera_raw_r2/src_fpga`.
ModelSim `D:/App/modelsim/win64`, Python `python`;
TD root explicitly `D:/App/TD_Release_2026.2.210.850`. Create fresh libraries and output folders per run.

Compile RTL: `rtl/td_sdp_ram40.v`, `rtl/reset_release_sync.v`, `rtl/control_fifo_40x512.v`,
`rtl/control_message_fifo_ip.v`, `rtl/mono_config_byte_store_v2.v`, `rtl/mono_config_legacy_scan_v1.v`,
`rtl/mono_config_scan_v2.v`, `rtl/mono_config_bar_v2.v`, `rtl/mono_config_engine_v2.v`, `rtl/mono_config_service_v2.v`.
IP: `ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v`,
`ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v`,
`ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v`,
`ip/camera_control_fifo_40x512/camera_control_fifo_40x512.v`.
Include dirs: `rtl/include/00_rtl`, `01_include`, `02_jpeg`, `03_mono_config_v2_20261015`, `04_include` (all under `rtl/include`).
Defines: `PH1`, `C15_F23_FULLHEIGHT_PROFILE=1`.
TD model library ph1 under TD_ROOT/sim_release: `common/al_phy_glbl.v`, `ph1/ph1_logic_eram.v`,
`ph1/ph1_logic_fifo.v`, `ph1/ph1_logic_ramfifo.v`, `ph1/ph1_phy_eram.v`, `ph1/ph1_phy_fifoctrl.v`.
Compile `ph1/ph1_phy_gsr.v` in work, run with `-L ph1 work.PH1_PHY_GSR ph1.glbl work.<testtop>`.
Treat global startup as a model prerequisite; all stimulus starts after genuine BOOT/SESSION_READY.
