#ifndef PCIE_PROTOCOL_V1_H
#define PCIE_PROTOCOL_V1_H

/* Generated from doc/pcie_protocol_v1.json. Do not edit by hand. */
#define PCIE_DEVICE_MAGIC       0x33434641u
#define PCIE_FRAME_MAGIC        0x47504A41u
#define PCIE_PROTOCOL_VERSION   1u
#define PCIE_HEADER_LENGTH      64u
#define PCIE_MAX_PAYLOAD        16777216u
#define PCIE_SLOT_COUNT         1u
#define PCIE_USER_BAR_BASE      0x00080000u

#define PCIE_REG_DEVICE_MAGIC         0x000u
#define PCIE_REG_PROTOCOL_VERSION     0x004u
#define PCIE_REG_CAPABILITIES         0x008u
#define PCIE_REG_SLOT_COUNT           0x00Cu
#define PCIE_REG_MAX_PAYLOAD          0x010u
#define PCIE_REG_HEADER_LENGTH        0x014u
#define PCIE_REG_CONTROL              0x018u
#define PCIE_REG_STATUS               0x01Cu
#define PCIE_REG_READY_MASK           0x020u
#define PCIE_REG_SENDING_MASK         0x024u
#define PCIE_REG_PRODUCER_SEQUENCE    0x028u
#define PCIE_REG_CONSUMED_SEQUENCE    0x02Cu
#define PCIE_REG_DROP_COUNT           0x030u
#define PCIE_REG_OVERFLOW_COUNT       0x034u
#define PCIE_REG_DMA_ERROR_COUNT      0x038u
#define PCIE_REG_LAST_ERROR           0x03Cu
#define PCIE_REG_TEST_LENGTH          0x040u
#define PCIE_REG_TEST_PATTERN         0x044u
#define PCIE_REG_TEST_TRIGGER         0x048u
#define PCIE_REG_H2C_BYTE_COUNT       0x050u
#define PCIE_REG_H2C_FRAME_COUNT      0x054u
#define PCIE_REG_H2C_ERROR_COUNT      0x058u
#define PCIE_REG_H2C_FIRST_ERROR      0x05Cu

#define PCIE_CONTROL_APP_ENABLE       (1u << 0)
#define PCIE_CONTROL_SOFT_RESET       (1u << 1)

#define PCIE_STATUS_LINK_UP           (1u << 0)
#define PCIE_STATUS_USER_RESET_RELEASED (1u << 1)
#define PCIE_STATUS_C2H_RUNNING       (1u << 2)
#define PCIE_STATUS_TX_BUSY           (1u << 3)
#define PCIE_STATUS_SOURCE_BUSY       (1u << 4)
#define PCIE_STATUS_FRAME_ERROR       (1u << 5)

#define PCIE_ERROR_NONE               0u
#define PCIE_ERROR_PAYLOAD_LENGTH     1u
#define PCIE_ERROR_PAYLOAD_KEEP       2u
#define PCIE_ERROR_PAYLOAD_LAST       3u
#define PCIE_ERROR_LINK_DOWN          4u
#define PCIE_ERROR_C2H_STOPPED        5u
#define PCIE_ERROR_HEADER_FORMAT      6u
#define PCIE_ERROR_RECOVERY_REQUIRED  7u

#endif
