---
name: jpeg-fixedpoint
description: Use when implementing or checking FPGA JPEG encoding, fixed-point DCT/quantization, entropy output, MCU boundaries, or sustained throughput. Do not use for ordinary JPEG file conversion.
---

# Hardware JPEG and fixed-point verification

Freeze color/range, sampling and MCU order, geometry, quantization/Huffman tables, signed widths,
scales, rounding, saturation and output protocol before an implementation change. Preserve the old
numeric and wire contract unless the user authorized a change. A fixture JPEG is not a hardware encoder.

Use the fresh-context black-box workflow in `rtl-stream-contract`. Give the verifier public numeric
specification and an independent reference, not RTL or expected bytes extracted from the candidate.
Start with small known blocks and short legal images; cover signed extrema, padded MCU/line edges,
restart/DC prediction, run length/Huffman, 0xFF stuffing and the exact final bits. Decode the complete
result independently: SOI/EOI or a matching length alone is insufficient.

Default to bounded directed tests. Full-HD or multi-frame continuous runs need an actual performance/
image qualification requirement and a stated time budget, not every small edit. Distinguish RTL output,
independent numerical/image acceptance and runner bookkeeping; preserve original failures when a parser
or benign marker whitespace is corrected. Never change an oracle simply to match the implementation.

The current PCIe header precedes payload length, so a slot becomes READY only after encoding, camera
error settlement and real memory writes succeed. Oversize/bad frames are discarded, not truncated into
a fake JPEG. Hold frame settings, descriptor and offered tail through real handshakes and retirement.

Rate evidence uses difficult as well as flat images, actual input and compressed bytes, bounded DDR/host
stalls and warmup/steady/drain separation. It reports unique complete source products, queue/debt trends
and model scope. Bus width, one frame's latency or a small-image BFM cannot prove sustained 1080p FPS.
