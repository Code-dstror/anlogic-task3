/* Included after reg_read/reg_write and the c2h_dev definition. */
static struct rkdbg_host debug_host_locked(struct c2h_dev *d)
{
	struct rkdbg_host host = {
		.dead = d->dead, .quarantined = d->quarantine, .running = d->running,
		.stopped = d->stopped, .active = d->active, .ready = d->ready,
		.submitted = d->submitted, .completed = d->completed, .all_slots_free = true,
		.source_reset_allowed = allow_source_reset,
	};
	unsigned int i;
	for (i = 0; i < slots; ++i)
		if (d->buffers[i].state != FREE)
			host.all_slots_free = false;
	return host;
}
static u32 debug_read(void *ctx, u32 offset) { return reg_read(ctx, offset); }
static void debug_write(void *ctx, u32 offset, u32 value) { reg_write(ctx, offset, value); }
static void debug_fault(void *ctx)
{
	struct c2h_dev *d = ctx;
	/* No BME clear/reset/recovery. Idle proof preceded any reset pulse; retain
	 * mappings and block all new commands after an uncertain observation. */
	d->quarantine = true;
	d->running = false;
	wake_up_interruptible(&d->wait);
}
static const struct rkdbg_ops debug_ops = { debug_read, debug_write, debug_fault };

static void debug_cap_locked(struct c2h_dev *d, struct c2h_debug_cap *cap)
{
	struct rkdbg_host host = debug_host_locked(d);
	bool verified_now = rkdbg_observe(&debug_ops, d, &host, &d->debug_reset);
	cap->version = RKDBG_ABI_VERSION;
	cap->user_abi = C2H_USER_ABI;
	cap->capabilities = allow_source_reset ? RKDBG_CAP_SOURCE_RESET : 0;
	cap->reset_state = d->debug_reset.state;
	/* Do not return a cached NEW_BOOT as a fresh idle proof. Keep internal
	 * completion history, so a normal later START is not made pending again. */
	if (cap->reset_state == RKDBG_RESET_NEW_BOOT && !verified_now)
		cap->reset_state = RKDBG_RESET_ISSUED;
	cap->issued_source_session = d->debug_reset.issued_session;
	cap->observed_source_session = d->debug_reset.observed_session;
	cap->reset_requests = d->debug_reset.requests;
}

static int debug_reset_locked(struct c2h_dev *d, const struct c2h_debug_reset *request)
{
	struct rkdbg_host host = debug_host_locked(d);
	enum rkdbg_result result;
	if (request->version != RKDBG_ABI_VERSION || !request->expected_cfg_session ||
	    request->reserved0 || request->reserved1)
		return -EINVAL;
	result = rkdbg_request(&debug_ops, d, &host, &d->debug_reset, request->expected_cfg_session);
	switch (result) {
	case RKDBG_OK: return 0;
	case RKDBG_BUSY: return -EBUSY;
	case RKDBG_STALE: return -ESTALE;
	case RKDBG_REPEAT: return -EALREADY;
	case RKDBG_UNSUPPORTED: return -EOPNOTSUPP;
	default: return -EIO;
	}
}
