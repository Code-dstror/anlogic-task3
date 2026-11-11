# HDR stop and capture configuration drain

`hdr_cfg_drain_carrier` connects one real HDR LONG/SHORT gate to the real paired capture configuration owner and its TD control FIFOs. It uses the production gate profile `TIMEOUT_CYCLES=12500000, EXTERNAL_PHASE_ENABLE=1`, with the other parameters at their defaults, and owner profile `TRUSTED_INPUT=1`. The maintainer owns the wiring and the independent bench supplies traffic and expectations. Its ingress, writer and sensor-clock handoff are external models.

## Ports and clocking

| Domain | Ports | Contract |
|---|---|---|
| Clocks/reset | `i_pixel_clk`, `i_pixel_rst_n`, `i_dfi_clk`, `i_dfi_rst_n`, `i_hdr_rst_n` | One bit each. PIX and DFI use independent, running clocks. A low PIX or DFI reset asserts the capture cohort reset. Wait for `o_cfg_reset_done` after releasing both. `i_hdr_rst_n` controls only the HDR source branch. Release it on a safe PIX boundary, with admission closed. |
| PIX HDR policy | `i_admit_enable`, `i_stable`, `i_hdr_fault`, `i_timeout_phase[31:0]`, `i_time[63:0]`, `i_time_valid` | One-bit policy levels except phase and time. The phase advances modulo 12500000 on PIX edges. Time is a valid nanosecond sample. Keep stable high and fault low for the normal test. |
| PIX HDR input | `s_long_data[146:0]`, `s_short_data[146:0]`, `s_long_valid`, `s_short_valid`, `s_long_ready`, `s_short_ready` | Each lane transfers on its own VALID && READY. Hold an offered token stable under stall. |
| PIX RAW output | `o_raw_data[79:0]`, `o_raw_valid[1:0]`, `o_raw_sof[1:0]`, `o_raw_eol[1:0]`, `o_raw_abort[1:0]` | Bit 0 and the low 40-bit slice are LONG. Bit 1 and the high slice are SHORT. Each VALID is one passive RAW4 beat. SOF/EOL describe that beat. ABORT is a separate negative event. |
| PIX SOURCE | `o_source_valid[1:0]`, `i_source_ready[1:0]`, `o_source_ok[1:0]`, `o_source_identity[191:0]`, `o_source_error[15:0]` | Low identity/error slices belong to LONG. Each 96-bit identity is `{session, epoch, capture_sequence}`. Status and payload stay stable while VALID and !READY. A terminal is taken only on VALID && READY. |
| PIX drain inputs | `i_ingress_idle[1:0]`, `i_enqueue_fire[1:0]` | LONG in bit 0. Idle also grants that member's capacity for a new RAW capture: it must be high before its new FS, and may become low only as its actual RAW SOF obtains ownership. A low idle before FS legitimately stalls admission. Each enqueue pulse adds one accepted transport item for that member. Hold both ingress idle levels high with no enqueues once the old source is drained. |
| DFI drain inputs | `i_consume_fire[1:0]`, `i_write_quiet` | LONG in bit 0. Each consume pulse removes one actually enqueued item. Never consume ahead of enqueue. Write quiet asserts only after the modeled accepted writes and their responses have drained. |
| PIX CONFIG input | `s_cfg_data[1183:0]`, `s_cfg_valid`, `s_cfg_ready` | Upstream-validated immutable tuple. Submit only one CONFIG at a time. Keep payload stable through the request handshake. |
| PIX CONFIG reply | `m_cfg_ack_data[1183:0]`, `m_cfg_ack_valid`, `m_cfg_ack_ok`, `m_cfg_ack_ready` | Positive ACK echoes the exact request. It stays valid and stable under bounded response backpressure. On its first valid cycle, `o_active_config` already reflects the accepted tuple. This is the capture-owner application ACK. |
| PIX status | `o_hdr_quiet`, `o_active_config[1183:0]`, `o_initialized`, `o_cfg_busy`, `o_cfg_reset_done`, `o_cfg_fault`, `o_source_drain_fault[1:0]` | Status levels. The gate quiet level covers actual HDR contexts and outstanding SOURCE terminals. CONFIG also requires the ingress, transport and writer drain. |
| DFI status | `o_dfi_drain_fault[1:0]` | Sticky per-member fault levels. Observe on DFI edges. |

Sample handshakes on the rising edge of the named domain. Within the HDR branch, the source identity comes from `o_active_config`. Close admission before issuing a new CONFIG, preserve it closed while the ACK is outstanding, and reopen only in a valid sensor profile after ACK retirement.

## Legal tokens and tuples

HDR input token fields are RAW10 samples `[39:0]` with pixel 0 in `[9:0]`, cropped SOF `[40]`, cropped EOL `[41]`, abort `[42]`, event code `[46:43]`, nonzero group ID `[78:47]`, member sequence `[110:79]`, trusted member identity `[111]`, and trusted common-cycle identity `[112]`. Other bits may be zero. Code 7 is trusted FS, code 0 is cropped RAW, and code 6 is verified true FE. A member's FS, data and FE use its own constant sequence and the pair's common group ID. The two lanes may be offset. Keep input order on each lane and group IDs within the same forward half-range. The short fixture can provide a single RAW4 beat with SOF and EOL both high per member. True FE is a later token, standing for upstream geometry/CRC verification. A previously started member must still produce its old-identity terminal if admission closes before FE.

The CFG tuple low bits are request `[31:0]`, session `[63:32]`, base mode `[65:64]`, quality `[72:66]`, adaptive flag `[73]`, minimum quality `[80:74]`, frame budget `[105:81]`, restart MCUs `[121:106]` and epoch `[159:128]`. Use base color mode 0, quality 75, minimum 1, other scalar bits zero. BOOT has nonzero session, request and epoch zero, and extension zero. Every subsequent request has a new nonzero request ID, the same session and the next epoch. Let `ext=tuple[1183:160]` and set unlisted bits zero.

| Tuple | Extension |
|---|---|
| HDR | `ext[15:0]=16'h0202`, ratio `ext[66:64]=4`, LONG black `ext[76:67]=50`, SHORT black `ext[86:77]=50`, qualification `ext[108:105]=15`, delta ns `ext[191:128]=1000000`, wait ns `ext[223:192]=50000000`, age ns `ext[255:224]=100000000` |
| SDR dehaze | `ext[15:0]=16'h0802` |

## Directed risk

1. Complete BOOT then HDR through positive CONFIG ACK retirement. Open admission and submit a legal old-epoch pair. Close admission after both cropped SOFs, send each true FE and briefly stall one SOURCE terminal. Check RAW and terminal identity and status, and keep the CONFIG ACK absent while that old SOURCE remains held. Give each member a real modeled enqueue obligation and drain both before reporting write quiet.
2. Request SDR dehaze while admission is closed. Once the old group and held SOURCE clear and the modeled ingresses are idle, continue supplying newer ordered FS/RAW/FE tokens for unadmitted groups while CONFIG is busy. Keep a bounded DFI write debt across multiple such groups, then let it finish. These rejected groups must create no RAW or SOURCE and must leave `o_hdr_quiet` high. Wait for exact positive dehaze ACK with no drain fault. Briefly stall the ACK, checking full tuple stability, then retire it. The same scenario can run with the board-source gate as a negative control.
3. After dehaze ACK retirement, assert the HDR branch reset as the sensor clock/profile changes. With admission still closed, send the next HDR tuple through the same owner and both FIFOs. After successful ACK retirement, release the branch reset and submit a new legal pair. Its RAW and both SOURCE terminals must complete with the new HDR epoch and the new per-lane sequences.

The targeted history is an HDR exit where new admission was paused and old data owners looked idle, yet the capture epoch did not advance while old sensor traffic was still arriving. This carrier verifies a bounded logical drain and re-entry. Full sensor timing, DDR and host APPLIED are outside this carrier's scope.

## Opaque compilation

Paths are relative to `refactor/camera_raw_r2/src_fpga`. Include `rtl/include/00_rtl`, `rtl/include/03_mono_config_v2_20261015`, `rtl/include/04_include` and `ip/camera_control_fifo_40x512/RTL/include`. Compile these Verilog files in `work` with `vlog -sv`.

```text
simulation/blackbox_cfg_transition_20261109/hdr_cfg_drain_carrier.v
rtl/real_hdr_pair_cycle_gate.v
rtl/physical_pair_config_owner.v
rtl/frame_config_preset_owner.v
rtl/paired_raw_capture_drain_cdc.v
rtl/reset_release_sync.v
rtl/control_message_fifo_ip.v
rtl/control_fifo_40x512.v
ip/camera_control_fifo_40x512/camera_control_fifo_40x512.v
ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v
ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v
```

Use ModelSim from `D:/App/modelsim/win64` and pass TD root `D:/App/TD_Release_2026.2.210.850` explicitly. Build the following paths from that root's `sim_release` into library `ph1`. Simulate with `-L ph1` and the `ph1.glbl` sibling top. Instantiate `PH1_PHY_GSR` as `PH1_PHY_GSR` in the bench when required by the model's global-reset reference.

```text
common/al_phy_glbl.v
ph1/ph1_logic_eram.v
ph1/ph1_logic_fifo.v
ph1/ph1_logic_ramfifo.v
ph1/ph1_phy_eram.v
ph1/ph1_phy_fifoctrl.v
ph1/ph1_phy_gsr.v
```

For the board-source control, substitute `../tmp/fieldfix_20261109/baseline/real_hdr_pair_cycle_gate.v` for the single gate source. Its working-copy SHA-256 is `68e0b67235a1d0b765e31f4adc48a3765980a627ce84f69f529d523b460c2b59`. Give each run its own output directory and libraries, 100 µs simulation watchdog and a bounded wall clock. Record tool version, exact command, source and TB hashes and terminal outcome. Bench authors may compile and hash the source paths without reading their contents.
