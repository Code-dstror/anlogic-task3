# Anlogic PCIe/SGDMA vendor source snapshot

- Source project: `03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1`
- Source TD generator version for PCIe/PLL: `6.2.178840`
- Target: `PH1A90SEG324-2`, PCIe Gen2 x1, Bank83 Lane1
- Imported on: `2026-09-14`

Only the PH1A branch used by `sgdma_subsys` is retained. The vendor files are
byte-for-byte copies and must not be edited locally. Application RTL from
`sgdma_app` is intentionally excluded.

The PCIe generator emits `PH1_LOGIC_PCIE.txt/.dat`, while its generated Verilog
loads the same byte content under the fixed names `al_pcie_ip.txt/.dat`. Both
names are retained so the TD synthesis run can resolve the configuration files
from the copied vendor directory.

The following identically named but incompatible sources are explicitly
excluded: `sgdma/pcie_bridge/bridge_v1_ph1/al_pcie_if/ip/ph1a90_pcie/*` from
the official tree. That subtree targets `PH1A90SBG484`, Gen3 x4 and defines a
conflicting `al_pcie_ip` module. The only allowed PCIe IP registration is
`al_ip/PH1_LOGIC_PCIE.ipc` in this snapshot.

`SHA256SUMS.txt` records the imported byte content. Regenerate it only when the
upstream vendor baseline is deliberately updated and review the diff.
