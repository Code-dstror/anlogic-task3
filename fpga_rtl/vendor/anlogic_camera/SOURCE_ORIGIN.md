# Camera reference sources

Target: PH1A90SEG324-2; local TD 6.2.168116.

Sources are taken from the locally supplied MiLianKe reference:
`03_MLK_AFH03_AFC03/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/`
`AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/`.

- `sensor/ui_imx415_reg.v`: unchanged `uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v`.
  Application overrides in `camera/sensor/imx415_mode_table.v` make INCK,
  MIPI lane timing and frame timing a coherent profile. No vendor source edits.
- `clocks/ui_pll.v`: unchanged `al_ip/ui_pll.v`, generated with TD 6.2.178840.
  Registered as a generated Verilog snapshot for compatibility with local
  TD 6.2.168116, like the existing sgdma_pll exception. Uses 100 MHz reference
  and supplies 24 MHz directly, without the reference top's extra /2.
- `phy/`: unchanged PHY, alignment and delay helper files from
  `uisrc/03_ip/mipi_csi_2/`; application protocol/CDC logic is outside this tree.

Camera package locations were cross-checked against the original
`02_peripheral_demo.zip/06_csi_2_dsi_imx415_7cun/uisrc/04_pin/fpga_pin.adc`.
No local reference path is a synthesis dependency. Existing copyright notices
are retained. As requested, this work keeps a concise source record rather
than a per-step hash audit.
