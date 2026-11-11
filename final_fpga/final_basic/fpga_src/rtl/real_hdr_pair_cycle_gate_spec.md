# HDR pair cycle gate

This candidate retains two PIX-domain group contexts. The physical member
rasters, RAW10 packing, DDR bank authority, RAW14 merge, T96, ISP and JPEG
algorithms are unchanged.

`s0` is physical LONG and `s1` is physical SHORT. Their 147-bit FIFO tokens use
RAW10 four-pixel data `[39:0]` (pixel 0 at `[9:0]`), cropped SOF `[40]`, cropped
EOL `[41]`, abort `[42]`, event/error code `[46:43]`, word-domain exposure group
`[78:47]`, independent VC capture sequence `[110:79]`, trusted identity `[111]`,
and trusted common-cycle identity `[112]`. The retained upper token fields are
not used here. Code 7 is true FS, 6 is true FE after upstream CRC/full-sensor
geometry validation, 0 is cropped RAW, and 8/abort/untrusted identity is negative.
Crop EOL is neither physical FE nor the eventual JPEG record TLAST. This gate
has no TKEEP; each RAW beat has all four samples present. Cropped frame size
and margins are checked by the unchanged crop/ingress modules.

Tokens transfer only on `s_valid && s_ready`. RAW payload is consumed without
gate backpressure. A new FS may wait for its own previous ingress/held SOURCE,
or for one of the two contexts; the other member remains able to consume FE.
The upstream real camera FIFOs remain finite at 512 tokens: no claim is made
that arbitrary DDR or SOURCE stalls can be absorbed. The gate adds no pixels
of storage. The existing source/ingress ownership and physical packet timeout
contracts continue to bound service. A third unresolved group is held, never
silently declared good or allowed to overwrite a context.

At trusted LONG FS a free context records group and per-member lifecycle.
Both active contexts share the registered capture cohort. Only one unfinished
member can exist on each ordered lane, so its registered output sequence is
also the sequence used to create that lane's terminal. This removes 256 bits
of duplicated context cohort/sequence registers. SOURCE bundles independently
copy the old registered identity on their enqueue edge and do not borrow it
afterwards, including same-edge old-cohort cancellation and new LONG FS.
SHORT joins only the exact group. An unmatched SHORT FS can wait for its
LONG only with trusted member and cycle identity and a nonzero group. An
orphan SHORT at receiver startup drains without RAW, SOURCE or a good pair.
An untrusted FS matching an existing group still cancels that group.
Each lane emits registered 40-bit RAW,
SOF and EOL into its existing passive ingress; there is no downstream RAW
ready at this boundary. Admission uses local ingress readiness, so the old
SHORT can remain active while the next LONG enters the other DDR bank.
Upstream context and payload remain ordered independently on each lane.

Each started member produces exactly one held SOURCE bundle at its own true
FE, or a negative bundle on CRC/geometry/identity/reentry/timeout/cohort fault.
The former shared `o_source_session/epoch/ok/error` now belong to LONG;
`o_source1_session/epoch/ok/error` are independent SHORT fields. All SOURCE
fields and valid hold until the corresponding ready handshake. Capture data
still uses the common `o_session/o_epoch`: a cohort mismatch cancels old
contexts and suppresses their same-edge RAW before a new cohort can emit RAW.
Each held terminal retains its context's original cohort and VC sequence.

A positive LONG SOURCE is member success, not pair success. If its SHORT
later fails, LONG is never retracted, and the next LONG owning that lane is
never aborted for the old group. SHORT's real negative writer finish marks
the matching DDR bank bad. If SHORT never emitted SOF, it never acquired a
writer; the incomplete bank expires only after its existing real writers are
idle. Both members' real successful writers remain necessary for bank READY.
Writer B errors independently veto READY even when both physical FEs were good.

`o_good_pairs` and `o_pair_event/o_pair_ok` describe trusted physical pair
completion for sensor warmup, not JPEG publication. A fault can cancel both
contexts on one edge; the diagnostic counters count both, while the sensor
owner receives one negative event, sufficient to leave STABLE. STOP disables
new group admission at the sampled FS edge and drains the rejected tails.
A change in permission leaves the same-edge outcome of a registered group's
matched RAW, FE or error unchanged. A new group can accept LONG and SHORT FS
together. When both tokens report a fault for a registered group on one edge,
the LONG error takes priority. A SHORT fault can suppress a simultaneous LONG
RAW beat and issue the LONG negative terminal on that edge. Timeouts issue
only negative outcomes.
Skipped/failed-group drain ordering uses modulo-32 serial comparisons within
the open half-range; zero is invalid. Coordinated cohort reset clears both
contexts and the drain watermark.

`o_quiet` is a PIX-domain level. It goes high when no group context is active
and both held SOURCE terminals have been accepted. With new admission closed,
it stays high through the drain of unadmitted sensor tokens. Those tokens still
advance the skip watermark and obey the token handshakes. On re-enable, a fresh
group must start with a trusted LONG FS and a new group ID. The caller combines
`o_quiet` with capture ingress, transport and writer drain before changing the
sensor clock or applying the next epoch.

With ordered physical lanes two contexts cannot complete GOOD on one edge.
The older group must have finished LONG before the newer LONG FS can create
the second context; its outstanding SHORT must finish before the newer SHORT
FS can start. There is only one SHORT token per edge. The short fixture asserts
`good_events <= 1` throughout and separately checks two-context cancellation.

Focused evidence is generated by `tools/run_hdr_overlap_unified.py`. It uses
the actual shared ingress, shared writer, DDR authority/directory and official
TD 2026.2 RAM model at 16x2. The single-clock FIFO and AXI sink are test-only
boundaries. It checks RAW bytes, real B-before-positive-finish, matching pair
publication, finite endpoint/terminal stalls, negative outcomes and recovery.
The old gate is a negative control on the same fixture. It does not validate
CDC, electrical capture, sustained full-HD fps, physical timing or board output.
