# `color_pipeline_axis` specification

This elastic color stage accepts four RGB101010 pixels in 120 bits and emits four RGB888 pixels in 96 bits. It applies unsigned Q8 white-balance gains, a signed Q8 3×3 color-correction matrix, saturation to 10 bits, then twelve registered Gamma/linear lookups. Gamma-enabled and linear-bypass modes have identical one-clock lookup latency.

`i_rstn` is synchronous active-low for pipeline state. Transfer occurs only on ready/valid handshakes. Output data, frame-start and line-end markers remain stable under backpressure. Statistics count accepted output beats, accepted frame-start beats and saturation-bearing beats.

Timing diagram: [color_pipeline_axis_transfer.json](../waveforms/color_pipeline_axis_transfer.json).
