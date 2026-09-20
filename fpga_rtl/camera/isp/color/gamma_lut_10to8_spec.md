# `gamma_lut_10to8` specification

The module maps a 10-bit input code to an 8-bit output using a 1024×8 PH1 ERAM initialized by `gamma22_10to8.dath`. The table encodes `round(255*(index/1023)^(1/2.2))`. With `C_GAMMA_LINEAR_BYPASS=1`, the registered output is the truncating linear conversion `index[9:2]` used by the color pipeline. Both modes have one clock of latency, preventing bypass-mode data from overtaking valid and marker pipelines.

`i_rstn` is active-low. The PH1 memory is synchronous; callers must align valid with the registered result. The initialization file must be resolved by both ModelSim and TD batch flows.

Timing diagram: [gamma_lut_lookup.json](../waveforms/gamma_lut_lookup.json).
