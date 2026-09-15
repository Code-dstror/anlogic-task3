# `pcie_axis_async_fifo` configuration

The asynchronous frame FIFO is implemented by the official Anlogic
`Soft_FIFO` 3.0 IP shipped with TD 6.2.1. It is not a handwritten FIFO.

| Generator option | Value |
| --- | --- |
| Device family | PH1 (`PH1A90SEG324`) |
| Clock mode | Asynchronous |
| Memory | ERAM / EMB20K area optimization |
| Write width/depth | 147 bits / 512 words |
| Read width/depth | 147 bits / 512 words |
| Show-ahead | Enabled |
| Output register | Disabled |
| Almost full | 504 words |
| Almost empty | 2 words |
| Reset | Asynchronous assert, synchronous release |
| Synchronizer stages | 2 |

The 147-bit word is `{slot_id[1:0], tlast, tkeep[15:0], tdata[127:0]}`.
`axis_frame_fifo_ip.v` is only a ready/valid adapter around the encrypted
vendor IP. The upstream side may write only when `o_source_ready` is high;
the downstream word is popped only on `o_sink_valid && i_sink_ready`.
