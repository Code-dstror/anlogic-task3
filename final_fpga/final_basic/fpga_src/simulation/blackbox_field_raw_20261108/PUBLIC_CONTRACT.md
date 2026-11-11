# RAW field short-test contract

The independent test author used only [public declarations and the ARAW byte layout](PUBLIC_PORTS.md), the
[store specification](../../rtl/stereo_raw_store_spec.md), the
[formatter specification](../../rtl/raw_video_record_formatter_spec.md), and this handoff. The opaque
[source list](sources.json) is for compilation and hashing; it is not an oracle.

The board observation was first SOURCE sequence 1 from each eye, a later gap per eye within the initial
33 s, and no further gaps in a 251 s observation. Complete records arrived at 30 fps per eye. The
observation did not identify the missing sequence, CRC, capture rejection, or host lease return timing.
The small tests distinguish loss with sufficient service from an explicit full-slot rejection. They cannot
identify the board's cause or establish full-size rate.

- Legal RAW profile: `WIDTH=8`, `HEIGHT=2`, `RAW_EXPORT_ENABLE=1`, `EXTERNAL_DECODER=1`,
  `VERIFY_DECODE_ACTIVE=1`; internal DFI period 7.5 ns, common cold reset, exclusive RAW mode, enable
  high, nonzero session and epoch zero. Idle processing and external decoder endpoints; the RAW path
  uses `o_raw_*`. The earlier `EXTERNAL_DECODER=0` handoff was an illegal RAW profile.
- BEGIN is one scalar valid/ready channel. Hold `s_frame`, `i_begin_camera`, and valid until ready;
  readiness latency is not fixed. On that edge `o_begin_accepted` is the result level and
  `o_capture_slot` is meaningful only if accepted (per-eye 0/1). A full eye must reject, without
  borrowing a slot or requiring finish. Source descriptor layout: camera [4], session [76:45], sequence
  [108:77], epoch [140:109], time [204:141], width [220:205], height [236:221], RAW10 code 1 [238:237],
  Bayer [369:368], valid Bayer [370], valid timestamp [371]; other unused bits zero.
- Feed `i_finish_valid/ok` on the accepted eye after DDR bytes are in the memory BFM. Successful finish
  represents matching SOURCE success and successful write acknowledgements. Negative finish cannot
  publish the failed frame or prevent the other eye from finishing independently.
- The job descriptor clears [383:367] and bit 0, replaces [44:13] by allocated generation and [12:5] by
  the accepted per-eye slot, and preserves the other source fields. Bayer and timestamp validity are
  separate frozen outputs. Generation is nonzero and globally increasing in allocation order; lease is
  its 64-bit zero extension, job ID is `0x8000000000000000 | lease`. RAW token is
  `{16'h5241,session32,generation32,13'd0,camera1,slot2,sequence32}`. The descriptor and token are
  borrowed until matching SAFE. RAW record length is the whole 64-byte header plus payload length.
- Slot bases are `0x02000000/0x03000000` for eye 0, `0x06000000/0x07000000` for eye 1. Four RAW10
  samples occupy the 40-bit group at bit offsets 0, 10, 20, 30, sent as five bytes in little-endian order.
  The BFM answers actual 16-byte AXI read beats with matching ID, RLAST and OKAY. 8×2 payload is
  20 bytes. The real formatter gets the accepted RAW offer and its frozen metadata. A host SAFE is sent
  after the real ARAW last handshake and formatter/RAW drain; negative RAW STOP uses the negative
  terminal and formatter abort/drain. Wrong SAFE cannot be accepted. A matching SAFE and actual
  `o_retire_done` are distinct; low `i_release_quiet` can hold the occupied slot after SAFE.
- STOP before initial BEGIN presentation rejects. While a BEGIN is pending, STOP may prevent an
  undecided allocation or allow an already decided response. Any accepted BEGIN must still have its
  negative finish consumed, including after STOP at/after its response. STOP after record START and
  before successful completion preserves sampled stalled AR and RAW beats through handshake and
  reports a negative terminal after drain; it does not retract a success already published. Check
  offer/beat stability on sampling edges and keep the corresponding commitments through recovery.
