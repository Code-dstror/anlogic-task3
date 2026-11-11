# HD/UHD F21 public interface

## Profiles and compilation

- Production service `preprocess_live_f21_service4` uses `UHD_COLOR_BYPASS_ENABLE=1`,
  `UHD_PREPROCESS_ENABLE=1`, `UHD_WIDTH=3840`, `UHD_HEIGHT=2160`,
  `HE_FIXED_CONFIG_SESSION_ENABLE=1`, `STEREO_PASSTHROUGH_ENABLE=1` and
  `LANE_TAP_ENABLE=1`. UHD exercises use `i_uhd_color=1`, `i_stereo_passthrough=0`,
  and camera zero. Legal short UHD variants are 480×32 and 3840×8. The widths are
  multiples of 240 and heights multiples of eight. HD geometry in the service is 1920×1080.
- The public `preprocess_live_f21_pipeline4` boundary permits a short HD raster with width
  a positive multiple of four. Use `MAX_WIDTH=1920, MAX_HEIGHT=1080, SHARED_Y_PROFILE=1,
  HE_SOURCE_QUALIFY_ENABLE=1, HE_COLOR_PRESERVE=1, HE_FIXED_CONFIG_SESSION_ENABLE=1,
  STEREO_HE_ENABLE=1, F22_FIXED1080P_ENABLE=1, DCP_ENABLE=0, NEUTRAL_TAP_ENABLE=1`, the UHD parameters above,
  and the default camera-context parameters. Set `cfg_width[12:0]` and
  `cfg_height[12:0]` to the actual selected dimensions. This boundary substitutes
  `s_data[95:0]`, `m_data[95:0]`, `m_luma[31:0]` for the service's RGB/Y ports.
  Drive `cfg_camera_id=0`, `cfg_he_context[141:0]` as
  `{session[31:0],epoch[31:0],exposure[31:0],gain[15:0],width[12:0],height[12:0],eye,1'b0,gray,1'b0}`,
  `cfg_he_capture_sequence[31:0]` with the capture, `i_he_history_rst_n` with the
  history reset, and `s_frame_error` for a canceled source. Its `i_he_source_*` and
  `o_he_source_*` signals are the channel-zero service SOURCE interface.
- [Opaque source list](compile.json). Resolve `sources` and `includes` relative to
  the candidate. Resolve `models` and `td_work_sources` from the explicit TD root.
  Compile models into ModelSim library `ph1`, then design sources and the GSR into
  `work` with `-L ph1`, the listed includes and defines. Load both listed globals
  and the fresh bench. TD root `<TOOLS_ROOT>/TD_Release_2026.2.210.850`, ModelSim bin
  `<TOOLS_ROOT>/modelsim/win64`. No ROM initialization files are needed for this carrier.
  Apply independent wall-clock and simulation watchdogs.

## Clock, ownership and SOURCE

All handshakes sample on `posedge clk`. Assert `rst_n` and `i_processing_rst_n`
low over active edges at startup. Release them with configuration and mode stable.
Switch cold geometry only after the frame and its SOURCE retire. Keep the selected
mode, configuration, and frame identity stable from START through retirement.

| Ports | Contract |
| --- | --- |
| `i_source_frame_begin` | One-cycle pulse for the new SOURCE context before any RGB. Use it before START on a recovery frame. |
| `i_filter_start_valid/o_filter_start_ready` | START takes once before RGB. `o_filter_complete` and `o_filter_error` are foreground filter events. On the filter event, `o_filter_terminal_context[159:0]` is the START context. |
| `frame_owner[63:0]`, `frame_capture[31:0]`, `frame_context[159:0]` | Borrowed owner, sequence and context. A valid example for the context is `{16'd1,16'd0,8'd1,8'd0,8'd0,8'd0,capture,epoch,session}`. |
| `frame_cohort[208:0]` | `{session[31:0],epoch[31:0],exposure[31:0],gain[15:0],13'd1920,13'd1080,3'd0,1'b0,67'd0}` for the service. Exposure and gain can remain zero. `cfg_he_history_eligible=1` qualifies this fixed test configuration independently of known exposure. |
| `s_valid/s_ready`, `s_rgb[95:0]`, `s_sof,s_eol` | Lane zero is the least significant 24 bits, bytes B,G,R from low to high. All four lanes are active. SOF is first accepted beat. EOL is final beat of each row. Stall holds the entire offered word and its markers. |
| `s_frame_done,s_frame_error` | One-cycle positive input status after the final accepted RGB beat (same edge also legal). Error invalidates the frame and any stalled output. |
| `m_valid/m_ready`, `m_rgb[95:0]`, `m_y[31:0]`, `m_sof,m_eol` | Same order and markers as the input, with per-lane 8-bit Y in `m_y`. Scoreboard only true handshakes. Stall holds the word and markers except on error cancellation or reset. |
| `m_frame_done,m_frame_error` | Completion requires all output beats, positive input status and filter completion. The registered `m_frame_done` is a pulse. A canceled frame has an error event and cannot complete successfully. |
| `source_valid[1:0]`, `source_ready[1:0]`, `source_owner_match[1:0]`, `source_accepted[1:0]` | Channel zero offers an already-authenticated SOURCE key once the owner matches. `source_camera,source_session[31:0],source_epoch[31:0],source_capture[31:0]` remain stable through the take. `source_ok` is high for a positive event. `source_ready[0]` is capacity. `source_accepted[0]` witnesses the exact accepted event. A foreign key has no owner match or accepted event. `source_skip[0]` pulses if the start has no histogram obligation. |
| `source_cancel[1:0]`, `i_authenticated_negative`, `source_cancel_done[1:0]` | The authenticated broadcaster cancels channel zero instead of delivering a positive event for a matching bad SOURCE. The cancel pulse revokes outstanding image tokens and incomplete HE work. `source_cancel_done[0]` marks pixel and HE cancellation drain. Wait for this and quiet before starting a recovery frame. |
| `o_presented,o_frame_quiet,o_maintenance_quiet` | Presented includes owned elastic pixels even during masked output. Frame quiet follows drain of image ownership. Maintenance quiet additionally waits for HD observation and dehaze activity. |

In UHD keep `cfg_filter_dehaze,cfg_multiscale,cfg_lane,i_filter_source_error` low
for ordinary positive tests. Dehaze, neutral stats, F22 and F23 do not produce UHD
results. Tie other disabled request inputs low and unused record/read consumers ready.
The service's public `o_history_used` refers to HD dehaze. Check HE use by RGB/Y
or the direct pipeline's `o_he_history_used` and `o_he_lut_source_sequence[31:0]`.
All modes may collect qualified histogram history, including frames with HE
display disabled. A zero HE enable does not imply a skipped SOURCE obligation.
Give every positive frame its matching SOURCE when its owner matches; a skip
instead reports that metadata or histogram-bank availability prevented collection.
The direct pipeline profile above requires `NEUTRAL_TAP_ENABLE=1` for its shared
original-RGB sideband, as the production service has always selected. The first
public handoff omitted that parameter and overconstrained the skip observation;
its original failed run remains separate from the corrected-profile rerun.
When a valid frame has drained, allow a bounded idle window of up to 20,000 clocks
after its matching positive SOURCE for histogram normalization before the next SOF.
`lut_valid` and `lut_epoch` describe the active map published at a frame boundary,
not an unpublished background candidate. After the first frame they may remain
zero throughout this idle window. Send the next eligible capture after that
bounded window, then check active validity, source capture and history use when
its first output is actually offered or accepted. `o_source_decision_valid` is
a one-cycle decision event; `o_frame_history_used` is held for the selected frame.

## Pixel arithmetic

1. For each RGB pixel, `Y = (77*R + 150*G + 29*B + 128) >> 8`.
2. The GRAY option replicates Y in all channels. The Gaussian value G at a pixel
   is the sum over a 3×3 neighborhood with weights `[[1,2,1],[2,4,2],[1,2,1]]`,
   plus eight, then shifted right by four. Clamp each neighborhood coordinate
   to the real image bounds.
3. Legacy Gaussian replicates G. Schema2 Gaussian adjusts each selected RGB
   component by `round_away_from_zero((G-Y)/2)`, saturates to [0,255], and recomputes
   Y using step 1. In GRAY plus schema2 Gaussian the selected RGB is already gray.
4. HE uses the resulting Y as the sample. After a qualified matching positive
   SOURCE, for a nonconstant history of N samples, the map is zero below the
   first occupied bin and otherwise `floor(255*(CDF(Y)-CDFmin)/(N-CDFmin))`.
   `CDFmin` is the count at the first occupied bin. A single-valued history
   yields the identity map. The map applies only to a later capture of the
   same eligible eye/session/epoch/context with capture age 1–4. A first frame,
   changed context or changed geometry cannot use the prior map. For a usable
   map and HE enabled, add `clamp(map[Y]-Y,-32,32)` to each channel, saturate to
   [0,255], and recompute Y. Without usable history or with HE disabled, preserve
   the preceding stage's RGB and Y. A failed SOURCE never becomes a map.

| Configuration | `cfg_schema2` | `cfg_filter_gray` | `cfg_filter_legacy_gaussian` | `cfg_filter_color` | `cfg_enable[2:0]` |
| --- | --- | --- | --- | --- | --- |
| Scalar COLOR | 0 | 0 | 0 | 0 | 000 |
| Scalar GRAY | 0 | 1 | 0 | 0 | 001 |
| Scalar GAUSSIAN | 0 | 1 | 1 | 0 | 011 |
| Scalar HISTOGRAM | 0 | 0 | 0 | 0 | 101 |
| Schema2 SDR, any subset of 0x0D | 1 | feature bit 0 | 0 | feature bit 2 | `{feature bit 3,1'b0,feature bit 0}` |

## Focused acceptance

- At 480×32 compare the first positive frame and later HE output against independent
  pixel mathematics. Include asymmetric channels, edges and stalls. Check held
  positive SOURCE identity, a matched negative with output stalled, cancellation
  drain and a subsequent legal positive recovery. A wrong-key offer must never
  qualify history.
- At 3840×8 compare Gaussian output across group 511/512 and both raster ends.
  An impulse or nonperiodic pattern across row boundaries exposes wrap or luma/RGB
  skew. Use schema2 color Gaussian to cover its longer RGB alignment requirement.
- If doing the full UHD count check, use the public `preprocess_hist_eq4` boundary
  with `MAX_WIDTH=3840, MAX_HEIGHT=2160, EXTERNAL_LUMA_ENABLE=1,
  SOURCE_QUALIFY_ENABLE=1, FIXED_CONFIG_SESSION_ENABLE=1, HE_COLOR_PRESERVE=1,
  STEREO_HISTORY_ENABLE=1, RESET_ALL_EYES_ON_GEOMETRY_CHANGE=1`. Drive
  `width,height[12:0]`, `s_luma[31:0]`, `s_data[95:0]`, frame markers and the
  same history context, eligibility and capture fields described above. The
  matching SOURCE interface is scalar `source_valid,source_camera,source_ok,
  source_session,source_epoch,source_capture_sequence` and the `o_source_*`
  witnesses. Send 2,073,600 groups at one accepted group per cycle. Use three
  gray levels such as 8, 100 and 224 with substantially more than 524,288
  groups at level 100 and a resulting LUT correction strictly between −32 and
  +32. After positive SOURCE and normalization, sample these levels at the
  next capture with unchanged geometry. Check `statistics_error`, the source
  sequence and numerical output. A short prefix of the second frame suffices
  for this count bound after the first frame has fully terminated.

These gates check digital foreground and histogram behavior. They do not
establish the full ISP/JPEG/DDR path's sustained rate or physical timing.
