# No-dehaze shared processing qualification

Run from the repository root with a fresh name:

```powershell
& 'python' -B refactor/dual_lane_s1/src_fpga/simulation/no_dehaze/run.py --name new_no_dehaze --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

The actual service has no dehaze estimator, gain table, restore pipeline,
private descriptor, map owner or pin. Accepted original RGB/Y now passes
directly through the existing gray queue into Gray/color Gaussian/F22/C1/HE.
The old service/module names and constant legacy status ports are compatibility
only. All streams use PIX clock, four RGB8 pixels and Y8 per lane; 480 accepted
beats form a line and 1080 lines form a frame. Transfers advance on valid and
ready. SOURCE[0] remains authenticated HE; the deleted SOURCE[1] cannot own or
block work. The neutral observer remains passive and produces its original
statistics record, without a dehaze F20 consumer.

Two complete HD frames keep Gray, alpha-half color Gaussian, qualified HE,
F22 and sparse C1 enabled. Independent NumPy/OpenCV equations derive the
filtered grayscale frame, then the exact previous-frame CDF mapping and HE's
clamped +/-32 reconstruction. The second frame must use real SOURCE-qualified
history. Every output RGB/Y group is compared. The frozen C1 model derives
quarter p11/Gx/Gy/native4x4 white/yellow hints and every packed candidate from
the original native RGB; these remain independent of output Gray/HE selection.
Neutral statistics, all serialized samples, descriptor identity/hold/readout,
finite random stalls and final-beat stalls are checked as well.

The runner asserts that the actual compilation closure contains no dehaze,
light_haze, gain or restore source. Real recursively included headers, RTL,
official models, numerical models and generated fixtures are hashed before
and after execution. Each child is bounded to 600 seconds; outputs are under
`tmp/no_dehaze/<name>`. This does not run synthesis, P&R, bit generation or
board work. Superseded S1 results remain under their historical evidence path.
