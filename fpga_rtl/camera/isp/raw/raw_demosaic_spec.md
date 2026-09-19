# `raw_demosaic` specification

`raw_demosaic` converts one 3×6 RAW10 window into four horizontally adjacent RGB101010 pixels (`m_tdata[119:0]`). `cfg_bayer_phase` selects RGGB/GRBG/GBRG/BGGR phase and `cfg_edge_g` selects rounded bilinear or edge-guided green interpolation. Row parity and lane position determine each pixel's Bayer color.

The stage uses an elastic ready/valid output register. Reset is synchronous active-low. Frame-start and line-end metadata remain aligned with the four generated pixels. Arithmetic stays at 10-bit output precision with explicit rounded averages; downstream stalls hold output data and markers.

Timing diagram: [raw_demosaic_window.json](../waveforms/raw_demosaic_window.json).
