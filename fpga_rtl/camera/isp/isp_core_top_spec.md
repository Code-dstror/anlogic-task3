# `isp_core_top` specification

## Interface and behavior

Single-clock, synchronous active-low reset ISP top. `s_tdata[39:0]` carries four RAW10 pixels with lane 0 in the least-significant bits. `m_tdata[95:0]` carries four RGB888 pixels, each lane encoded as R:G:B. `s_tuser/m_tuser` are frame-start markers and `s_tlast/m_tlast` are line-end markers. Width and height are 13-bit runtime inputs; Bayer phase and green interpolation mode are sampled by the RAW pipeline. Output statistics count accepted beats, accepted frame starts and saturation events.

The pipeline is elastic: an accepted beat is `valid && ready`; a stalled output holds data and markers. Latency is pipeline- and frame-position-dependent because the demosaic stage buffers lines. The first output requires sufficient following-row data. Maximum configured dimensions are 3840×2160 and width must be divisible by four.

## Processing

RAW10 → saturating black-level subtraction → 3×3 Bayer neighborhood → RGB101010 demosaic → Q8 white balance → signed Q8 3×3 CCM → registered Gamma/linear conversion → RGB888.

## Verification

The real RTL passes the integrated 16×4, 1920×1080 and 3840×2160 ModelSim tests recorded in `doc/imx415_camera_validation.md`. TD synthesis is pending.

Timing diagram: [isp_core_top_stream.json](waveforms/isp_core_top_stream.json).
