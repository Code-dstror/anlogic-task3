/* SPDX-License-Identifier: GPL-2.0 */
#ifndef C2H_LIFECYCLE_H
#define C2H_LIFECYCLE_H
enum c2h_read_action {
	C2H_READ_WAIT, C2H_READ_DATA, C2H_READ_EOF, C2H_READ_ERROR
};

/* Shared by read() and its advisory wait predicate. Callers recheck under
 * the device mutex before acting. Faults outrank READY and normal STOP EOF.
 * -1 is the sole known no-active-descriptor value; unknown state is not EOF.
 */
static inline enum c2h_read_action c2h_read_action_for(bool dead, bool quarantined,
		bool running, bool stopped, int active, unsigned int ready,
		unsigned long long submitted, unsigned long long completed)
{
	if (dead || quarantined || active < -1 || completed > submitted)
		return C2H_READ_ERROR;
	if (ready)
		return C2H_READ_DATA;
	if (!running && stopped && active == -1 && submitted == completed)
		return C2H_READ_EOF;
	return C2H_READ_WAIT;
}

/* pci_name() supplies the canonical full BDF; no partial/default matching. */
static inline bool c2h_target_matches(const char *target, const char *pci_name)
{
	if (!target || !pci_name || !*target)
		return false;
	while (*target && *target == *pci_name) {
		target++;
		pci_name++;
	}
	return !*target && !*pci_name;
}

/* Lock-held ordering shared by the driver and the host C fault harness.
 * Callers retain all DMA ownership on false; no rollback/reset is safe.
 * u32/bool and generated hardware/legacy constants come from the caller.
 */
struct c2h_lifecycle_ops {
	u32 (*read)(void *ctx, u32 reg);
	void (*write)(void *ctx, u32 reg, u32 value);
	bool (*valid)(void *ctx, u32 status);
	void (*fault)(void *ctx, const char *why);
};

static inline bool c2h_app_write(const struct c2h_lifecycle_ops *ops,
		void *ctx, u32 value)
{
	u32 control;
	if (ops->read(ctx, C2H_LEGACY_BASE) != C2H_LEGACY_MAGIC)
		goto fail;
	control = ops->read(ctx, C2H_LEGACY_BASE + C2H_LEGACY_CONTROL);
	if (control & ~C2H_LEGACY_APP_ENABLE)
		goto fail;
	/* Literal APP-only writes: never echo SOFT_RESET or unknown bits. */
	ops->write(ctx, C2H_LEGACY_BASE + C2H_LEGACY_CONTROL, value);
	if (ops->read(ctx, C2H_LEGACY_BASE + C2H_LEGACY_CONTROL) != value ||
	    ops->read(ctx, C2H_LEGACY_BASE) != C2H_LEGACY_MAGIC)
		goto fail;
	return true;
fail:
	ops->fault(ctx, "APP control unavailable or readback unconfirmed");
	return false;
}

static inline bool c2h_lifecycle_start(const struct c2h_lifecycle_ops *ops,
		void *ctx)
{
	u32 status;
	/* A non-running owner cannot adopt an externally enabled source. */
	if (ops->read(ctx, C2H_LEGACY_BASE) != C2H_LEGACY_MAGIC ||
	    ops->read(ctx, C2H_LEGACY_BASE + C2H_LEGACY_CONTROL) != 0) {
		ops->fault(ctx, "APP not disabled before RESUME");
		return false;
	}
	ops->write(ctx, C2H_R_CONTROL, C2H_CMD_RESUME);
	status = ops->read(ctx, C2H_R_STATUS);
	if (!ops->valid(ctx, status) || ops->read(ctx, C2H_R_COMMAND_ERROR) ||
	    (status & (C2H_ST_OWNED | C2H_ST_STOPPED | C2H_ST_SAFE_RESULT))) {
		ops->fault(ctx, "RESUME failed");
		return false;
	}
	return c2h_app_write(ops, ctx, C2H_LEGACY_APP_ENABLE);
}

static inline bool c2h_lifecycle_stop(const struct c2h_lifecycle_ops *ops,
		void *ctx, u32 *status)
{
	if (!c2h_app_write(ops, ctx, 0))
		return false;
	ops->write(ctx, C2H_R_CONTROL, C2H_CMD_STOP);
	*status = ops->read(ctx, C2H_R_STATUS);
	if (!ops->valid(ctx, *status) || ops->read(ctx, C2H_R_COMMAND_ERROR)) {
		ops->fault(ctx, "STOP failed");
		return false;
	}
	/* STOP may still own a descriptor: existing fence/ACK harvest must drain. */
	return true;
}
#endif
