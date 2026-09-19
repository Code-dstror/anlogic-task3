# `raw_row_window` specification

`raw_row_window` accepts 40-bit, four-pixel RAW10 beats and emits a 180-bit neighborhood containing three rows by six columns. Runtime width/height are latched at frame start. The module preserves Bayer phase at all borders using reflected neighbors, emits row-first, row-last, frame-first and row-parity metadata, and reports internal activity through `m_busy` and `dbg_state`.

Two 40-bit line banks are implemented as four 20-bit, 1024-deep PH1 ERAM blocks. Their synchronous read latency is explicitly aligned with the data/metadata pipeline. The module inserts internal line-flush and final virtual-row steps, so total latency depends on width and position. Backpressure freezes the complete neighborhood and all state that belongs to it.

Legal width is a multiple of four and no greater than `MAX_WIDTH`; legal height is bounded by `MAX_HEIGHT`. Invalid or truncated frames enter the documented discard/restart path rather than emitting partial valid neighborhoods.

Timing diagram: [raw_row_window_line.json](../waveforms/raw_row_window_line.json).
