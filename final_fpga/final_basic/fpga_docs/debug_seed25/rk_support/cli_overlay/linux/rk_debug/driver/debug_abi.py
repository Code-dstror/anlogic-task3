"""Generated from debug_constants.h and c2h_debug_uapi.h; host-only."""
RKDBG_ABI_VERSION = 1
RKDBG_CAP_SOURCE_RESET = 1
RKDBG_RESET_NONE = 0
RKDBG_RESET_ISSUED = 1
RKDBG_RESET_NEW_BOOT = 2
RKDBG_RESET_UNCERTAIN = 3
C2H_GET_DEBUG_CAP = 0x80204846
C2H_GET_DEBUG_CAP_FORMAT = '=8I'
C2H_GET_DEBUG_CAP_FIELDS = ('version', 'user_abi', 'capabilities', 'reset_state', 'issued_source_session', 'observed_source_session', 'reset_requests', 'reserved')
C2H_SOURCE_RESET = 0x40104847
C2H_SOURCE_RESET_FORMAT = '=4I'
C2H_SOURCE_RESET_FIELDS = ('version', 'expected_cfg_session', 'reserved0', 'reserved1')
