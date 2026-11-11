# TD GitHub smoke project

One toggling register for PH1A90SEG324-2, TD 2026.2 (6.2.3.210850).
The registered `td_smoke` project uses one seed and one requested thread.
Changing its four watched input files triggers one independent native full build
through `server/td/projects.json`; documentation changes alone do not.

The test covers project-push detection, resource admission, synthesis, placement,
routing, bitgen, native report generation/reopening and artifact download.
It does not validate production HDR/JPEG timing, multi-seed scheduling,
checkpoint continuation, complete warning retention or overnight reconnection.
Native phase logs can still be overwritten in the deployed v2 controller.

The ADC is a compile-only pin assignment reused from the local tiny TD probe;
it is not a reviewed board connection map. Do not program this bitstream onto
hardware. The SDC constrains the test clock, not a board-level I/O interface.
No IP or production sources are used. Results belong to each server job's own
AL and Runs, never the manual HDR/JPEG GUI directory.

To stop watching this example, set its `enabled` field to `false` in
`server/td/projects.json`. Existing jobs and artifacts are not deleted.
