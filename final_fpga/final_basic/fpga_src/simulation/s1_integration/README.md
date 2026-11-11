> SUPERSEDED 2026-10-31: FPGA dehaze was withdrawn. These assets describe
> the abandoned S1 candidate; do not run them against the final no-dehaze source set.
> Reproduction uses the frozen71734f2f donor; current checks use ../no_dehaze/.

# Actual S1 service plus sparse-lane integration

This candidate merges frozen S1 leaves from71734f2f into the R6 service. It
preserves sparse F23[176:0], lane_read interfaces, native RGB color hints,
quarter p11, LUTRAM winners and the R6 transport. It does not import the S1
donor's retired four-ROI F23 interfaces or PASS results.

```powershell
& 'python' -B refactor/dual_lane_s1/src_fpga/simulation/s1_integration/run.py --name new_joint --joint --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64 --timeout-seconds 1200
```

Use a fresh name. --joint runs two complete1920x1080 frames: first identity
builds real SOURCE/F20-qualified S1 history; second uses frozen S1 G/C. An
independent S1 integer model checks every output RGB/Y group. The frozen C1
model derives the expected quarter p11/Gx/Gy, native4x4 white/yellow hints,
all serialized samples and every sparse candidate word from those pixels.
The real sparse descriptor is held under stall, read, and retired through its
public interfaces. Input sends no intentional bubbles; output finite random
stalls and17-cycle final-beat stalls exercise stable tuples.

The final bounded partial frames enter stereo with a qualified mono history,
check identity output and no HE/S1 collection or use, abort through processing
reset, then return to mono and check identity with cleared history. The service
adds optional STEREO_PASSTHROUGH_ENABLE/i_stereo_passthrough. A mode transition
clears history once; persistent stereo eligibility does not hold S1 admission
in reset. The outer controller must change mode only at a safe frame boundary.

Without --joint, the retained donor-style body exercises four full frames,
partial global reset recovery and public F21 disable; this is an optional new
candidate test, not an inherited qualification. --prepare-only and
--compile-only do not prove functional behavior. All actual reachable source,
model/header, fixture and oracle hashes, commands and logs are saved under
this candidate's tmp/s1_integration/<name>/qualification.json and rechecked at
completion. No force, RAM replacement, source modification, P&R or board work
is part of this test. It does not qualify complete JPEG or dual-camera capture;
those have independent candidate checks.
