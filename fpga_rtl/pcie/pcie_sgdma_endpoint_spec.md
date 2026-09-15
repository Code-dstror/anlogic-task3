# pcie_sgdma_endpoint specification

## Purpose and vendor boundary

This module is the only application-facing boundary for the PH1 PCIe Gen2 x1
hard IP and official SGDMA subsystem. It instantiates the official SGDMA PLL,
the PH1A SGDMA subsystem, one 128-bit C2H channel, one 128-bit H2C channel, and
the AXI4-Lite master interface. `o_c2h_running` is exactly C2H status bit 6.

The 25 MHz board clock is buffered and converted to 125 MHz core and 25 MHz
auxiliary clocks. PERST# resets a power-on delay; PCIe release occurs only after
the PLL lock has remained asserted for the stability counter interval.

```wavejson
{"signal":[{"name":"mperst","wave":"01......"},{"name":"pll_lock","wave":"0.1....."},{"name":"lock_stable","wave":"0...1..."},{"name":"tl_power_on_rst_n","wave":"0...1..."},{"name":"user_rst_n","wave":"0.....1."},{"name":"link_up","wave":"0......1"}]}
```

## Constraints and verification

The target is PH1A90SEG324-2, PCIe Bank83 Lane1, with the hard-IP reference
clock constrained by the official IPC SDC. TD synthesis/place/route proves
vendor wrapper elaboration. ModelSim cannot claim PCIe enumeration without a
Root Complex BFM.
