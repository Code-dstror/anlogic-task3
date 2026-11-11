# Independent black-box FPGA tests

This is the project default for functional verification of new/changed RTL and newly requested functional tests. It does not require
rerunning tests for documentation-only changes, or make native elaboration/mapped-constraint checks
into functional simulation. An explicitly requested historical reproduction can use its frozen bench,
with that scope stated rather than called independent black-box verification. A user's narrower or explicitly
different verification request takes precedence.

## Separate roles

Create the test author without inheriting the implementation conversation (`fork_turns="none"` when
available). Use the user-requested model/effort when supplied. The author may continue several related
test modules with only public contracts; do not later leak implementation explanations into that context.
If no fresh agent is available, report the independence limit instead of claiming the same-author test
was independent. This requirement authorizes delegation for the verification task, not unrelated work.

The maintainer reads RTL, binds the production source list and supplies the interface specification.
The test author may read that specification, its own newly written bench and public-output logs. It
may submit opaque RTL/IP/model files to the compiler and compute their hashes. It may not open their
implementation, use a previous white-box bench as oracle, inspect/force internal hierarchy, or infer
expected values from DUT output. Compiler diagnostics that expose source expressions are handled by
the maintainer; return only the needed dependency, legal parameter or public-interface correction.

## Handoff before writing the bench

Include only what the external test needs:

- Module/port declarations, parameter meanings and the complete legal profile used in production.
  Include transitive sources, include directories, defines, IP/model/library roots and sibling globals.
- Clock relationships, asynchronous assertion and release/stop contracts; distinguish startup latency
  from the first legal sampling edge. Never invent an extra reset or use a simulation-only bypass as production evidence.
- Data layout, valid bytes/lanes, geometry and frame boundaries; public mathematical or wire-format
  reference independent of the RTL. Identify bounds and undefined inputs explicitly.
- Acceptance and holding rules, including borrowed descriptors; pulse versus level; counters' units
  (physical FS, RAW4 group, FIFO word, burst, record) and observation domain.
- Success and failure completion, cancel/STOP priority, outstanding obligations, SOURCE/B requirements,
  precise identity matching, SAFE versus actual retirement and cold configuration versus runtime changes.
- The externally observed bug/risk and the smallest meaningful positive, negative and recovery cases.
  Do not prescribe internal states, preferred implementation or a predetermined PASS conclusion.

For bitstream history, distinguish a frozen UART first-window from continuous measurements. A sampled
reset-high value cannot disprove an inter-edge pulse. Fault injection through public interfaces proves
a conditional mechanism, not that the board experienced that pulse width or exact event.

## Run and judge

Use short scenarios, small legal geometry and explicit wall-clock plus simulator watchdogs. Keep a
legitimate first transaction through its actual terminal, consecutive transactions, finite backpressure,
boundary tails, cancel with committed work, and next-transaction recovery where the risk requires them.
Only expand/repeat for a new change, failure or uncovered risk; do not turn “more thorough” into an
unbounded random sweep or hours of full-HD frames. Long image/rate qualification needs a clear task
requirement and its own budget; warmup, steady interval and final drain are separate measurements.

Scoreboard only real interface handshakes. Do not throttle a passive camera by a diagnostic enqueue
pulse, count a held DONE/accepted level every cycle, require a borrowed input handshake before its
consumer can complete, or free a buffer merely because a SAFE acknowledgment has been accepted.

Classify each failure as implementation, contract, fixture or tool/dependency. Never weaken a defined
expectation just to match the DUT. Ask the maintainer for the normative basis of an ambiguous field;
retain the original FAIL and document the correction. Undefined-input observations remain separately
labeled, not relabeled into functional success. A real DUT defect is fixed by the maintainer, then the
same externally derived case runs again in a new directory. Board anomalies are not automatically unique diagnoses.

Preserve exact commands, parameters, versions, before/after source and TB hashes, terminal markers,
raw logs and modeled boundaries. Match markers robustly to harmless whitespace, but do not fabricate
them or overwrite an old FAIL. HDL completion, independent image/numerical acceptance, runner status,
synthesis, physical timing and board validation are distinct. Vendor warnings are classified by actual
file/version/message; do not globally suppress warnings or edit protected IP to silence a model diagnostic.
