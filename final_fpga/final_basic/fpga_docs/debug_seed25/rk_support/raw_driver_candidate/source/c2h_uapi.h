/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
#ifndef C2H_CANDIDATE_UAPI_H
#define C2H_CANDIDATE_UAPI_H
#include <linux/types.h>
#include <linux/ioctl.h>

/* PRIVATE candidate, unrelated to the released stream_diag ioctl ABI. */
#define C2H_USER_ABI 2
#define C2H_BATCH_MAX 16
#define C2H_OWNER_INFO_VERSION 1
/* Additive host-private identity; no FPGA register or GET_INFO layout change. */
struct c2h_owner_info {
	__u32 owner_info_version, user_abi, pci_domain, pci_bus, pci_devfn, generation;
	__u64 transport_session;
};
struct c2h_info {
	__u32 user_abi, slots, capacity, running;
	__u32 quarantined, stopped, dma_bits, mapping_bytes;
	__u64 status_polls, interrupts, submitted, completed;
};
struct c2h_completion {
	__u32 slot, generation, result, bytes;
	__u32 record_identity[4];
};
struct c2h_lease {
	__u32 slot, generation;
};
struct c2h_release_batch {
	__u32 count, reserved;
	struct c2h_lease leases[C2H_BATCH_MAX];
};
struct c2h_legacy_op {
	__u32 offset, value, write, reserved;
};
struct c2h_legacy_batch {
	__u32 count, reserved;
	struct c2h_legacy_op ops[C2H_BATCH_MAX];
};
#define C2H_GET_INFO _IOR('H', 0x40, struct c2h_info)
#define C2H_START _IO('H', 0x41)
#define C2H_STOP _IO('H', 0x42)
#define C2H_RELEASE _IOW('H', 0x43, struct c2h_release_batch)
#define C2H_LEGACY _IOWR('H', 0x44, struct c2h_legacy_batch)
#define C2H_GET_OWNER _IOR('H', 0x45, struct c2h_owner_info)
#endif
