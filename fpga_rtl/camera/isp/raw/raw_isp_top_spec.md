# `raw_isp_top` specification

`raw_isp_top` composes `raw_blc`, `raw_row_window` and `raw_demosaic`. Its input is four RAW10 pixels in 40 bits; its output is four RGB101010 pixels in 120 bits. Runtime size, Bayer phase and green interpolation mode are passed to the neighborhood and demosaic stages. Reset is synchronous active-low.

The ready path propagates downstream capacity through the elastic stages. `tuser` remains a frame-start marker and `tlast` remains a line-end marker. Latency includes one-line lookahead and internal flush steps; throughput after fill is one four-pixel beat per accepted clock.

Timing diagram: [raw_isp_top_frame.json](../waveforms/raw_isp_top_frame.json).
