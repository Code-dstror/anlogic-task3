# CFG1 quality control public verification contract

Use the public module `quality_config_carrier` with its default `QUALITY_CONTROL_ENABLE=1`. Use `QUALITY_CONTROL_ENABLE=0` for the feature-disabled comparison, or compile the fixed parent with `-Parent`. Exercise asynchronous USER, PIX and DFI clocks. Declare and connect the testbench by the public ports below. Invoke the compiler without opening production RTL, the carrier implementation, the vendor models or prior tests.

```powershell
$project = '<PROJECT_ROOT>/refactor/camera_fusion_r1'
& "$project/verification_reference/compile_quality_config.ps1" `
  -ModelSimBin '<TOOLS_ROOT>/modelsim/win64' `
  -TdRoot '<TOOLS_ROOT>/TD_Release_2026.2.210.850' `
  -WorkDir "$project/tmp/quality_cfg_independent_01"
```

Run the testbench alongside `work.glbl` and `work.PH1_PHY_GSR` for the official TD models.
The opaque compile/include input list and source hashes are in `QUALITY_CONFIG_INPUTS.json`.

## Public ports

```verilog
module quality_config_carrier #(
    parameter integer QUALITY_CONTROL_ENABLE=1
) (
    input wire user_clk,user_rst_n,pixel_clk,pixel_rst_n,dfi_clk,dfi_rst_n,
    input wire i_stereo_mode,i_uhd_mode,
    input wire write_valid,input wire [11:0] write_offset,
    input wire [31:0] write_data,input wire [3:0] write_strobes,
    output wire [1:0] write_response,
    input wire read_valid,input wire [11:0] read_offset,
    output wire read_response_valid,output wire [31:0] read_data,
    output wire [1:0] read_response,
    input wire [1:0] i_source_idle,i_capture_enqueue,i_capture_consume,
    input wire i_write_quiet,i_pipeline_idle,i_frame_accept,
    input wire [31:0] i_frame_sequence,
    output wire o_source_ready,o_pause_new_frames,
    output wire o_job_config_valid,input wire i_job_config_ready,
    input wire i_job_config_done,i_job_config_error,i_job_config_busy,
    output wire [1183:0] o_job_config,o_dfi_active,o_pixel_active,o_service_active,
    input wire i_release_whole_ack,
    output wire o_whole_ack_valid,
    input wire i_inject_ack_valid,i_inject_ack_ok,
    input wire [1183:0] i_inject_ack_data,
    output wire o_inject_ack_ready,
    output wire o_cfg_fault,output wire [31:0] o_stale_ack_count,
    output wire o_user_initialized,o_pixel_initialized
);
```

- Active-low resets are independently driven and initially asserted. Use rising-edge handshakes. `i_stereo_mode` and `i_uhd_mode` are static for each BOOT. Drive only one high, or both low for HD mono. BOOT automatically installs the neutral extension, base COLOR/Q75 and epoch 0 with a nonzero session. Drive idle source endpoints and complete the initial DFI CONFIG. BOOT needs no frame pulse.
- The USER BAR takes one request pulse per access. Use all four byte strobes for scalar writes and wait for `read_response_valid` before issuing a later read. A successful response is `0`. Reserve several USER cycles between writes. Read the CFG status and response sequence to distinguish pending, PREPARED and APPLIED.
- `write_response` is combinational and valid before the accepting USER edge. READY status is SESSION_READY|BUSY|READY (19); a successful APPLIED terminal is SESSION_READY|APPLIED (20). CANCEL is legal after READY and before COMMIT: its matched response leaves status SESSION_READY (16), ERROR=OK, the same epoch and ACTIVE, without a new CONFIG application. BOOT extension is exactly1024 zero bits, epoch0, first sequence0 and camera0. Each successful COMMIT increments epoch by one.
- The paired capture endpoint enqueues one group for each set bit of `i_capture_enqueue` on PIX edges and consumes one group for each set bit of `i_capture_consume` on DFI edges. Each member has its own ledger. Drive balanced counts on valid paths and raise both source-idle bits after all promised capture work. `i_write_quiet` is the DFI-domain whole-write drain proof. Ordinary paths keep all counts at zero, `i_source_idle=3` and `i_write_quiet=1`.
- The DFI endpoint accepts `o_job_config` exactly on `o_job_config_valid && i_job_config_ready`. That offer remains stable under finite backpressure. Send one DFI edge of `i_job_config_done` only after acceptance, with `i_job_config_error` valid on that edge. `i_job_config_busy` may stay high while the endpoint finishes work and must be low on a successful DONE edge. On successful completion `o_dfi_active` publishes the complete tuple. `o_pixel_active` is the local capture owner snapshot. Both may lead USER APPLIED while admission is controlled by the protocol.
- `o_whole_ack_valid` reports the real whole ACK offered in PIX. `i_release_whole_ack=0` holds it. To inject a stale reply, keep the real ACK held, present a prior full tuple with `i_inject_ack_valid` and `i_inject_ack_ok=1`, and hold through `o_inject_ack_ready`. Release the real ACK afterward. A stale ACK cannot admit the new capture or publish APPLIED.
- ACK injection VALID/READY and release are sampled in PIX. Enqueue is PIX, consume is DFI, source-idle is PIX and write-quiet is DFI. A source may become idle while already promised data is still draining; idle alone does not satisfy that debt.
- A successful configuration requires `o_source_ready && !o_pause_new_frames` followed by one rising PIX edge with `i_frame_accept=1` and the actual first sequence in `i_frame_sequence`. PREPARE requires `i_pipeline_idle=1`. Once the matching whole ACK has completed, a legal first frame publishes APPLIED even if `i_pipeline_idle` has since gone low. `o_service_active` publishes at that frame edge. USER APPLIED subsequently reports the same sequence and epoch with all 32 exact words.
- Public tuple layout has extension bits `[1183:160]`, epoch `[159:128]`, reserved `[127:122]`, restart `[121:106]`, budget `[105:81]`, minimum quality `[80:74]`, adaptive flag `[73]`, JPEG quality `[72:66]`, base mode `[65:64]`, session `[63:32]` and request sequence `[31:0]`. Use the protocol spec as the independent oracle for values.

## Wire and scenario checklist

The existing registers, commands and error codes are in [pcie_protocol_v1.json](../docs/pcie_protocol_v1.json). Additive fields are in [quality_control_v1.json](../docs/quality_control_v1.json). `CFG_FEATURES` bit 6 advertises the capability. PREPARE_EXT and COMMIT use the existing 32 little-endian words. Legacy snapshots keep both new words zero. Quality version 1 uses W1 as `{reserved0, wb_enable, wb_b[9:0], wb_g[9:0], wb_r[9:0]}` and W12 as `{24'd0, version[3:0], fusion[1:0], tone[1:0]}`. Fusion 0/1 are balanced/legacy. Tone 0/1/2/3 are balanced/legacy/bright/highlight. Manual WB requires three gains in 1–1023. Disabled WB requires three zeros. SDR permits WB with Tone and fusion zero. Unknown versions, reserved bits, fusion 2/3, and invalid WB reject at PREPARE. Physical HDR requires ratio 4, black 50/50, qualification 15, zero upper delta word, and nonzero wait/age. The existing HDR motion fields and dehaze generation 0/1 remain independent.

Malformed shape/value requests are INVALID. A valid mode/processing mask absent from the advertised capability is UNSUPPORTED. In UHD JPEG the base capability word is 0x7f with quality enabled or 0x3f with it disabled. Schema2 modes are SDR only and enables are 0x0d. UHD accepts version 1 WB with Tone/fusion zero and rejects HDR/dehaze/lane as UNSUPPORTED. A nonzero HDR preset with SDR mode is INVALID. With QUALITY_CONTROL_ENABLE=0, W1/W12 are old reserved words, so directly sending nonzero quality bytes to that RTL produces INVALID. New SDK capability preflight instead raises UNSUPPORTED before sending those bytes. Do not conflate the two layers or invent precedence for a request containing several different errors.

Cover a legal first transaction on both topologies, distinct nonzero WB channels, nonzero Tone/fusion and old-generation dehaze in one exact round trip. Stall DFI CONFIG and withhold the whole ACK. Inject a stale old-epoch ACK, release the actual ACK, and publish the first frame while `i_pipeline_idle=0`. Exercise HDR exit to SDR HE, change to SDR dehaze, and reenter HDR with another valid profile. Verify a rejected request leaves all active owners at the previous epoch and a later legal request completes. Include a bad or withheld endpoint transaction only if required by the case, with a bounded watchdog. Use separate runs for deliberate stop or fault conditions.

## RK SDK public surface

Use Python 3.12. Put this project's `rk_sdk` first on `PYTHONPATH` and the workspace root second for the local `linux.rk_debug` peer. Run outside the workspace root so the overlay `linux.task3_pipeline` wins. The deployed equivalent puts this SDK first and the matching released peer second. No device, C2H kernel or image dependencies are required for a mock BAR test.

- `linux.task3_pipeline.mono_config_v2.MonoConfiguration` accepts the original fields and the optional quality fields in the JSON. `words()` emits a 32-element tuple of unsigned words. `from_words(words)` restores those fields and rejects nonzero reserved bits.
- `linux.task3_pipeline.config_transaction.ConfigTransactions(bar, timeout_s=..., poll_interval_s=...)` uses the supplied `bar.read32(offset)` and `bar.write32(offset, value)`. `mono_capabilities().quality_version` is 1 exactly when the live feature is set and schema2 is present. A nonzero quality field on a featureless bit rejects before the first PREPARE write. A legal transaction compares all 32 ACTIVE words after APPLIED.
- `dual_host.debug_modes.SharedControls(transactions, lut_timeout_s=positive_timeout, profile='r3', transition_guard=None)` uses the existing peer entry points `discover()`, `read_active()` and `propose(document)`. On a schema switch a complete original document may omit new fields, which default to zero. Once in schema2, a partial document preserves omitted fields. `dual_host.debug_modes.mode_document(text, topology, hdr_policy=None)` accepts the existing mode commands and an optional **JSON file path** for the complete HDR policy. Discover exposes quality options only when the feature bit is present; `parameters.schemas['2']` is a list of entries with `path`, not a nested fields dictionary.
- SDK numeric fields use strict integers, not bool/float/string. An absent schema2 declaration makes `mono_capabilities()` raise ConfigError/UNSUPPORTED. Physical ratio/black/delta profile checks belong to SharedControls/SharedStereoReceiver and the production BAR validator; generic MonoConfiguration/ConfigTransactions retain their generic numerical range. A wrong ACTIVE snapshot raises ConfigError/STALE and terminates that client without automatic retry.
- On the wire, assert identity with the JSON field offsets and masks. Cover old-bit rejection before writes, old configuration acceptance on the new owner, schema-switch defaults, a partial patch preserving other controls, and exact round trip of distinct RGB values. Simulate a wrong ACTIVE W1 or W12 after APPLIED and require stale/failure handling.
