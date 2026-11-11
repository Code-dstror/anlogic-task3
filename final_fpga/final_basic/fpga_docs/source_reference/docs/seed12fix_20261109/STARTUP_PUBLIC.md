# HDR startup black-box contract

Use the public interface and the opaque compilation list below. The bench drives the I²C slave and the aligned CSI WORD boundary after PHY training. The carrier runs the real IMX415 configuration recipe, HDR packet parser, crop, two TD member FIFOs, pair gate and pair-feedback CDC through the actual RAW and member SOURCE outputs. MCLK switching, electrical training, DDR writes, CFG BAR publication and PCIe require separate verification. Treat production RTL, carrier wiring, prior tests and vendor model internals as opaque.

Instantiate `seed12_hdr_startup_carrier` once for each eye. Drive both with the same PIX clock and connect each `i_peer_stable` to the other eye's `o_hdr_stable`. The two eyes have separate CSI and I²C inputs. A single-eye check may tie `i_peer_stable` high. Use CFG period 40 ns, PIX period 10 ns and a WORD period of 9 ns with an independent phase. The geometry is four sensor pixels by one row, with full-extent crop. The carrier uses eight qualifying pairs, a 4096-PIX-clock pair deadline, four CFG clock cycles for reset/release/wake waits, and four CFG clock cycles per I²C half-period. These values shorten waits and data volume for simulation.

## Public ports and sampling

| Domain | Ports | Meaning |
|---|---|---|
| Clock/reset | `i_cfg_clk, i_word_clk, i_pixel_clk, i_reset_n` | One bit each. Assert the common active-low reset with all clocks running for at least 12 CFG edges, then release away from clock edges. Local release takes three CFG edges; the first legal START sample is the fourth CFG rising edge after external release. Wait through four CFG rising edges before offering START on a falling edge. Raw `o_start_ready` may already be high during local reset and does not waive that boundary. Reset clears the receiver cohort, member sequences and pair accounting. |
| CFG | `i_config_start, i_clock_locked, i_hdr_profile, o_start_ready, o_config_written, o_config_error, o_xclr, o_scl, io_sda, o_register_index[7:0]` | Pulse START for one CFG edge after ready with lock high. Use HDR profile 1 and hold it for the cohort. Profile 0 with no WORD traffic is legal for an optional prior SDR cohort, followed by reset and a new HDR START. `o_config_written` is a held level after the last successful write. `o_config_error` is a held error. XCLR is active low, SCL is driven by the carrier, and SDA is open-drain. Register index is zero-based. |
| WORD | `i_word_enable, i_word[31:0], i_word_valid, o_word_fifo_ready` | Assert enable only after the corresponding CFG write completes. Wait for FIFO ready and at least 16 further WORD edges before offering the first word. Hold enable for the cohort. There is no WORD backpressure input handshake. After startup, the bench uses packet gaps and offered rates that fit the bounded FIFOs. |
| PIX policy | `i_peer_stable, i_admit_enable, o_hdr_stable, i_session[31:0], i_epoch[31:0], i_time_ns[63:0], i_time_valid, i_capture_idle[1:0]` | Stable is the local eye's level after eight consecutive verified pairs reach CFG and the result returns to PIX. Both eyes must be stable before either emits admitted RAW in a two-eye configuration. Keep admit enabled during warmup. Use a constant nonzero session and target epoch per cohort, valid monotonically increasing time, and both capture-idle inputs high for this small fixture. |
| PIX RAW | `o_raw_data[79:0], o_raw_valid[1:0], o_raw_sof[1:0], o_raw_eol[1:0], o_raw_abort[1:0], o_metadata[393:0]` | LONG uses bit 0 and low slices, SHORT uses bit 1 and high slices. RAW is passive with one four-pixel beat per asserted VALID. Cropped SOF and EOL both accompany the one legal beat in this geometry. ABORT is separate. Metadata is 197 bits per member. Bits 196, 195 and 194:193 are HDR, admitted, and role (1 LONG, 2 SHORT). Bits 191:160 carry the common group. |
| PIX SOURCE | `o_source_valid[1:0], i_source_ready[1:0], o_source_ok[1:0], o_source_session[63:0], o_source_epoch[63:0], o_source_sequence[63:0], o_source_error[15:0]` | LONG uses bit 0 and low slices. Each 32-bit sequence counts its own real VC frame starts. A terminal transfers on VALID && READY and stays stable while stalled. Positive SOURCE requires the member's true FE after its verified full raster, and carries the supplied session and target epoch. A member that never emitted RAW SOF has no SOURCE terminal. |
| PIX pair/status | `o_pair_event, o_pair_ok, o_quiet, o_good_pairs[31:0], o_bad_pairs[31:0], o_not_admitted_pairs[31:0], o_identity_fault, o_pair_overflow` | Sample pair result only when the one-cycle event is high. Successful warmup groups contribute GOOD without generating products. Quiet means no retained group or held SOURCE. Identity fault and lost pair feedback are sticky until the cohort resets. |

Sample handshakes on the rising edge of the named domain. To acknowledge the configuration, use pull-up SDA and pull it low only for the ninth SCL pulse after each byte. The master sends `0x34` then the two address bytes most significant first and one value byte per transaction. Begin ACK in the low phase before the ninth rising edge and hold through that pulse. A correctly acknowledged HDR recipe writes 139 registers and ends at index 138. If running the optional SDR case, it writes 203 registers and ends at index 202.

## Legal CSI words

* Drive a burst after at least eight WORD cycles with `i_word_valid=0`. Drive one little-endian 32-bit word on each valid cycle. Byte 0 occupies bits 7:0. The boundary starts at the CSI header, with no D-PHY SoT byte. For this fixture, put FS, RAW12 and FE in separate bursts and keep header and payload words contiguous within a RAW12 burst.
* Use VC 0 for LONG and VC 1 for SHORT. A header's first byte has VC in bits 7:6 and data type in bits 5:0. The next two bytes are the little-endian frame number for FS (type 0) and FE (type 1), or the byte count 6 for RAW12 (type `0x2c`). Use nonzero frame numbers, matching FS/FE in each member. The fourth byte has its high two bits zero and the six CSI header parity bits in the low bits. For a 24-bit little-endian header, parity bits 0 through 5 are the XOR reductions over masks `f12cb7 f2555b 749a6d b8e38e df03f0 effc00` in that order.
* Each two RAW12 pixels form three bytes, the first pixel's high eight bits, the second pixel's high eight bits, and the second pixel's low nibble above the first pixel's low nibble. A four-pixel RAW12 line is six payload bytes followed by two CRC bytes. Initialize the reflected CRC-16 to `0xffff`, feed the six bytes in wire order with polynomial `0x8408` and no final XOR, then emit the CRC low byte first. The line occupies two words after its header. The expected RAW10 value is `min(1023, (RAW12 + 2) >> 2)` per pixel, with the first pixel in bits 9:0 of its member slice.
* A regular pair is complete VC0 FS/RAW12/FE followed by VC1 FS/RAW12/FE. Give complete pairs at least 2 µs between starts and keep members of a pair within the pair deadline. The first published frame of a new receiver cohort may legally be a VC1 FS/RAW12/FE from an already-running sensor cycle. With no observable preceding VC0 FS in that cohort, this frame has no pair. Subsequent complete pairs must qualify with their true independent VC sequences.

## Directed regression

Run identical stimuli and expectations with the fixed board-source gate and with the candidate. Start from freshly written HDR profiles, enable both WORD streams and open PIX admission. Give CAM1 one complete, CRC-good leading VC1 frame before the first published VC0 FS. CAM0 starts with a complete pair. Supply eight complete pairs to each eye, observing real pair feedback. CAM0 may qualify first, but neither eye can emit RAW or SOURCE before CAM1 also qualifies. The leading CAM1 frame must never count as a good pair or produce a product. On the old gate, the diagnostic failure is that CAM0 reaches stable while CAM1 never qualifies after a bounded wait and multiple pair deadlines. Preserve the actual failure log.

After both eyes qualify, send the next complete pair on each eye and check the exact RAW10 data, two real positive member SOURCE terminals per eye, roles, common group and target session/epoch. The first admitted CAM1 LONG and SHORT sequences are 9 and 10 when eight warmup pairs follow the leading SHORT. CAM0's are both 9 under the same eight-pair warmup. Briefly stall one SOURCE terminal and verify its held bundle until READY. Check the next legal pair completes and that the carrier goes quiet after all SOURCEs retire. Account for every offered qualifying group and product so an erroneous early frame cannot satisfy the positive check.

A separate normal LONG-first run or one healthy LONG-first eye in the same two-eye run supplies a control. Use a simulation watchdog of at most 8 ms and a wall-clock watchdog of at most 90 s per run. Where the negative control reaches the expected observed stall, report it as a failed liveness expectation with the observed public outputs, and preserve it before running the candidate. Do not change legal stimuli or the success expectation between baseline and candidate.

## Opaque compilation

From `refactor/camera_raw_r2/src_fpga`, compile the following into `work` along with the new independent testbench using ModelSim `vlog -sv`. Include `rtl/include/04_include` and `ip/camera_packet_fifo_147x512/RTL/include`.

```text
simulation/blackbox_hdr_startup_20261109/seed12_hdr_startup_carrier.v
rtl/reset_release_sync.v
rtl/imx415_sensor_config.v
rtl/imx415_sensor_recipe.v
rtl/imx415_mode_table.v
rtl/imx415_hdr2_recipe_rom.v
rtl/camera_i2c_write.v
rtl/real_hdr_event_cdc.v
rtl/hdr_csi_boundary_adapter.v
rtl/real_hdr_csi_word_core.v
rtl/real_hdr_csi_dual_word_rx.v
rtl/real_hdr_member_crop10.v
rtl/raw_capture_fifo_eram_safe.v
rtl/real_hdr_csi_capture_stream.v
rtl/real_hdr_pair_cycle_gate.v
ip/camera_packet_fifo_147x512/camera_packet_fifo_147x512.v
ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v
ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v
ip/vendor/anlogic_camera/sensor/ui_imx415_reg.v
```

For the baseline substitute `../tmp/seed12fix_20261109/baseline/real_hdr_pair_cycle_gate.v` for the gate path. The Git blob at board commit `4a08ae35391e7b7ea6767260d7d1b4b182ef4bb9` is `8b8375b4286e685a77e2b14275ae86b892794be8`. The copied file SHA-256 is `9a8aaad1b7e59827c9afb0ddfd539bcbc3f78ca39002a1a0e2861f4c789fb2ae`.

Use ModelSim from `D:/App/modelsim/win64` and the explicit TD root `D:/App/TD_Release_2026.2.210.850`. Compile the following vendor models from that root's `sim_release` into library `ph1` and run with `-L ph1` and sibling top `ph1.glbl`. Instantiate `PH1_PHY_GSR` as `PH1_PHY_GSR` in the independent bench when required by the global reset binding.

```text
common/al_phy_glbl.v
ph1/ph1_logic_eram.v
ph1/ph1_logic_fifo.v
ph1/ph1_logic_ramfifo.v
ph1/ph1_phy_eram.v
ph1/ph1_phy_fifoctrl.v
ph1/ph1_phy_gsr.v
```

Keep separate run directories and libraries under `refactor/camera_raw_r2/tmp/seed12fix_20261109/`. Record source, testbench and model SHA-256, tool version, commands and observed terminal results. Read the public interface and compile/hash the listed opaque inputs.
