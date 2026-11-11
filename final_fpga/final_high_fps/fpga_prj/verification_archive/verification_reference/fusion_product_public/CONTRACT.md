# Unified real ISP / product public short contract

This is a public black-box carrier contract. Do not read the generated `.v`, projection scripts,
production RTL, vendor implementation or any prior test. The generated port declaration and
`compile.json` are public. Hash and compile the implementation inputs without opening them.

Use the transport, BAR, reset, native ARM/fence/ACK, RAW input and real retirement specification
in `../uhd_integration_public/CONTRACT.md`, subject to the explicit changes below. The old external
ISP model section does not apply: this carrier instantiates the real `shared_wide_isp`, WB,
Tone/Gamma and downstream JPEG. It retains the true source owner, configuration path, DDR RAW
store/read, JPEG write-response gate, native PCIe transport and record retirement. Sensor/CSI,
PLL, physical DDR and PCIe hard port remain external digital boundaries. Geometry is a short
480x32 verification raster for the UHD profile; capability discovery still reports 3840x2160.

## Prepared carrier and tools

The current prepared opaque carrier is `../../tmp/fusion_product_projection/real_isp_a3`.
Read only `uhd_integration_fixture_ports.vh` and `compile.json` there. Source paths in the
compile list are relative to this new project, TD paths relative to the explicitly selected
`<TOOLS_ROOT>/TD_Release_2026.2.210.850`. Models are compiled into `ph1`, except GSR into `work`.
The compiler group containing the two fdct MAC files must use ordinary Verilog `-mfcu`;
do not force all production files to SystemVerilog. New benches may use SystemVerilog.
Sibling global tops are in the compile list. ModelSim is `<TOOLS_ROOT>/modelsim/win64`.

The maintainer-only `prepare_rom.ps1 -SimDirectory <new absolute run path>` initializes thirteen
frozen ROMs. It can be executed opaquely. All initialization files and original input hashes
must be recorded. Tone MIF is initialization only; Gamma is a public mathematical lookup table.
Simulation clock/watchdogs follow the inherited contract: at most 200000 PIX cycles per case
and at most 180 seconds including compilation, with a 60-second per-process simulation deadline.
The genuine SYS25 POR takes about 81.9 us; do not bypass it or wait less than it.

## Actual arithmetic and configuration

The legacy external `i_isp_*` model inputs are unused and should be driven zero. `o_isp_*` outputs
are passive observations; `o_isp_raw_valid` is an offer, not an acceptance strobe and must not be
counted with the now-unused external ready input. Use real capture, SOURCE, JPEG and terminal
handshakes and emitted record bytes for success. No hierarchical signal access is allowed.

The current quality wire contract is `../../docs/quality_control_v1.json`. UHD supports schema2
MONO_SDR, grayscale/Gaussian/HE and combinations, plus manual shared RGB Q8 WB. It does not support
HDR, dehaze or lane. UHD's prior feature subset is extended by bit6; other capability meanings
are unchanged. `quality_version=1`, WB enable1 and distinct RGB gains in 1..1023 are legal;
Tone/fusion preset must be zero for SDR. W1 = R | G<<10 | B<<20 | 1<<30, W12=0x10.
Cold geometry1/2 select UHD15/20; profile5/6 must be acknowledged by the sensor boundary.
Before PREPARE or PREPARE_EXT, write CFG_HOST_CAPABILITIES (application offset0x274)
with bit0 FRAME_APPLIED set, then read it back. CFG_ERROR is at application offset0x24c;
record the code for any rejection instead of interpreting BUSY or elapsed time alone.
The cold-page public generated constants are in `../../rk_sdk/dual_host/pcie_protocol_v1.py`
and `stereo_control_v1.py`; these contain protocol values, not test or implementation logic.

Public pixel math is given in `../../../camera_hdr_quality_r1/docs/blackbox/ISP.md` and its linked
Tone contract. Production Bayer phase is GBRG. SDR subtracts50 with floor0; unit CCM; WB is
round-half-up(sample*gain/256), clipped to1023, then the frozen Gamma lookup. The real shared ISP
freezes the accepted SOF configuration. Spatially constant per-color Bayer inputs are sufficient
to create an independently predictable constant RGB frame, including reflected boundaries.
For example choose independently distinct R/G/B RAW10 values above50 and legal distinct WB gains.
Use independently decoded JPEG and predetermined tolerance (e.g. at most4 RGB8 codes for a
constant-color scene) for the lossy encoder. Do not derive expected image values from DUT output.
Metadata processing mode is 0x80 | processing_enables for schema2, and exact requested epoch,
session, capture sequence and short width/height must match the emitted record.

## Required new cases

1. A legitimate cold UHD boot: real BAR select/apply, CFG schema2 with manual WB, remote ACK and
actual cold FS/SOF/FE leading to APPLIED, record v4 select, native buffer ARM and APP arm. The
first product goes through actual RAW writes, replay, real ISP and JPEG, delayed final write B,
record offer, native fence, matching host ACK and real ring retirement. Reconstruct every TLP
with strobes, prove no record before the last B and no slot retirement before matching host ACK.
Use finite AXI and TLP backpressure. The entire JPEG must decode and match the independent image.
2. After a legal first frame, inject one SLVERR on an already committed RAW AR after actual JPEG
START. Drain all promised R/W/B. The frame must produce negative SOURCE/JPEG/writer/ticket terminal,
zero successful record and release RAW ownership; then a new legal same-session frame must reach
actual retirement. Preserve any outstanding native buffer ownership correctly.
3. A stopped DFI startup: system/USER can release while DFI clock is stopped. PIX is permitted to
remain reset through the memory/cohort interlock, and DFI remains reset until its clock resumes.
Resume DFI, await actual PIX/DFI release and complete the first legitimate configured product.
Reset release and resource ownership may not be shortcut by the testbench. Cover the other UHD
cold rate code if practical in this case.

The author may add a small bounded configuration switch for WB if the public legal first-frame
event can be supplied while admission is paused. Do not force arbitrary BUSY/error recovery.
The exact first-terminal proof is required; bad-input zero-output alone is insufficient.

Each run must save test/source/ROM hashes before and after, exact commands, decoded record,
JPEG integrity and numerical metrics, original failure logs and classification. This proves a
short raster under digital boundary models, not full4K sustained FPS or board behavior.
