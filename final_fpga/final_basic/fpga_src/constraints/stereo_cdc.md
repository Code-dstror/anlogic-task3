# Second-camera pin and CDC additions

This candidate adds nine camera1 pin assignments in `anlogic2026.adc` and the
flat native constraint file `stereo_cdc.sdc`. The inherited
`real_hdr_clocks.sdc` and `stream_cdc.sdc` are unchanged. The November camera_shared_r1 migration regenerated four private business FIFO IPs with TD 2026.2. Its generated instances and dedicated short-test results are in ../../docs/FIFO_MIGRATION.md. Older board and timing figures below belong to their original source.

**Current status: source-level review only. Native SDC mapped-object matching,
clock derivation/coverage, synthesis, P&R and STA for these new constraints are
NOT_RUN by this change.** A successful future source registration alone will
not prove that a query matched or that two receivers fit BANK13 local clocks.

## Project registration and ordering

Register `fpga_prj/constraints/stereo_cdc.sdc` as an ordinary project SDC in the
same constraint set. The recommended explicit order is:

1. `real_hdr_clocks.sdc`: existing board, first camera and derived clocks.
2. `stereo_cdc.sdc`: camera1 450 MHz worst-case input clock, an additional `derive_clocks`
   pass for the newly clocked LCLK/SCLK network, and only new CDC endpoints.
3. `stream_cdc.sdc`: unchanged inherited source-level constraints.

Keep the existing IP XML/IPC constraint loading, including the official
`csi_event_fifo_47x8192.tcl`. Both receiver instances use the same registered
IP bytes; do not duplicate generated IP source registration. User constraints
must apply after IP registration/clock derivation. A future native read must
check the additional derive pass, the expected camera1 clock periods and the
first-stage object queries rather than hiding missing objects with `-nowarn`.

The file contains only flat `create_clock`, `derive_clocks`, `set_max_delay`,
`set_false_path -hold`, `set_path_skew` and explicit reset-boundary commands.
It has no Tcl procedure, loop, runtime audit or broad asynchronous clock group.
The scalar/held-bundle budgets follow the existing 7.0/7.5 ns convention, with
the actual source/destination endpoints listed directly.

## Camera1 board assignments

| Port | FPGA P/control pin | Differential N pin |
|---|---|---|
| mipi1_clk_hs_rx_p | E16 | F16 |
| mipi1_data_hs_p[0] | F18 | G18 |
| mipi1_data_hs_p[1] | K16 | K17 |
| mipi1_data_hs_p[2] | D17 | E17 |
| mipi1_data_hs_p[3] | J17 | J18 |
| cam1_scl | N10 | — |
| cam1_sda | N11 | — |
| cam1_mclk | J13 | — |
| cam1_xclr | K13 | — |

TD assigns the negative member from the LVDS18 positive pin; no extra negative
port is created. HS data retains INDEL=20, matching the supplied conversion
example and the existing controlled PHY use. Control pins use LVCMOS18 with
the example's pull/drive settings. These are source constraints, not an eye
margin or soldering acceptance result.

Evidence already visually checked during the hardware review:

- `references/DSI2CIS/AFC03_IMX415_MIPI_dsi/uisrc/04_pin/fpga_pin.adc`, SHA256
  `c69f208ba42a3476465d95a4b08450f748ef1e23cd510d76aaa32f2366b6f189`.
- AFH03 carrier schematic `MLK-AFH03-20251112.pdf`, physical pp.4 and 29,
  SHA256 `2431ff026ea3546b185672d9df9cd7bb163108713742983cbfb2c208737b8d4a`.
  Its page date is 2025-12-02. Page4 confirms the R671/R672 switch for LA32_P/N11
  (camera1 SDA); page29 confirms FMC-to-FPGA nets.
- AFC03 core schematic `MLK-AFC03-20251112（仅FPGA部分及板级连接器不包含RK部分）.pdf`,
  physical p.5, SHA256
  `fb39e4498fafecd6b4a47f72259854720593a4374f8f82272b615150926f53d3`.
  This verifies the P/N pairs and BANK13 membership. SCL/SDA are BANK12.

Both physical eyes share the existing SDR and DOL2 sensor recipes. Each
HS input uses the fastest HDR period **2.222222 ns**, with a corresponding
HDR WORD period **8.888888 ns**. The SDR WORD period remains **11.111112 ns**.
Both receiver HS interfaces occupy BANK13; local IOCLK/LCLK/SCLK reachability
and placement must be checked in physical implementation before board claims.

## Constraint-to-structure mapping

| New crossing | Declared endpoints and bound | Structural reason / remaining check |
|---|---|---|
| SENSOR→PIX/REF boot state | `u_camera1/{done_sync,error_sync,enable_sync}[0]`, max 7.5 ns | Two-stage level synchronization; only FIRST is exceptional. SENSOR reset/configuration logic and SECOND stay timed. |
| REF→WORD control | receiver `word_enable_sync[0]`, PHY `r_align_enable_sync[0]`, watchdog `r_req_meta`, max 7.5 ns | Independent first-stage synchronization of enable and request toggle. |
| WORD→PIX/REF status | stream `identity_fault_pixel[0]`, receiver `phy_ready_sync[0]`, frontend `delay_sync[0]`, watchdog `r_ack_meta`, max 7.5 ns | First-stage status/ACK only; no exception on post-sync consumers or ordinary RAW pixels. |
| WORD↔PIX official event FIFO | `primary_addr_gray_reg_{w,r}[*]`→`sync_r1_{w,r}[*]` under the camera1 SDR FIFO instance, max and path-skew 7.5 ns | Public FIFO3.0 TCL supplies the leaf names. The bound is below both the 8 ns PIX and 8.889 ns fastest WORD periods. Actual mapped names/counts and Gray publication must still be checked. |
| USER→PIX/DFI mode command | exact `request_toggle`, `release_toggle`, `quarantined`→corresponding `[0]` synchronizer bits, max 7 ns | Each domain waits a full two-stage request propagation; common release waits both returning ACKs. No second-stage or mode consumer exemption. |
| PIX/DFI→USER acknowledgement | exact `pixel_ack`/`dfi_ack`→`pixel_ack_sync[0]`/`dfi_ack_sync[0]`, max 7 ns | ACK publishers remain normally timed in their own domain; only asynchronous FIRST captures use the bound. |
| USER held mode bit→PIX/DFI local mode | exact `held_mode`→`o_pixel_mode`/`o_dfi_mode`, max 7 ns | Bundled one-bit payload is held from before request propagation through both ACKs. Capture occurs only after synchronized request and local quiet. This is a held-mailbox exception, not an unconstrained live mode signal. |
| PIX reset request→camera SENSOR/REF releases | `u_camera1/u_sensor_reset` and `u_ref_reset` `release_pipe[*]` | Top-level camera1 request is PIX-owned mode/pause/reset. Local PIX release is kept normally timed. |
| REF/WORD/PIX requests→receiver local releases | Explicit cohort, identity, watchdog, FIFO write/read release chains listed in SDC | Only foreign-origin request paths into those exact chains are cut. Local release-to-functional state and all related WORD/x2/x4 PHY recovery/removal paths stay timed. |
| USER/PIX/DFI common reset→cold mailbox releases | Each of the three explicit `u_*_release/release_pipe[*]` banks receives exceptions only from the other two clocks | Cohort AND is an asynchronous request. Every mailbox domain releases through its own three-stage chain. Same-domain shift/data paths remain checked. |

The Gray FIFO constraints use public wrapper hierarchy
`u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst`.
They explicitly tighten the new instance; they do not edit the vendor TCL or
add a wildcard matching all design FIFOs. Query-match and naming changes after
mapping must be resolved from the actual netlist, not guessed or suppressed.

`u_stereo_capture0` and `u_stereo_capture1` are wholly PIX-domain modules and
receive no CDC exceptions. Their configuration/time snapshot and SOURCE
outputs remain ordinary timed paths. The unconnected eye-scan debug output
registers are expected to prune in the current top, so no broad debug-bundle
exception is installed. If those outputs become live, their frozen-status
bundle needs its own explicit transfer budget and verification.

No board input/output delay has been invented: external D-PHY timing, local
sampling phase, MCLK/control board delay and eye qualification remain physical
validation work. Missing coverage must be reported when native timing reports
become available, not relabeled PASS because the clock has a period.
