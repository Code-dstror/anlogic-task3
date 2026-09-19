# `raw_blc` specification

`raw_blc` is a one-entry elastic RAW10 stage. Each of four 10-bit lanes is reduced by its lane-specific black-level parameter with saturation at zero. Input and output use ready/valid with frame-start `tuser` and line-end `tlast`. Reset is synchronous active-low and clears output valid. With an empty output slot or an accepting downstream, a new beat may be accepted every clock; visible latency is one clock for an accepted beat.

Corner cases: samples below their offset produce zero; samples at or above the offset retain 10-bit precision; while `m_tvalid && !m_tready`, data and markers remain stable.

Timing diagram: [raw_blc_transfer.json](waveforms/raw_blc_transfer.json).
