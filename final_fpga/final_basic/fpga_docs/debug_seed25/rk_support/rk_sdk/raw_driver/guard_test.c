/* Host-only compile and execution of the exact patched C2H_LEGACY preflight. */
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>

typedef uint32_t u32;
#include "c2h_legacy_policy.h"

enum { REQUEST_PRODUCT = 0xfa8, ACTIVE_PRODUCT = 0xfac };

struct c2h_legacy_op {
	u32 offset, value, write, reserved;
};

struct c2h_dev {
	bool running;
	int active;
	u32 control, status, stereo_status;
};

static u32 reg_read(struct c2h_dev *d, u32 offset)
{
	switch (offset - C2H_LEGACY_BASE) {
	case C2H_LEGACY_CONTROL:
		return d->control;
	case 0x1c:
		return d->status;
	case 0xf94:
		return d->stereo_status;
	default:
		assert(false);
		return 0;
	}
}

static int validate(struct c2h_dev *d, struct c2h_legacy_op *ops, unsigned int count)
{
	struct {
		struct c2h_legacy_op *ops;
		unsigned int count;
	} legacy = {ops, count};
	unsigned int i;
	int ret;

#include "kernel_preflight.inc"
	return 0;
out:
	return ret;
}

static int op(struct c2h_dev *d, u32 offset, u32 value, u32 write)
{
	struct c2h_legacy_op request = {offset, value, write, 0};

	return validate(d, &request, 1);
}

int main(void)
{
	struct c2h_dev idle = {.active = -1};
	struct c2h_dev hot[] = {
		{.active = -1, .running = true}, {.active = 0},
		{.active = -1, .control = C2H_LEGACY_APP_ENABLE},
		{.active = -1, .status = 1U << 2}, {.active = -1, .status = 1U << 3},
		{.active = -1, .status = 1U << 4}, {.active = -1, .status = 1U << 7},
		{.active = -1, .stereo_status = 1U << 2},
	};
	struct c2h_legacy_op rejected_batch[] = {{REQUEST_PRODUCT, 1, 1, 0}, {0xf8c, 0, 1, 0}};

	assert(op(&idle, REQUEST_PRODUCT, 0, 1) == 0);
	assert(op(&idle, REQUEST_PRODUCT, 1, 1) == 0);
	assert(op(&idle, REQUEST_PRODUCT, 2, 1) == -EPERM);
	assert(op(&idle, REQUEST_PRODUCT, UINT32_MAX, 1) == -EPERM);
	assert(op(&idle, REQUEST_PRODUCT + 1, 1, 1) == -EPERM);
	assert(op(&idle, REQUEST_PRODUCT, 1, 2) == -EPERM);
	assert(op(&idle, ACTIVE_PRODUCT, 1, 1) == -EPERM);
	assert(op(&idle, 0xfb0, 0, 0) == -EPERM);
	assert(op(&idle, 0xf8c, 1, 1) == 0 && op(&idle, 0xf8c, 0, 1) == -EPERM);
	assert(op(&idle, 0xf90, 1, 1) == 0 && op(&idle, 0xf90, 0, 1) == -EPERM);
	assert(op(&idle, 0xfa0, 2, 1) == 0 && op(&idle, 0xfa0, 1, 1) == -EPERM);
	assert(op(&idle, C2H_LEGACY_CONTROL, 1, 1) == -EPERM);
	assert(validate(&idle, rejected_batch, 2) == -EPERM);
	for (unsigned int i = 0; i < sizeof(hot) / sizeof(hot[0]); ++i) {
		assert(op(&hot[i], REQUEST_PRODUCT, 1, 1) == -EBUSY);
		assert(op(&hot[i], REQUEST_PRODUCT, 0, 0) == 0);
		assert(op(&hot[i], ACTIVE_PRODUCT, 0, 0) == 0);
	}
	return 0;
}
