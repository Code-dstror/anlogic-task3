# CSI-2 RAW10 receiver contract

`csi2_raw10_rx_stream` accepts the 32-bit packet-aligned stream produced by
the reviewed four-lane Anlogic camera PHY.  The first valid word of every
packet is the CSI-2 header.  This boundary is also exposed for simulation so
the protocol, CDC, and recovery logic can be tested without pretending to
simulate MIPI electrical behavior.

The board integration target supplies 24 MHz IMX415 INCK and configures four
lanes at 720 Mbit/s per lane.  The forwarded DDR clock is therefore 360 MHz
and the four-byte aligned-word clock is 90 MHz.  These are integration
requirements, not claims of measured PHY margin.

The supported image packet is virtual channel 0, RAW10 data type `0x2b`.
Every received sensor line is passed through; active-image cropping belongs to
the parent camera pipeline. RAW10 word count may have any 32-bit word
alignment but must be a multiple of five bytes. The confirmed sensor lines
are 1932 pixels / 2415 bytes in binning mode and 3864 pixels / 4830 bytes in
full mode. Payload and the two CRC bytes may end at any byte position in the
final 32-bit PHY word.

The pixel-clock output is a ready/valid event stream.  Normal events carry
four ten-bit pixels in `o_raw_data`, with `o_raw_sof` on the first group after
a frame-start short packet and `o_raw_eol` on the last group of a RAW10 long
packet.  An event with `o_frame_abort=1` is a control item: pixel data and
SOF/EOL are ignored, `o_error_code` gives the reason, and the consumer must
reset/drain its current frame.  After an abort this receiver suppresses pixel
items until the next valid frame-start packet.

Error codes are: `1` uncorrectable header ECC, `2` payload CRC mismatch,
`3` asynchronous FIFO overflow, `4` malformed packet/length, and `5`
unexpected frame sequencing.  CSI-2 payload CRC is reflected CRC-16 with
polynomial `0x8408` and initial value `0xffff`.

The physical side cannot be backpressured.  The official Anlogic Soft FIFO
3.0 is therefore used only as a clock-domain buffer.  Full/almost-full causes
one abort control item and drop-until-next-frame-start recovery; it never
silently discards pixels while claiming the frame is valid.
