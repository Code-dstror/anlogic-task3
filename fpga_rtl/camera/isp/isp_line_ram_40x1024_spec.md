# `isp_line_ram_40x1024` specification

This line-memory wrapper stores 1024 words of 40-bit RAW data. It is composed of two `isp_line_ram_20x1024` slices, each backed by a PH1 `PH1_LOGIC_ERAM` in simple-dual-port mode. The common clock drives a write port (`wr_en`, `wr_addr`, `wr_data`) and an independently enabled synchronous read port (`rd_en`, `rd_addr`, `rd_data`).

The read result is registered by the ERAM and holds when `rd_en=0`. Write/read collision behavior follows the configured PH1 primitive; `raw_row_window` schedules addresses and pipeline state so verified frame traffic remains deterministic. The wrapper has no independent reset because stale memory words are ignored until associated valid pipeline state exists.

Timing diagram: [isp_line_ram_read.json](waveforms/isp_line_ram_read.json).
