# HDR pair reader public test contract

Use the public declaration in `src_fpga/simulation/blackbox_hdr_reader_round2_20261109/hdr_reader_carrier.v` under `refactor/camera_raw_r2` for a one-clock AXI read and RAW output fixture. The carrier connects the real production HDR reader, shared decoder, two vendor-backed 512-group queues and merge. Build the carrier and all dependencies opaquely. The bench may read this document and the carrier's module declaration. Compare A/B output against the external mathematical contract independently on both builds.

## Interfaces

Sample handshakes on rising `i_clk`. Hold `i_identity_rst_n` low for at least eight running edges at startup and wait for `o_start_ready`. Use `WIDTH=68`, `HEIGHT=63`. Each exposure contains 1,071 groups, 5,355 bytes and 335 AXI words. Accept `i_start_valid && o_start_ready` with the bank, camera and merge settings held. `i_cancel=0` for normal jobs. A completed result transfers on `o_result_valid && i_result_ready`. `o_read_quiet` must already be true on this handshake. Hold `i_result_ready=0` for several edges at one terminal and check the valid and result level are stable. Wait for READY before the next START. The current job's result and output data are distinct interfaces.

AXI is a byte address with 16-byte-aligned INCR read bursts of 1–16 beats within a 4 KiB page. AR ID is 1 and ARSIZE is 4. Camera, bank and member are encoded by `0x02000000 + (4*camera + 2*bank + member)*0x01000000`; member 0 is LONG and member 1 is SHORT. For each exposure, accepted AR ranges must cover the rounded frame interval consecutively, exactly once. Return each accepted read in order with RID=ARID, RRESP=OKAY, RLAST on its last beat, and a stable beat during RREADY backpressure. For a frame tail place distinguishable sentinel bytes beyond the valid frame extent. The rounded final AXI word has 11 useful bytes. One nonterminal chunk is 512 groups in the candidate and may be shorter in the baseline. Split/order choices across members are flexible within the independent contiguous coverage contract.

The frame bytes are little-endian packed unsigned RAW10, with lane 0 in bits `[9:0]` of each five-byte four-pixel word. The first byte of an AXI word is bits `[7:0]`. Use differing data for the two members and following jobs. This checks both input streams, including pairs spanning the 512-group boundaries and 4 KiB boundary.

For each `m_valid && m_ready` the index is the zero-based raster group. The four unsigned 14-bit results are in `m_raw`, lane 0 in `[13:0]`. SOF is true for index 0, EOL for each 17th group, EOF for index 1070. Each group produces one 4-bit motion mask. Hold `m_ready` low during some offered data and require `m_valid`, RAW14, motion, index and markers to remain stable. A good job delivers exactly all groups with no extras and one successful drained result. The two public occupancy ports report real unread group counts, each in 0–512 inclusive. In the candidate, a fast responder and a temporary output hold should allow at least one queue to reach exactly 512 without overflow, then complete normally. An older implementation may peak below this value.

The public linear RAW14 formula is given for the board settings `ratio_log2=4`, black levels 50/50, motion base 64 and shift 3. For each lane let `L=max(long_raw-50,0)`, `S=max(short_raw-50,0)*16` and `W=clamp(floor((long_raw-768)/8),0,16)`. Any lane with `long_raw<896`, `short_raw>54` and `abs(L-S)>64+floor(L/8)` sets group motion. When motion is set, return `S` for all lanes and mask `4'hf`. Otherwise return `floor(((16-W)*L + W*S + 8)/16)` for each lane and mask 0. A useful data pattern varies group index and lane and includes both static mixed values and groups with motion. In particular select at least one lane above the long saturation knee or motion threshold to make the expected output depend on SHORT.

## Minimum scenarios

1. Run one clean first pair through a real output/result handshake. Count each AR and report start-to-result cycles with a specified, identical read-latency profile for baseline and candidate. Prefer a fixed nonzero AR-to-first-R latency for each accepted AR and an otherwise ready consumer so the cost of command bubbles is observable. Report only model-specific cycles and AR counts. Retain full DATA/marker comparisons or a digest for each real successful frame.
2. Exercise a run with fast AR/R and a finite downstream stall long enough to exercise the full queue, then end-of-frame partial bytes, exact 4 KiB split, data backpressure and result backpressure. Clear the stall well before the watchdog. Assert no overflow or protocol fault in either build.
3. Assert cancel while AR is presented and ARREADY is withheld, or during an accepted R burst. Retire the promised AR and all of its beats with the same protocol. Check no new command is initiated after cancellation, already offered RAW may drain, and exactly one drained unsuccessful result transfers. Next issue a different camera/bank and pixel pattern without another reset and require one real successful terminal. This is a clean cancel, so `o_protocol_fault` stays low.

One 1920×1080 address-only cursor pass per revision is optional if it fits the wall budget. A short reader A/B is sufficient with a separate arithmetic full-HD command-count derivation. The BFM validates reader behavior under its declared latency and stall profile. It excludes sensor, DDR physical controller, JPEG, RK and sustained full-HD service.

## Opaque sources and tool setup

Production RTL paths below are relative to `C:/fpga_workspace/anlogic-task3/refactor/camera_raw_r2/src_fpga`. Build these files without reading their implementations. Use separate run/library directories, identical bench and driver code, and the real fixed IP and vendor models for both A/B.

```text
rtl/hdr_pair_pixel_reader.v
rtl/hdr_pair_read_cursor.v
rtl/shared_raw10_decode_service.v
rtl/shared_raw10_decoder_masked.v
rtl/hdr_merge4.v
rtl/td_sdp_ram40.v
ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v
```

Baseline replaces only `rtl/hdr_pair_read_cursor.v` with `C:/fpga_workspace/anlogic-task3/tmp/seed12_round2_20261109/hdr_reader_baseline/hdr_pair_read_cursor.v`, preserved from `492c53845ef6d4830a6bad0759aef82c8d002df3`. In a clean checkout use the exact bytes of `git cat-file blob 30f189201135454bd78c83516e9671e2e5aa5cc3` to restore it under the run root. Its SHA256 is `328a0bf1501df4962859f4ef480857039781baeff65fbbaf26c493adcfb6d879`. Candidate uses the production path. Use `D:/App/modelsim/win64` and explicit TD root `D:/App/TD_Release_2026.2.210.850`. Compile `$TdRoot/sim_release/common/al_phy_glbl.v`, `$TdRoot/sim_release/ph1/ph1_logic_eram.v`, `$TdRoot/sim_release/ph1/ph1_phy_eram.v` in ph1, and `$TdRoot/sim_release/ph1/ph1_phy_gsr.v` in work or ph1. The test top can instantiate `PH1_PHY_GSR PH1_PHY_GSR();`. Launch with `-L ph1` and the `ph1.glbl` top. Verify source hashes for all actual compile inputs and record tool versions, exact commands and per-case watchdogs. Bound each short run to 55 seconds wall clock and a 200,000-edge watchdog, with separate limits if running the optional geometry.
