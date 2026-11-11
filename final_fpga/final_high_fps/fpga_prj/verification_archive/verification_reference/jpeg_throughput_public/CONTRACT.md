# R3 JPEG independent short verification

Use this contract, the three public port declarations, the compiler manifest and the linked public references. The test author may hash and compile the opaque inputs. Use newly authored stimulus and scoreboards based on the public ports. The production RTL, candidate RTL, vendor model bodies, experiments, old tests and internal hierarchy are outside the author context. Return compile diagnostics to the maintainer.

[R1 JPEG public contract](../../../camera_rate_r1/verification_reference/jpeg_rate_public/CONTRACT.md) · [R1 negative STATUS contract](../../../camera_rate_r1/verification_reference/jpeg_rate_public/FAILURE_CONTRACT.md) · [R2 dual geometry contract](../../../camera_rate_r2/docs/ISP_JPEG_GEOMETRY_CONTRACT.md) · [Independent JPEG mathematics](../../../../tools/jpeg_ref/jpeg_ref.py)

## Clock and legal profiles

Use one PIX clock with an 8 ns period. Hold active-low reset across at least ten rising edges at startup and release away from the sampling edge. Global reset may discard unfinished work. The directed negative cases below have no simultaneous reset. All ready/valid transfers occur on a rising edge with both signals high. A stalled producer holds all valid fields stable. Payload and sideband values have meaning when valid.

| DUT | Legal short profile | Scope |
| --- | --- | --- |
| [`jpeg_mcu_422`](jpeg_mcu_422_ports.vh) | `MAX_WIDTH=480`, `MAX_HEIGHT=32`, `ROW_STREAM_ENABLE=1`, `DUAL_GEOMETRY_ENABLE=1`, `FIXED_GEOMETRY_ENABLE=0`. Low profile 240×16 and high 480×32. Set `i_block_ready=0`. | Real row stream and reuse of the first eight-line group buffer |
| [`jpeg_entropy`](jpeg_entropy_ports.vh) | `STREAM_INPUT_ENABLE=1`, `RESTART_ENABLE=1`, `COEFF_BANKED_STORAGE_ENABLE=1`, `ROM_INIT_ROOT="./rom_init"`, `ROM_INIT_SUFFIX=".mif.dath"`. Set `i_block_valid=0` and all legacy block payload/metadata inputs to zero. Keep `i_abort=0` for the directed cases. | Direct signed quantized coefficients for entropy arithmetic boundaries |
| [`jpeg_encoder_top`](jpeg_encoder_top_ports.vh) | `MAX_WIDTH=3840`, `MAX_HEIGHT=32`, `DUAL_GEOMETRY_ENABLE=1`, `FIXED_GEOMETRY_ENABLE=0`, `SHARED_STREAM_ENABLE=1`, `TINY_DISTRIBUTED_RAM_ENABLE=0`, `COEFF_BANKED_STORAGE_ENABLE=1`, `MCU_ROW_STREAM_ENABLE=1`, `ROM_INIT_ROOT="./rom_init"`, `ROM_INIT_SUFFIX=".mif.dath"`. Low strip 1920×16 and high strip 3840×32. | True width switches through RGB, coefficient generation, JPEG AXIS and RESULT |

In dual geometry, the two legal dimensions are the maximum pair and the pair at half each dimension. These short profiles exercise that contract. The production instance uses 1920×1080 and 3840×2160 with the same feature enables. Switch geometry only between transactions, after the preceding terminal has been accepted and the DUT is idle or ready for a new SOF.

## MCU row stream

`i_y[31:0]` supplies four consecutive unsigned luma samples in low-byte-first order. `i_cb[15:0]` and `i_cr[15:0]` supply the two corresponding horizontal pair samples, earliest in the low byte. The input SOF is on the first accepted group and EOL on each row's last group. Hold width, height and capture ID through the frame. Use sample patterns distinguishable by coordinate, row and component.

For each raster-order 16×8 MCU, the expected block order is Y0, Y1, Cb, Cr with indices 0, 1, 2, 3 and components 0, 0, 1, 2. Each block has rows 0 through 7 in order. At coordinate `(mx,my)` and row `r`, each of the eight low-byte-first samples belongs to input row `8*my+r`. The source column starts at `16*mx` for Y0, `16*mx+8` for Y1 and `8*mx` in the corresponding half-width chroma plane for Cb/Cr. `o_frame_last` identifies the final block and is valid on all its row offers. Frame retirement requires acceptance of row 7 of that block. At every row transfer check row index, capture ID, block/component, both MCU coordinates, last flag and all sample bytes. For legal frames `o_error_valid` stays low.

Use finite stalls on row 7 before a block transition and on the last row of an eight-line group. With the final row of group zero held and the second group filled, offer the next group's input and verify it cannot be accepted ahead of the group-zero terminal row handshake. Resume the sink and account for the next group and the entire frame. This high profile has four groups so the test observes actual buffer reuse. Also cover the boundary from the final chroma block of one MCU to the next MCU's Y0. In ready intervals record consecutive row7→row0 transfer gaps. A narrower gap is the optimization's observable effect. The correctness scoreboard must tolerate latency variation and a finite group-boundary handoff.

## Direct entropy

Input is one HEADER then eight DATA transfers per block. `i_token_keep=16'hffff` throughout. Set `i_token_user=2'd1` and `i_token_last=0` on the HEADER. Set `i_token_user=0` on DATA, with `i_token_last=1` on its eighth transfer only. Each DATA beat carries eight signed 16-bit coefficients in JPEG zigzag order, earliest at bits [15:0]. The first coefficient is DC. Present blocks in the same MCU and component order as above.

| HEADER bits | Field |
| --- | --- |
| [31:0] | Capture ID |
| [63:32] | Mode epoch |
| [95:64] | Session ID |
| [104:96] | MCU x |
| [113:105] | MCU y |
| [115:114] | Component, Y=0, Cb=1, Cr=2 |
| [117:116] | Block index 0–3 |
| [118] | Last block of frame, one only for final Cr |
| [125:119] | Frozen quality 1–100 |
| [126] | Camera ID |
| [127] | Reserved zero |

Start the first MCU at (0,0). Freeze the frame identity, quality and `i_restart_mcus` from its first HEADER through completion. This interface supplies prequantized values. Their signed numerical limits are independent of the small raster's ability to produce such values from pixels.

Use standard baseline Huffman DC and AC tables. Compute one independent DC predictor per component, including both Y blocks in the Y predictor. Initialize all predictors to zero at a new frame and after an actual restart marker. The DC category is the bit length of the absolute difference, with category zero for zero. Legal differences include ±2047. A difference of magnitude 2048 or more is unsupported. AC coefficients have magnitude up to 1023. Encode negative amplitude `v` at size `s` as `(2**s - 1) + v`. Use EOB for trailing zeros and ZRL for each sixteen-zero run before a following nonzero AC.

Emit MSB first. Entropy bytes equal to FF are followed by 00. Restart interval zero disables markers. For a nonzero interval, fill with one bits to the next byte boundary and insert the literal two-byte RST marker after each completed interval of MCUs before the final MCU of the frame. Markers start at FF D0 and increment modulo eight. Marker FF is unstuffed. The final scan also pads with ones and stuffs any resulting FF. This output contains entropy and optional RST markers. The file formatter supplies the JPEG header and EOI in the encoder test.

`o_byte_last` accompanies the last byte of the completed scan, including any final stuffing byte. It is held with the offered byte under stall. Successful `o_entropy_done` is a single pulse after that byte is accepted. `o_error_valid` is a synchronous error pulse with matching capture ID. A directed out-of-range DC difference reports `o_error_code=2` and no successful done for that frame. Any byte already offered under stall remains stable until accepted. The unsuccessful prefix is discardable, and the frame need not supply LAST. After drain and `o_idle`, a new valid frame must complete without reset.

Use an independently computed byte reference for at least one legal sequence with both signs of large DC differences, a nonzero restart interval, and at least one genuine FF00. Dense legal AC or isolated long zero runs can provide distinct bit alignment. Include finite ready stalls during a visible byte offer, including near a scan or restart boundary. Also test an unsupported DC difference then a legal fresh frame. Score bytes, actual terminal events and stable offers. The independent reference can use the standard tables, amplitude helpers and bit writer in the linked math reference. It must compute predictors and restart boundaries from supplied vectors.

## Complete JPEG and source status

The encoder accepts four `{R,G,B}` byte triples per input group with earliest pixel in bits [23:0]. `i_luma` supplies corresponding full-range Y values, earliest in bits [7:0]. Freeze capture ID, camera/session/epoch, width/height, restart interval and quality through the frame. Use Q75 for comparisons. Use the independent JPEG BT.601 chroma math, rounding and clamping before averaging each horizontal pair with `(a+b+1)>>1`. For exact numerical checks the Y plane is the supplied Y. The reference's default RGB-derived Y is appropriate only if it is also the supplied value. A grayscale reference fixture has neutral chroma and allows a simple exact pixel-to-JPEG check with the Q75 reference. JPEG 4:2:2 order and restart rules are as above. DRI carries the configured interval when nonzero. Read actual SOF dimensions and component sampling factors from the file.

The status interface represents the upstream SOURCE terminal at this leaf boundary. Supply a matching positive or negative status after the last accepted RGB group, with its fields held until accepted. EOL and accepted status are separate. AXIS is 128 bits, byte 0 in bits [7:0], and `tkeep[n]` qualifies byte n. Count only actual accepted valid bytes. Nonterminal beats of a successful file have full KEEP, and the final beat has a contiguous nonzero low-byte KEEP. Stalled AXIS holds DATA/KEEP/LAST. The successful RESULT is a held offer with `o_result_ok=1`, `o_error_code=0`, matching ID, frozen quality/epoch and exact byte count. It requires both positive SOURCE status and acceptance of the AXIS LAST. Hold a RESULT under finite backpressure and check it through acceptance.

A matching negative status with otherwise legal pixels reports STATUS (`o_error_code=1`), `o_result_ok=0`, matching ID, frozen quality/epoch and zero length. A previously offered AXIS beat remains committed through acceptance. Accepted prefix bytes belong to the failed frame, regardless of whether the encoder had already offered a tail. Failure RESULT waits for outstanding output to drain, and failed-frame output does not arrive after RESULT acceptance. There is no requirement for EOI or LAST on a failed prefix. After accepting RESULT and observing idle, a fresh legal frame must complete without reset. These are the existing [R1 STATUS semantics](../../../camera_rate_r1/verification_reference/jpeg_rate_public/FAILURE_CONTRACT.md).

Use one short sequence covering low success, high success, a low failure and low recovery. Include a deterministic textured or dense frame as well as a simple known fixture. Exercise a nonzero restart interval and normal interval zero. For the failure, once the last RGB group has been accepted, arrange a finite AXIS stall with a visible valid offer and deliver the matching negative status while it is held. For success, delay positive status until after LAST in one case and hold LAST after positive status in another. Require each successful stream to be a complete externally decoded JPEG with actual dimensions and expected fixture content. Use the decoder's full pixel load, not just a header probe. Compare all accepted bytes and the per-beat KEEP/LAST sequence of each successful fixture across the four variants with identical inputs. Absolute offer cycles and failed prefix length can vary. Byte equivalence augments the independent content oracle and positive/negative transaction checks.

## Opaque compilation

[compile.json](compile.json) names all inputs and SHA-256 digests. It selects exactly one source per module for each of `baseline`, `dc39`, `mcu_prefetch` and `combined`. [compile_inputs.py](compile_inputs.py) checks the digests, converts all ten addressed MIFs to the sealed LF-delimited `./rom_init/*.mif.dath` images, creates separate ModelSim libraries and compiles the inputs. It records actual paths, commands and digests in `compile_inputs.json`. The runner contains no test logic. Use a fresh run directory for each variant and each retry.

```powershell
$jpegPython = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
$jpegPublic = 'refactor/camera_rate_r3/verification_reference/jpeg_throughput_public'
$jpegRun = 'refactor/camera_rate_r3/tmp/jpeg_throughput_validation/example-baseline'
& $jpegPython -X utf8 -B "$jpegPublic/compile_inputs.py" --variant baseline --run-dir $jpegRun --td-root '<TOOLS_ROOT>/TD_Release_2026.2.210.850' --modelsim-bin '<TOOLS_ROOT>/modelsim/win64'
```

With native Windows execution, use the run directory as cwd for subsequent commands. Production and model `.v` compile in Verilog mode. The two official FDCT wrapper files compile together with `-mfcu`. Compile the new bench separately with `vlog -sv -work work -L ph1 <bench.sv>`. Use `vsim -c -t 1ps -L ph1 work.<bench> work.PH1_PHY_GSR ph1.glbl` with the bench's bounded batch commands. Check errors and terminal markers separately. Any failure at the opaque compiler boundary is for the maintainer. Report the log path and scope without opening RTL or vendor internals.

## Evidence boundaries

The row and entropy leaf runs need only the two distinct source sets relevant to that leaf. The end-to-end JPEG test uses all four sets and the same stimulus. Record actual input/output handshake cycles, SRC status and RESULT acceptance, IDs, JPEG SHA-256 and length, first/tail timing, stalls, observed FF00 and RST counts, and phase-specific row or frame intervals. Use a finite simulation-cycle watchdog and at most 300 s wall clock per simulation. Preserve original failure artifacts and tool, manifest, input and testbench hashes. These are short public-interface tests through actual JPEG logic. Board cadence, sustained full-frame rate and DDR B/slot retirement remain separate evidence.
