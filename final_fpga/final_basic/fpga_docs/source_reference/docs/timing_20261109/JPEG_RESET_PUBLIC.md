# JPEG ingress reset short-test contract

The independent author may read this document, `verification_reference/egress_public.md`
for the complete public ordered_frame_cdc interfaces and token/extension wire layout,
and the project protocol JSON. Do not read production RTL, old TB/runners or model implementations.
The actual opaque implementation closure is the same one listed in that public egress contract;
it includes ordered_frame_ingress, ordered_frame_egress, the real FIFO/fence and extension RAM.
Use the production CONTEXT/WRITE_TAG/RECORD_EXTENSION=1, WIDTH16384,
BORROW_EXTENSION=1, STREAM_EXTENSION=1, MASK_CONTEXT=0, EXTENSION_RAM=1 profile.

This boundary transports opaque JPEG bytes; no image generation or decoding is required.
Drive a few full16byte words and a short tail, true LAST, then an actual result with matching
sequence/epoch/quality and exact KEEP byte count. A complete legal128flit extension with independent
wire oracle and matching prefix must cross the actual FIFO/RAM before result acceptance.
There is no independent cancel port; coordinated source/sink reset cancels the cohort.
Quiescent fence is a proof of true drain, not a reset or permission to discard a held beat.

All input metadata remains stable through its public handshake. The CONTEXT transfer may precede
START ready; retain START metadata until its actual handshake. A frozen START or extension/FENCE
offer cannot change under stall. Payload when VALID is low is undefined, including after reset;
do not assert zeros then. Reset must withdraw public VALID/READY immediately, even if source or
sink clock is stopped. After normal local release and public reset_done, a distinct new frame
must produce only its own metadata/data/extension/result; no pre-reset bytes or false success.

Required cases: legal first transaction through actual result and fence, two consecutive frames
with different eye/session/epoch/tag and caller input mutation after completed handshakes;
pause consumer on START, DATA LAST, extension and RESULT. Exercise reset while source clock is
stopped with each of (a) CONTEXT consumed but START held, (b) partial JPEG data,
(c) extension head/midpoint/final flit, and (d) frozen FENCE/result held. Restart and complete a
fresh legal frame after each bounded scenario. Cover a negative result and a wrong identity/length
using the exact existing E1/E2/E4 error rules; do not relax metadata or lease lifetime to pass.
For malformed base in flit1/flit7, complete all128flits and RAM writes before expecting shape fault;
flit0 and ordering errors can quarantine earlier. Keep no duplicate whole-frame raster tests here.

Use explicitly TD D:/App/TD_Release_2026.2.210.850 and ModelSim D:/App/modelsim/win64,
Python python. Models and headers are
compiler inputs only. Use work.PH1_PHY_GSR and ph1.glbl sibling tops as appropriate, no internal
force or hierarchy reads. Each test process has a <=60s wall budget and a simulated watchdog.
Preserve input/model/TB SHA, original tool/fixture failures and actual handshake observations.
