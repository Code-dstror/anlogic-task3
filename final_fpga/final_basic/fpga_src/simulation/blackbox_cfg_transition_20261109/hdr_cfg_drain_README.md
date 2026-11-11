# HDR drain and re-entry short test

The bench uses the public [HDR drain contract](../../../docs/fieldfix_20261109/HDR_DRAIN_PUBLIC.md)
and the maintainers' opaque carrier. ModelSim runs the real gate, paired capture
configuration owner and TD control FIFOs. The baseline replaces only the gate
with the board-source copy identified by the contract.

The fixture uses independent 10 ns PIX and 14 ns DFI clocks. It retires the BOOT
and HDR ACKs and transfers one RAW4 per HDR member. An ingress becomes busy on
its accepted RAW4 and releases ownership on its SOURCE handshake. Admission
closes before true FE. LONG SOURCE retires while SHORT SOURCE stays held for
at least 20 PIX cycles. The bench checks the RAW4 payloads, old epoch, member
sequences and held SOURCE payload.

Each old RAW4 adds a transport item on its actual beat. The model holds both
items before DFI consumption, then holds write responses across the first part
of a 256-group rejected traffic train. The two lanes start on different PIX
edges and advance their sequences in order. The bench counts actual handshakes
and checks that rejected tokens create neither RAW nor SOURCE. It samples HDR
quiet every PIX edge during the train and requires the exact positive dehaze
ACK while traffic is arriving. The bench records any drain fault through the
end of this observation and fails on it.

The ACK sink holds each offer for at least six PIX cycles and checks the entire
tuple and the applied configuration during the hold. After dehaze ACK
retirement, the HDR branch is reset across a new HDR CONFIG and released with
admission closed. Both members of the first pair after release must reach
SOURCE in the new HDR epoch. The fixture models ingress, write responses and
the sensor clock handoff. Sensor timing, physical DDR transactions and host
APPLIED are outside its scope.

## Run

Use a fresh ID for each attempt from the repository root.

~~~powershell
$hdrRunner = 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_cfg_transition_20261109/hdr_cfg_drain_run.ps1'
pwsh -NoProfile -File $hdrRunner -Variant baseline -ModelSimBin 'D:/App/modelsim/win64' -TdRoot 'D:/App/TD_Release_2026.2.210.850' -RunId probe1
pwsh -NoProfile -File $hdrRunner -Variant candidate -ModelSimBin 'D:/App/modelsim/win64' -TdRoot 'D:/App/TD_Release_2026.2.210.850' -RunId probe1
~~~

Each attempt gets fresh ModelSim libraries and logs under
`refactor/camera_raw_r2/tmp/blackbox_hdr_cfg_drain_20261109`. Its `evidence.json`
records argv, the ModelSim version, exact input SHA-256 values and the terminal
status. The runner gives ModelSim a shared 55 s wall budget. The bench has a
100 µs simulation watchdog. Exit 0 means PASS, exit 1 preserves the classified
test FAIL, and exit 2 means the tool or evidence was blocked.

## Recorded attempts

- `baseline-r1`, `baseline-r2` and `candidate-r2` stopped at initial FS. The
  fixture had marked the external ingresses busy before any RAW4 ownership.
  The public contract now specifies that idle grants eligibility for a new FS.
- `baseline-r3` completed the legal old pair and saw the PIX SOURCE drain
  fault at 2.255 µs, 20 ns after the first rejected FS. `candidate-r3` passed.
- `baseline-r4` failed with `DUT_REJECTED_TRAFFIC_BLOCKS_CONFIG` at 26.600 µs.
  Both old SOURCE terminals retired, both transport items were consumed, and
  write quiet asserted at 2.828 µs. The gate accepted 768 rejected tokens per
  lane. HDR quiet was low in 738 of 1,477 PIX cycles after modeled debt cleared.
  The CONFIG owner remained busy at epoch 1 after another 900 PIX cycles
  without input traffic.
- `candidate-r4` passed at 18.710 µs with the same fixture and model inputs.
  HDR quiet stayed high across all rejected traffic. The dehaze ACK retired
  at 3.125 µs after seven held PIX cycles. After branch reset, both HDR
  terminals retired successfully at epoch 3 with sequences 1257 and 9257.
