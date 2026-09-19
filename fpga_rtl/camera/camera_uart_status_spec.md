# `camera_uart_status` specification

Once every `CLOCK_HZ` input cycles, the module snapshots three 32-bit counters and sends one 16-byte UART 8N1 packet. Each bit lasts `BAUD_DIV` cycles. The packet is `43 41 4D 31`, followed by `i_frames`, `i_errors`, and `i_digest`, each least-significant byte first. Inputs changing during transmission cannot alter the active snapshot. `o_tx` is high between packets and during each stop bit.

```wavejson
{ "signal": [
  { "name": "i_clk", "wave": "p........." },
  { "name": "snapshot", "wave": "01........" },
  { "name": "o_tx", "wave": "10.1.0.1.." },
  { "name": "byte", "wave": "x=........x", "data": ["0x43"] }
] }
```

Verification decodes two complete packets, changes all counters after byte three of the first packet, checks byte order and snapshot isolation, and checks packet cadence, start/stop bits, and idle-high behavior.
