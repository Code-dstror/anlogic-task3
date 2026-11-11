/* Actual production helper shared with host fault tests. */
#ifndef RKDBG_RESET_GUARD_H
#define RKDBG_RESET_GUARD_H
#include "debug_constants.h"
#include "pcie_protocol_v1.h"
#include "c2h_hw_abi.h"

enum rkdbg_result { RKDBG_OK, RKDBG_BUSY, RKDBG_STALE, RKDBG_REPEAT, RKDBG_FAULT, RKDBG_UNSUPPORTED };
struct rkdbg_state { u32 state, issued_session, observed_session, requests; };
struct rkdbg_host {
	bool dead, quarantined, running, stopped, all_slots_free, source_reset_allowed;
	int active;
	u32 ready;
	unsigned long long submitted, completed;
};
struct rkdbg_ops {
	u32 (*read)(void *ctx, u32 offset);
	void (*write)(void *ctx, u32 offset, u32 value);
	void (*fault)(void *ctx); /* software quarantine only; never PCI config/BME */
};
struct rkdbg_sample { u32 session, cfg_status, app_status, control, native_status; };

static inline bool rkdbg_host_idle(const struct rkdbg_host *h)
{
	return !h->dead && !h->quarantined && !h->running && h->stopped &&
		h->active == -1 && !h->ready && h->all_slots_free && h->submitted == h->completed;
}

static inline bool rkdbg_read(const struct rkdbg_ops *ops, void *ctx, struct rkdbg_sample *s)
{
	u32 algo, record, magic, cfg_magic, command_error, cfg_error, active_session;
	u32 ready_mask, sending_mask;
	magic = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_DEVICE_MAGIC);
	cfg_magic = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_CFG_MAGIC);
	s->control = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_CONTROL);
	s->app_status = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_STATUS);
	s->session = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_CFG_SESSION);
	s->cfg_status = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_CFG_STATUS);
	cfg_error = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_CFG_ERROR);
	active_session = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_CFG_ACTIVE_SESSION);
	algo = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_ALGO_STATUS);
	record = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_RECORD_STATUS);
	ready_mask = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_READY_MASK);
	sending_mask = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_SENDING_MASK);
	s->native_status = ops->read(ctx, C2H_R_STATUS);
	command_error = ops->read(ctx, C2H_R_COMMAND_ERROR);
	if (magic != PCIE_DEVICE_MAGIC || cfg_magic != PCIE_CFG_MAGIC || s->control == ~0U ||
	    s->app_status == ~0U || s->cfg_status == ~0U ||
	    algo == ~0U || record == ~0U || ready_mask == ~0U || sending_mask == ~0U ||
	    cfg_error == ~0U || s->native_status == ~0U || command_error == ~0U)
		return false;
	/* Keep busy/error as a known refusal, not a fabricated unreachable read. */
	if ((algo & (PCIE_ALGO_STATUS_BUSY | PCIE_ALGO_STATUS_LOADING | PCIE_ALGO_STATUS_ERROR)) ||
	    (record & (PCIE_RECORD_V2_STATUS_BUSY | PCIE_RECORD_V2_STATUS_ERROR)) || command_error ||
	    cfg_error || active_session != s->session || ready_mask || sending_mask)
		s->cfg_status |= PCIE_CFG_STATUS_BUSY;
	/* SOURCE_BUSY excludes already READY JPEGs; masks do not prove global quiet. */
	return true;
}

static inline bool rkdbg_hw_idle(const struct rkdbg_sample *s, bool completion)
{
	u32 required = PCIE_STATUS_LINK_UP | PCIE_STATUS_USER_RESET_RELEASED;
	u32 forbidden = PCIE_STATUS_C2H_RUNNING | PCIE_STATUS_TX_BUSY |
		PCIE_STATUS_SOURCE_BUSY | PCIE_STATUS_FRAME_ERROR;
	if (completion)
		required |= PCIE_STATUS_SESSION_REARM_READY;
	return s->control == 0 && s->session != 0 &&
		(s->app_status & required) == required && !(s->app_status & forbidden) &&
		(s->cfg_status & PCIE_CFG_STATUS_SESSION_READY) &&
		!(s->cfg_status & (PCIE_CFG_STATUS_BUSY | PCIE_CFG_STATUS_READY | PCIE_CFG_STATUS_ERROR)) &&
		(s->native_status & (C2H_ST_LINK_UP | C2H_ST_BME | C2H_ST_STOPPED)) ==
		(C2H_ST_LINK_UP | C2H_ST_BME | C2H_ST_STOPPED) &&
		!(s->native_status & (C2H_ST_OWNED | C2H_ST_SAFE_RESULT | C2H_ST_QUARANTINE | C2H_ST_RECORD_BOUND));
}

static inline void rkdbg_fault(const struct rkdbg_ops *ops, void *ctx, struct rkdbg_state *s)
{
	s->state = RKDBG_RESET_UNCERTAIN;
	ops->fault(ctx);
}

static inline enum rkdbg_result rkdbg_request(const struct rkdbg_ops *ops, void *ctx,
		const struct rkdbg_host *host, struct rkdbg_state *state, u32 expected)
{
	struct rkdbg_sample a, b;
	u32 control, magic;
	if (!host->source_reset_allowed)
		return RKDBG_UNSUPPORTED;
	if (host->dead || host->quarantined || state->state == RKDBG_RESET_UNCERTAIN)
		return RKDBG_FAULT;
	if (!expected || state->issued_session == expected || state->requests == ~0U)
		return RKDBG_REPEAT;
	if (state->state == RKDBG_RESET_ISSUED || !rkdbg_host_idle(host))
		return RKDBG_BUSY;
	if (!rkdbg_read(ops, ctx, &a) || !rkdbg_read(ops, ctx, &b)) {
		rkdbg_fault(ops, ctx, state);
		return RKDBG_FAULT;
	}
	if (a.session != expected || b.session != expected)
		return RKDBG_STALE;
	if (!rkdbg_hw_idle(&a, false) || !rkdbg_hw_idle(&b, false))
		return RKDBG_BUSY;
	/* Linearization before the ONLY write: uncertainty consumes this attempt. */
	state->issued_session = expected;
	state->observed_session = expected;
	state->requests++;
	state->state = RKDBG_RESET_ISSUED;
	ops->write(ctx, PCIE_USER_BAR_BASE + PCIE_REG_CONTROL, PCIE_CONTROL_SOFT_RESET);
	/* CONTROL reads APP only; SOFT_RESET is a pulse, not a readable completion. */
	control = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_CONTROL);
	magic = ops->read(ctx, PCIE_USER_BAR_BASE + PCIE_REG_DEVICE_MAGIC);
	if (control != 0 || magic != PCIE_DEVICE_MAGIC) {
		rkdbg_fault(ops, ctx, state);
		return RKDBG_FAULT;
	}
	return RKDBG_OK; /* issued only; never completion */
}

static inline bool rkdbg_observe(const struct rkdbg_ops *ops, void *ctx,
		const struct rkdbg_host *host, struct rkdbg_state *state)
{
	struct rkdbg_sample a, b;
	if (state->state != RKDBG_RESET_ISSUED && state->state != RKDBG_RESET_NEW_BOOT)
		return false;
	if (host->dead || host->quarantined) {
		state->state = RKDBG_RESET_UNCERTAIN;
		return false;
	}
	if (!rkdbg_host_idle(host))
		return false;
	if (!rkdbg_read(ops, ctx, &a) || !rkdbg_read(ops, ctx, &b)) {
		rkdbg_fault(ops, ctx, state);
		return false;
	}
	if (rkdbg_host_idle(host) && rkdbg_hw_idle(&a, true) && rkdbg_hw_idle(&b, true) &&
	    a.session == b.session && a.session != state->issued_session) {
		if (state->state == RKDBG_RESET_NEW_BOOT && a.session != state->observed_session) {
			rkdbg_fault(ops, ctx, state);
			return false;
		}
		state->observed_session = a.session;
		state->state = RKDBG_RESET_NEW_BOOT;
		return true;
	}
	return false;
}
#endif
