/* Additive host-only ioctl extension; existing C2H UAPI2 remains unchanged. */
#ifndef RKDBG_UAPI_H
#define RKDBG_UAPI_H
#include <linux/types.h>
#include <linux/ioctl.h>
#include "debug_constants.h"
struct c2h_debug_cap {
	__u32 version, user_abi, capabilities, reset_state;
	__u32 issued_source_session, observed_source_session, reset_requests, reserved;
};
struct c2h_debug_reset {
	__u32 version, expected_cfg_session, reserved0, reserved1;
};
#define C2H_GET_DEBUG_CAP _IOR('H', 0x46, struct c2h_debug_cap)
#define C2H_SOURCE_RESET _IOW('H', 0x47, struct c2h_debug_reset)
#endif
