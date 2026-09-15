`ifndef PCIE_PROTOCOL_V1_VH
`define PCIE_PROTOCOL_V1_VH

// Generated from doc/pcie_protocol_v1.json. Do not edit by hand.
`define PCIE_DEVICE_MAGIC       32'h33434641
`define PCIE_FRAME_MAGIC        32'h47504A41
`define PCIE_PROTOCOL_VERSION   16'h0001
`define PCIE_HEADER_LENGTH      32'd64
`define PCIE_MAX_PAYLOAD        32'd16777216
`define PCIE_SLOT_COUNT         32'd1
`define PCIE_USER_BAR_BASE      32'h00080000

`define PCIE_REG_DEVICE_MAGIC         12'h000
`define PCIE_REG_PROTOCOL_VERSION     12'h004
`define PCIE_REG_CAPABILITIES         12'h008
`define PCIE_REG_SLOT_COUNT           12'h00C
`define PCIE_REG_MAX_PAYLOAD          12'h010
`define PCIE_REG_HEADER_LENGTH        12'h014
`define PCIE_REG_CONTROL              12'h018
`define PCIE_REG_STATUS               12'h01C
`define PCIE_REG_READY_MASK           12'h020
`define PCIE_REG_SENDING_MASK         12'h024
`define PCIE_REG_PRODUCER_SEQUENCE    12'h028
`define PCIE_REG_CONSUMED_SEQUENCE    12'h02C
`define PCIE_REG_DROP_COUNT           12'h030
`define PCIE_REG_OVERFLOW_COUNT       12'h034
`define PCIE_REG_DMA_ERROR_COUNT      12'h038
`define PCIE_REG_LAST_ERROR           12'h03C
`define PCIE_REG_TEST_LENGTH          12'h040
`define PCIE_REG_TEST_PATTERN         12'h044
`define PCIE_REG_TEST_TRIGGER         12'h048
`define PCIE_REG_H2C_BYTE_COUNT       12'h050
`define PCIE_REG_H2C_FRAME_COUNT      12'h054
`define PCIE_REG_H2C_ERROR_COUNT      12'h058
`define PCIE_REG_H2C_FIRST_ERROR      12'h05C

`define PCIE_CONTROL_APP_ENABLE       0
`define PCIE_CONTROL_SOFT_RESET       1

`define PCIE_STATUS_LINK_UP           0
`define PCIE_STATUS_USER_RESET_RELEASED 1
`define PCIE_STATUS_C2H_RUNNING       2
`define PCIE_STATUS_TX_BUSY           3
`define PCIE_STATUS_SOURCE_BUSY       4
`define PCIE_STATUS_FRAME_ERROR       5

`define PCIE_ERROR_NONE               32'd0
`define PCIE_ERROR_PAYLOAD_LENGTH     32'd1
`define PCIE_ERROR_PAYLOAD_KEEP       32'd2
`define PCIE_ERROR_PAYLOAD_LAST       32'd3
`define PCIE_ERROR_LINK_DOWN          32'd4
`define PCIE_ERROR_C2H_STOPPED        32'd5
`define PCIE_ERROR_HEADER_FORMAT      32'd6
`define PCIE_ERROR_RECOVERY_REQUIRED  32'd7

`endif
