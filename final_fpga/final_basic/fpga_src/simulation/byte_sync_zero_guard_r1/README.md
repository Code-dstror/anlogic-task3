# Byte-sync complete-zero guard A/B

Run from the repository root with the registered local Python and ModelSim:

```powershell
& 'python' -I -B `
  refactor/dual_sdr_lane_r1/src_fpga/simulation/byte_sync_zero_guard_r1/run.py `
  --name guard_312_r2 --modelsim-bin D:/App/modelsim/win64
```

Choose a new run name to preserve completed evidence. Outputs are under the
candidate's `tmp/byte_sync_zero_guard_r1`. The runner uses current candidate
RTL, checks the exact guarded source SHA, derives the old A/B module by
reversing only the seven predicates, and checks that this inverse matches
the fixed baseline SHA. The 312 deterministic cases retain all eight physical
bit phases, missing lane sync, skew and packet-gap boundaries, false preambles,
and the exact eight stable zero-bit boundary. Real RAW10 samples and parser
terminals are checked. There is no electrical PHY or FIFO in this chain.

`packet_fixture.py` contains the original deterministic 31 packet scenarios;
the phase and false-preamble extension follows the fixed 2902 donor experiment.
Read-only hierarchy observations live only in this testbench, so the candidate
retains its compact production parser/serial interface.

The complementary original physical receiver recovery matrix is:

```powershell
& 'python' -I -B `
  refactor/dual_sdr_lane_r1/src_fpga/simulation/runtime_recovery/run_validation.py `
  --source-root C:/fpga_workspace/anlogic-task3/refactor/dual_sdr_lane_r1 `
  --output-root C:/fpga_workspace/anlogic-task3/refactor/dual_sdr_lane_r1/tmp/byte_sync_zero_guard_r1 `
  --name guard_sdr_matrix_r1 --suite matrix --modelsim-bin D:/App/modelsim/win64 `
  --td-root D:/App/TD_Release_2026.2.210.850
```

It exercises the original SDR physical hierarchy and official FIFO after the
byte boundary, with CRC/truncation, reset, finite stalls and later recovery.
The two suites establish complementary digital evidence. Neither proves board
electrical acquisition or complete repair of the intermittent CAM0 line count.
