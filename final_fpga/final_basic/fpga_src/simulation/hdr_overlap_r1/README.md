# HDR overlap short proof

Run with the explicit local ModelSim and TD 2026.2 paths:

```powershell
& 'python' -X utf8 -I -B refactor/dual_unified_r1/tools/run_hdr_overlap_unified.py --name hdr_final --modelsim-bin D:/App/modelsim/win64 --td-root D:/App/TD_Release_2026.2.210.850
```

Add `--old-gate` under a different unique run name for the old merge-candidate
gate negative control. Source snapshots, exact commands, SHA256 identities and
all logs are retained under candidate `tmp/hdr_overlap_r1/<name>`.

The fixture uses actual `shared_raw10_frame_ingress`,
`shared_raw_capture_writer`, `hdr_pair_bank_owner_dual`, directory and official
ERAM model. Only the two bounded single-clock FIFOs, BEGIN arbitration and AXI
write endpoint are models. RAW words have no inserted source bubbles. Every
actual W byte is checked against the independent transmitter pattern. Every
pair publication requires both matching real successful writer completions,
each after actual B handshake. Finite AW/W/B stalls include every final W.

Final short results on 2026-11-04: `new_h` PASS, 39 checks; `old_c` PASS negative
control. Both receive the same 16 cross-VC overlap groups. New produces 16
physical-good and 16 actual DDR pair products; old produces 8 and 8. Other
cases cover late peer CRC after LONG success/new LONG start, negative AXI B,
ingress geometry failure, stable loss/recovery, peer failure before pixel SOF,
independent held SOURCE, two-context epoch cancellation and same-edge old
cohort cancellation/new LONG FS, missing LONG/SHORT
FE, STOP, group/sequence wrap and reset during a frame.

The product consumer models no reads and releases acquired banks only after
the unchanged read/write/ticket-quiet contract. Input timing includes real
write-quiet service windows. A separate overpacked development stimulus had
no global write-quiet interval and exhausted both banks; that failed run
`new_c` is retained. These results establish functional overlap ownership,
not unlimited buffering or sustained 1920x1080 30 fps. HD numerical/JPEG proof
is separately maintained in `merge_integration_20261101/hdr_startup`.

`--physical-rx` selects the actual four-lane byte aligner, packet RX,
full-width crop, official asynchronous member FIFOs and real I2C recipe owner
with height reduced to one sensor row. Final `physical_b` PASS has 15 checks:
sixteen physical groups produce sixteen good events, zero overlap skips,
all sixteen actual FEs/crops on each lane, and missing FE remains negative.
STABLE propagation makes the first nine rapid groups unadmitted in this
short artificial input schedule; that is distinct from the removed skip.

The HDR long oracle checks nine full sensor groups: eight warmups including
the retained overlapping groups 1 and 2, then primary product SOURCE9. Its
independent RAW14/T96/JPEG-byte/decode/v4/SAFE/ACK and SDR-return bad-CRC checks
remain. The current DDR commit observation is LONG-only; the oracle separately
requires one real positive finish from each writer before the one pair acquire.

Synthesis, P&R, timing and board validation are NOT_RUN by this short runner.
