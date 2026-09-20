# Camera ISP

This directory contains the 4-PPC RAW10 to RGB888 ISP used after the IMX415
capture path. The stream contract is `40-bit RAW10 AXIS-like input -> 96-bit
RGB888 AXIS-like output`; `tuser` marks frame start and `tlast` marks line end.

The two line banks use four 20-bit PH1 ERAM blocks and the gamma lookup uses a
1024x8 PH1 ERAM. The wrappers follow the vendor template at
`template/verilog/Device-Primitive/PH1A/RAM,ROM/ph1a_ram_rom.v`. ModelSim tests
compile the real TD PH1 primitive model from `sim_release/ph1/ph1_logic_eram.v`.

Run `./run_camera_isp_modelsim.ps1 -Test core` for the pixel/marker/backpressure
test. The `1080` and `4k` selections run 1920x1080 and 3840x2160 frame tests.

The integrated crop-to-ISP-to-packer tests currently pass for 16x4, 1920x1080
and 3840x2160, including the former right-edge regression. See
`doc/imx415_camera_validation.md` for exact logs and current limitations. TD
synthesis resolves Gamma initialization relative to its source file; simulation
runners stage that same file in their isolated working directory.
