# Dark-channel restore stream: external short-test contract

Test author may read this file and their own new bench/logs only. Do not open production RTL, vendor models, old testbenches or internal hierarchy. Opaque compile and hashing are allowed. This is a pipeline boundary/liveness test, not a new full image-quality qualification.

Module `dehaze_dcp_restore4`, parameters WIDTH=256, HEIGHT=128, EXTERNAL_DARK_ENABLE=0 for the test. Production is 1920x1080, external dark statistics=1. Legal geometry: WIDTH multiple128 and >=256; HEIGHT multiple4 and >=128; tile dimensions WIDTH/16 and HEIGHT/4 <=2048; tile sample steps floor(tile/8) <=255. No simulation-only reset or hierarchy forcing.

Ports (all synchronous to positive `clk`, except active-low asynchronous `rst_n`):

```verilog
input clk,rst_n,clear,i_history_reset;
input i_enable,i_camera;
input [31:0] i_session,i_epoch,i_sequence;
input s_valid,s_sof,s_eol; output s_ready;
input [95:0] s_rgb; input [31:0] s_luma;
input [15:0] s_dark_statistics;
input i_terminal_valid,i_terminal_ok,i_terminal_camera;
input [31:0] i_terminal_session,i_terminal_epoch,i_terminal_sequence;
output m_valid,m_sof,m_eol; input m_ready;
output [95:0] m_rgb; output [31:0] m_luma;
output o_history_used,o_pending,o_pixel_pending;
```

One transfer is four pixels, RGB lane p=`s_rgb[p*24+:24]`, R/G/B bytes2/1/0; luma lane p=`s_luma[p*8+:8]`. SOF exactly first accepted group and EOL every WIDTH/4 groups; HEIGHT complete lines. Producer holds all offered fields while stalled. Output valid and fields must hold under downstream stall unless cancelled/reset; preserve raster and total groups. An inactive/first-history frame is exact identity RGB and Y (the test supplies independently computed `(77R+150G+29B+128)>>8`). Numerical processing is allowed only if `o_history_used` for that accepted frame is set. This flag is sampled for a new input SOF and stays meaningful for that frame.

Source terminal is a one-cycle observation of a separately authenticated result. Identity is camera/session/epoch/sequence; mismatch does not authorize history or release that frame's pending history. The matching terminal may coincide with input SOF, occur during the raster, or after all output. `ok=1` on a complete good raster may publish per-eye history. `ok=0` with matching key may terminate a truncated raster's estimator; it does not by itself revoke already transferred output. `clear` is the public cancellation signal for pixel drain/discard; use it for aborting an incomplete frame and before the next owner. Do not expect already accepted pixels to be replayed after cancel.

Disabled frame (`i_enable=0`) bypasses correction and creates no history obligation. For enabled frames, absence of matching terminal may retain `o_pending=1` even after `o_pixel_pending=0`; after matching terminal and bounded internal completion, both must clear, and next valid frame must be accepted. Input configuration/key is frozen from accepted SOF, must not change an owned frame. `i_history_reset` at accepted SOF invalidates previous history and makes that frame an identity first frame. Per-eye history cannot cross camera/session/epoch. A forward unsigned sequence distance1..4 is eligible; test only these defined forward cases, not backward/half-range assumptions. Map is produced from the previous qualified frame, not current partially seen input.

Known board risks: HE->dehaze and HDR->dehaze can stall control; this leaf test must independently check that enabled/disabled transitions, two alternating eyes, SOURCE timing and finite backpressure do not leave the public stream stuck. It cannot prove whole CFG ownership or identify board root cause.

Minimal cases: disabled identity with finite stalls; first enabled frame after history reset; alternating two eyes/epochs to ensure first-history identity; early matching SOURCE at SOF and late SOURCE after raster; wrong terminal ignored then matching terminal release; negative terminal plus clear on a partial raster then healthy next owner; stopped-clock reset discards held VALID and next legal frame completes. A few 256x128 rasters are short; wall timeout<=60s per invocation and simulation watchdog<=2ms. No hours-long full-HD multiframe testing. Hash DUT, TB and runner; preserve failing baseline. Test files go only in `refactor/camera_raw_r2/src_fpga/simulation/blackbox_dehaze_transition_20261109/`, artifacts under its own R2 tmp directory.

Opaque compiler input is one production file `refactor/camera_raw_r2/src_fpga/rtl/dehaze_dcp_restore4.v` (no vendor models). ModelSim root D:/App/modelsim/win64; Python python. Compile tools may require existing approved native execution. Read tool environment rules without production implementation.
