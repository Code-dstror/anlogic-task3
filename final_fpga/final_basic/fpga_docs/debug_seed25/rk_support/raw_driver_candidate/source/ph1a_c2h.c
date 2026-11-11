// SPDX-License-Identifier: GPL-2.0
/* Isolated candidate: never bind to a released SGDMA image. */
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/dma-mapping.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <linux/poll.h>
#include <linux/uaccess.h>
#include <linux/workqueue.h>
#include <linux/random.h>
#include <linux/kref.h>
#include <linux/interrupt.h>
#include <linux/delay.h>
#include <linux/compat.h>
#include "c2h_uapi.h"
#include "c2h_hw_abi.h"
#include "c2h_legacy_policy.h"
#include "c2h_lifecycle.h"

static unsigned int slots = 4, capacity = C2H_MAX_RECORD_BYTES;
static unsigned int poll_ms = 1, drain_ms = 2000, dma_bits = 64;
static bool irq_hint;
static char *target_bdf;
module_param(slots, uint, 0444);
module_param(capacity, uint, 0444);
module_param(poll_ms, uint, 0444);
module_param(drain_ms, uint, 0444);
module_param(dma_bits, uint, 0444);
module_param(irq_hint, bool, 0444);
module_param(target_bdf, charp, 0444);
MODULE_PARM_DESC(target_bdf, "Required exact canonical BDF (dddd:bb:ss.f); no implicit target");
MODULE_PARM_DESC(drain_ms, "Host close/remove patience only; expiry quarantines, never frees DMA");
MODULE_PARM_DESC(irq_hint, "Enable only with qualified frame-result MSI vector 0 image");

enum slot_state { FREE, ACTIVE, READY, LEASED };
struct c2h_slot {
	void *cpu;
	dma_addr_t dma;
	enum slot_state state;
	struct c2h_completion completion;
};
struct c2h_dev {
	struct pci_dev *pdev;
	void __iomem *bar;
	struct miscdevice misc;
	struct mutex lock;
	struct kref refs;
	struct delayed_work work;
	wait_queue_head_t wait;
	struct c2h_slot buffers[C2H_BATCH_MAX];
	__le32 *fence;
	dma_addr_t fence_dma;
	u32 session[2], generation, identity[4];
	u32 pci_domain, pci_bus, pci_devfn;
	size_t allocation_bytes;
	int active;
	unsigned int ready;
	bool opened, running, quarantine, dead, stopped, irq, online;
	u64 polls, submitted, completed;
	atomic64_t interrupts;
};

static u32 reg_read(struct c2h_dev *d, u32 reg)
{
	return readl(d->bar + reg);
}

static void reg_write(struct c2h_dev *d, u32 reg, u32 value)
{
	writel(value, d->bar + reg);
}

static u32 command(struct c2h_dev *d, u32 cmd)
{
	reg_write(d, C2H_R_CONTROL, cmd);
	/* Flush posted control; this read is not the payload DMA fence. */
	return reg_read(d, C2H_R_STATUS);
}

static void quarantine(struct c2h_dev *d, const char *why)
{
	if (!d->quarantine) {
		dev_err(&d->pdev->dev, "DMA quarantined: %s; mappings retained until platform recovery\n", why);
		/* Contain further requests, never treat this as a posted-write drain. */
		pci_clear_master(d->pdev);
	}
	d->quarantine = true;
	d->running = false;
	wake_up_interruptible(&d->wait);
}

static bool valid_status(struct c2h_dev *d, u32 status)
{
	if (status == ~0U || (status & C2H_ST_QUARANTINE)) {
		quarantine(d, "unreachable BAR or endpoint quarantine");
		return false;
	}
	if (!(status & C2H_ST_LINK_UP) || !(status & C2H_ST_BME)) {
		quarantine(d, "link or bus mastering lost");
		return false;
	}
	d->stopped = !!(status & C2H_ST_STOPPED);
	return true;
}

static u32 lifecycle_read(void *ctx, u32 reg)
{
	return reg_read(ctx, reg);
}

static void lifecycle_write(void *ctx, u32 reg, u32 value)
{
	reg_write(ctx, reg, value);
}

static bool lifecycle_valid(void *ctx, u32 status)
{
	return valid_status(ctx, status);
}

static void lifecycle_fault(void *ctx, const char *why)
{
	quarantine(ctx, why);
}

static const struct c2h_lifecycle_ops lifecycle_ops = {
	.read = lifecycle_read, .write = lifecycle_write,
	.valid = lifecycle_valid, .fault = lifecycle_fault,
};

static void write_identity(struct c2h_dev *d)
{
	unsigned int i;
	for (i = 0; i < 4; ++i)
		reg_write(d, C2H_R_IDENTITY_WORD0 + 4 * i, d->identity[i]);
}

/* lock held. OWNED remains set until the matching safe ACK is confirmed. */
static void harvest(struct c2h_dev *d, u32 status)
{
	struct c2h_slot *slot;
	u32 code, emitted, length;
	unsigned int i;
	if (d->active < 0) {
		if (status & (C2H_ST_OWNED | C2H_ST_SAFE_RESULT))
			quarantine(d, "unexpected hardware owner");
		return;
	}
	if (!(status & C2H_ST_OWNED)) {
		quarantine(d, "hardware ownership disappeared");
		return;
	}
	if (!(status & C2H_ST_SAFE_RESULT))
		return;
	for (i = 0; i < 4; ++i) {
		if (reg_read(d, C2H_R_ACTIVE_IDENTITY_WORD0 + 4 * i) != d->identity[i]) {
			quarantine(d, "stale completion identity");
			return;
		}
	}
	code = reg_read(d, C2H_R_RESULT_CODE);
	emitted = reg_read(d, C2H_R_LOCAL_EMITTED_BYTES);
	length = reg_read(d, C2H_R_BOUND_RECORD_LENGTH);
	/* Codes 4/5 must never be advertised as safe by the endpoint. */
	if ((code != C2H_RESULT_COMPLETE && code != C2H_RESULT_CANCELLED &&
	     code != C2H_RESULT_INPUT_ERROR && code != C2H_RESULT_CAPACITY_LENGTH &&
	     code != C2H_RESULT_SOURCE_ABORT) || emitted > capacity ||
	    (code == C2H_RESULT_COMPLETE && (!length || length != emitted || length > capacity))) {
		quarantine(d, "invalid safe result or length");
		return;
	}
	slot = &d->buffers[d->active];
	for (i = 0; i < 4; ++i)
		slot->completion.record_identity[i] = reg_read(d, C2H_R_RECORD_IDENTITY_WORD0 + i * 4);
	/* Non-relaxed STATUS observed the endpoint's successful MRd fence. */
	dma_rmb();
	write_identity(d);
	status = command(d, C2H_CMD_ACK);
	if (!valid_status(d, status) || reg_read(d, C2H_R_COMMAND_ERROR) ||
	    (status & (C2H_ST_OWNED | C2H_ST_SAFE_RESULT))) {
		quarantine(d, "safe ACK was not confirmed");
		return;
	}
	slot->completion.result = code;
	slot->completion.bytes = code == C2H_RESULT_COMPLETE ? emitted : 0;
	slot->state = READY;
	d->ready++;
	d->active = -1;
	d->completed++;
	wake_up_interruptible(&d->wait);
}

static void submit_free(struct c2h_dev *d)
{
	struct c2h_slot *slot = NULL;
	u32 status, cookie;
	unsigned int i;
	if (!d->running || d->quarantine || d->active >= 0)
		return;
	for (i = 0; i < slots; ++i) {
		if (d->buffers[i].state == FREE) {
			slot = &d->buffers[i];
			break;
		}
	}
	if (!slot)
		return; /* All buffers leased: hardware source backpressure, no overwrite. */
	if (d->generation == U32_MAX) {
		quarantine(d, "generation exhausted; coordinated reset required");
		return;
	}
	d->identity[0] = i;
	d->identity[1] = ++d->generation;
	d->identity[2] = d->session[0];
	d->identity[3] = d->session[1];
	cookie = d->generation ^ d->session[0] ^ d->session[1];
	WRITE_ONCE(*d->fence, cpu_to_le32(cookie));
	dma_wmb();
	reg_write(d, C2H_R_DMA_ADDRESS_LOW, lower_32_bits(slot->dma));
	reg_write(d, C2H_R_DMA_ADDRESS_HIGH, upper_32_bits(slot->dma));
	reg_write(d, C2H_R_CAPACITY_BYTES, capacity);
	write_identity(d);
	reg_write(d, C2H_R_FENCE_ADDRESS_LOW, lower_32_bits(d->fence_dma));
	reg_write(d, C2H_R_FENCE_ADDRESS_HIGH, upper_32_bits(d->fence_dma));
	reg_write(d, C2H_R_FENCE_COOKIE, cookie);
	/* Conservatively own it before ringing: failed readback cannot free it. */
	d->active = i;
	slot->state = ACTIVE;
	slot->completion.slot = i;
	slot->completion.generation = d->generation;
	status = command(d, C2H_CMD_SUBMIT);
	if (!valid_status(d, status) || reg_read(d, C2H_R_COMMAND_ERROR) ||
	    !(status & C2H_ST_OWNED)) {
		quarantine(d, "submit acceptance not confirmed");
		return;
	}
	d->submitted++;
}

static void c2h_work(struct work_struct *work)
{
	struct c2h_dev *d = container_of(to_delayed_work(work), struct c2h_dev, work);
	u32 status;
	mutex_lock(&d->lock);
	if (!d->dead && !d->quarantine) {
		status = reg_read(d, C2H_R_STATUS);
		d->polls++;
		if (valid_status(d, status)) {
			harvest(d, status);
			submit_free(d);
		}
		if (!d->running && d->stopped && d->active < 0)
			wake_up_interruptible(&d->wait);
		if (!d->quarantine && (d->active >= 0 || (!d->running && !d->stopped)))
			/* At least one jiffy; never a production busy-loop. */
			mod_delayed_work(system_wq, &d->work, max_t(unsigned long, 1, msecs_to_jiffies(poll_ms)));
	}
	mutex_unlock(&d->lock);
}

static irqreturn_t c2h_irq(int irq, void *opaque)
{
	struct c2h_dev *d = opaque;
	atomic64_inc(&d->interrupts);
	if (READ_ONCE(d->online) && !READ_ONCE(d->dead))
		mod_delayed_work(system_wq, &d->work, 0);
	return IRQ_HANDLED;
}

static void stop_locked(struct c2h_dev *d)
{
	u32 status;
	d->running = false;
	if (d->quarantine || d->dead)
		return;
	if (!c2h_lifecycle_stop(&lifecycle_ops, d, &status))
		return;
	harvest(d, status);
	wake_up_interruptible(&d->wait);
	if (d->active >= 0 || !d->stopped)
		mod_delayed_work(system_wq, &d->work, 0);
}

static void final_put(struct kref *ref)
{
	struct c2h_dev *d = container_of(ref, struct c2h_dev, refs);
	unsigned int i;
	if (d->quarantine || d->active >= 0) {
		/* No DMA API unmap/free, even on close, unbind or module removal.
		 * Retain pci_dev and metadata too. No reset/recovery ioctl exists.
		 * This intentional bounded leak requires platform recovery/reboot.
		 */
		dev_crit(&d->pdev->dev, "retaining coherent mappings after unsafe detach\n");
		return;
	}
	for (i = 0; i < slots; ++i)
		if (d->buffers[i].cpu)
			dma_free_coherent(&d->pdev->dev, d->allocation_bytes, d->buffers[i].cpu, d->buffers[i].dma);
	if (d->fence)
		dma_free_coherent(&d->pdev->dev, sizeof(*d->fence), d->fence, d->fence_dma);
	pci_dev_put(d->pdev);
	kfree(d->misc.name);
	kfree(d);
}

static int c2h_open(struct inode *inode, struct file *file)
{
	struct c2h_dev *d = container_of(file->private_data, struct c2h_dev, misc);
	int ret = 0;
	mutex_lock(&d->lock);
	if (d->dead || d->quarantine)
		ret = -EIO;
	else if (d->opened)
		ret = -EBUSY;
	else {
		d->opened = true;
		kref_get(&d->refs);
		file->private_data = d;
	}
	mutex_unlock(&d->lock);
	return ret;
}

static int c2h_release_file(struct inode *inode, struct file *file)
{
	struct c2h_dev *d = file->private_data;
	unsigned int i;
	mutex_lock(&d->lock);
	stop_locked(d);
	mutex_unlock(&d->lock);
	wait_event_timeout(d->wait, READ_ONCE(d->active) < 0 ||
		READ_ONCE(d->quarantine) || READ_ONCE(d->dead), msecs_to_jiffies(drain_ms));
	mutex_lock(&d->lock);
	if (d->active >= 0)
		quarantine(d, "close drain timed out");
	/* release is delayed until mmap's file references also disappear. */
	if (!d->quarantine) {
		for (i = 0; i < slots; ++i)
			d->buffers[i].state = FREE;
		d->ready = 0;
	}
	d->opened = false;
	mutex_unlock(&d->lock);
	kref_put(&d->refs, final_put);
	return 0;
}

static long c2h_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	struct c2h_dev *d = file->private_data;
	struct c2h_release_batch batch;
	struct c2h_legacy_batch legacy;
	struct c2h_info info = {};
	struct c2h_owner_info owner = {};
	unsigned int i, j;
	long ret = 0;
	if (cmd == C2H_RELEASE && copy_from_user(&batch, (void __user *)arg, sizeof(batch)))
		return -EFAULT;
	if (cmd == C2H_LEGACY && copy_from_user(&legacy, (void __user *)arg, sizeof(legacy)))
		return -EFAULT;
	mutex_lock(&d->lock);
	if (cmd == C2H_GET_OWNER) {
		/* Cached probe identity, readable even in quarantine/detached state.
		 * generation is the last attempted allocation, not the next value.
		 */
		owner.owner_info_version = C2H_OWNER_INFO_VERSION;
		owner.user_abi = C2H_USER_ABI;
		owner.pci_domain = d->pci_domain;
		owner.pci_bus = d->pci_bus;
		owner.pci_devfn = d->pci_devfn;
		owner.generation = d->generation;
		owner.transport_session = ((u64)d->session[1] << 32) | d->session[0];
		ret = copy_to_user((void __user *)arg, &owner, sizeof(owner)) ? -EFAULT : 0;
		goto out;
	}
	if (cmd == C2H_GET_INFO) {
		info.user_abi = C2H_USER_ABI;
		info.slots = slots;
		info.capacity = capacity;
		info.mapping_bytes = d->allocation_bytes;
		info.running = d->running;
		info.quarantined = d->quarantine;
		info.stopped = d->stopped;
		info.dma_bits = dma_bits;
		info.status_polls = d->polls;
		info.interrupts = atomic64_read(&d->interrupts);
		info.submitted = d->submitted;
		info.completed = d->completed;
		ret = copy_to_user((void __user *)arg, &info, sizeof(info)) ? -EFAULT : 0;
		goto out;
	}
	if (d->dead || d->quarantine) {
		ret = -EIO;
		goto out;
	}
	switch (cmd) {
	case C2H_LEGACY:
		if (!legacy.count || legacy.count > C2H_BATCH_MAX || legacy.reserved ||
		    pci_resource_len(d->pdev, C2H_BAR) < C2H_LEGACY_BASE + 4096) {
			ret = -EINVAL;
			break;
		}
		for (i = 0; i < legacy.count; ++i) {
			struct c2h_legacy_op *op = &legacy.ops[i];
			if (op->reserved || op->write > 1 ||
			    (op->write ? !c2h_legacy_writable(op->offset) : !c2h_legacy_readable(op->offset))) {
				ret = -EPERM;
				goto out;
			}
			/* DUAL R3 N2 trial: no MONO/Rice/reset/arbitrary cadence writes. */
			if (op->write &&
			    ((op->offset == 0xf8cU && op->value != 1U) ||
			     (op->offset == 0xf90U && op->value != 1U) ||
			     (op->offset == 0xfa0U && op->value != 2U))) {
				ret = -EPERM;
				goto out;
			}
			if (op->write && op->offset == 0xfa8U) {
				if (op->value != 0U && op->value != 1U) {
					ret = -EPERM;
					goto out;
				}
				if ((reg_read(d, C2H_LEGACY_BASE + C2H_LEGACY_CONTROL) & C2H_LEGACY_APP_ENABLE) ||
				    (reg_read(d, C2H_LEGACY_BASE + 0x1cU) & 0x9cU) ||
				    (reg_read(d, C2H_LEGACY_BASE + 0xf94U) & (1U << 2))) {
					ret = -EBUSY;
					goto out;
				}
			}
			if (op->write && c2h_legacy_record_write(op->offset) &&
			    (d->running || d->active >= 0)) {
				ret = -EBUSY;
				goto out;
			}
		}
		/* Same exclusive fd and mutex as DMA; no raw BAR mmap or reset writes. */
		for (i = 0; i < legacy.count; ++i) {
			struct c2h_legacy_op *op = &legacy.ops[i];
			if (op->write)
				reg_write(d, C2H_LEGACY_BASE + op->offset, op->value);
			else
				op->value = reg_read(d, C2H_LEGACY_BASE + op->offset);
		}
		if (reg_read(d, C2H_LEGACY_BASE) != C2H_LEGACY_MAGIC) {
			quarantine(d, "legacy window readback lost");
			ret = -EIO;
			break;
		}
		/* On EFAULT, writes may have executed: caller must not retry a command. */
		ret = copy_to_user((void __user *)arg, &legacy, sizeof(legacy)) ? -EFAULT : 0;
		break;
	case C2H_START:
		if (d->running)
			break;
		if (d->active >= 0) {
			ret = -EBUSY;
			break;
		}
		if (!c2h_lifecycle_start(&lifecycle_ops, d)) {
			ret = -EIO;
			break;
		}
		d->running = true;
		mod_delayed_work(system_wq, &d->work, 0);
		break;
	case C2H_STOP:
		stop_locked(d); /* asynchronous drain; GET_INFO.stopped alone is not safe */
		if (d->quarantine)
			ret = -EIO;
		break;
	case C2H_RELEASE:
		if (!batch.count || batch.count > C2H_BATCH_MAX || batch.reserved) {
			ret = -EINVAL;
			break;
		}
		/* Validate the entire batch first: duplicates/stale handles change nothing. */
		for (i = 0; i < batch.count; ++i) {
			u32 id = batch.leases[i].slot;
			if (id >= slots || d->buffers[id].state != LEASED ||
			    d->buffers[id].completion.generation != batch.leases[i].generation) {
				ret = -ESTALE;
				goto out;
			}
			for (j = 0; j < i; ++j)
				if (batch.leases[j].slot == id) {
					ret = -EINVAL;
					goto out;
				}
		}
		for (i = 0; i < batch.count; ++i)
			d->buffers[batch.leases[i].slot].state = FREE;
		if (d->running)
			mod_delayed_work(system_wq, &d->work, 0);
		break;
	default:
		ret = -ENOTTY;
	}
out:
	mutex_unlock(&d->lock);
	return ret;
}

static enum c2h_read_action read_action(struct c2h_dev *d)
{
	/* Wait predicates are advisory; read() rechecks with the lock held. */
	return c2h_read_action_for(READ_ONCE(d->dead), READ_ONCE(d->quarantine),
		READ_ONCE(d->running), READ_ONCE(d->stopped), READ_ONCE(d->active),
		READ_ONCE(d->ready), READ_ONCE(d->submitted), READ_ONCE(d->completed));
}

static ssize_t c2h_read(struct file *file, char __user *buf, size_t size, loff_t *offset)
{
	struct c2h_dev *d = file->private_data;
	struct c2h_completion results[C2H_BATCH_MAX];
	unsigned int ids[C2H_BATCH_MAX], n = 0, i, j, limit;
	ssize_t ret;
	enum c2h_read_action action;
	if (size < sizeof(results[0]))
		return -EINVAL;
	limit = min_t(size_t, size / sizeof(results[0]), C2H_BATCH_MAX);
again:
	mutex_lock(&d->lock);
	action = read_action(d);
	if (action == C2H_READ_ERROR) {
		if (!d->dead && !d->quarantine)
			quarantine(d, "invalid read drain ownership state");
		ret = -EIO;
		goto out;
	}
	if (action == C2H_READ_EOF) {
		ret = 0;
		goto out;
	}
	for (i = 0; i < slots; ++i) {
		if (d->buffers[i].state == READY) {
			/* Buffer index is not arrival order after a lower slot is reused. */
			j = n++;
			while (j && results[j - 1].generation > d->buffers[i].completion.generation) {
				results[j] = results[j - 1];
				ids[j] = ids[j - 1];
				--j;
			}
			ids[j] = i;
			results[j] = d->buffers[i].completion;
		}
	}
	if (!n) {
		mutex_unlock(&d->lock);
		if (file->f_flags & O_NONBLOCK)
			return -EAGAIN;
		ret = wait_event_interruptible(d->wait, read_action(d) != C2H_READ_WAIT);
		if (ret)
			return ret;
		goto again;
	}
	n = min(n, limit);
	ret = n * sizeof(results[0]);
	if (copy_to_user(buf, results, ret)) {
		ret = -EFAULT; /* No leases consumed; userspace must discard partial copy. */
		goto out;
	}
	for (i = 0; i < n; ++i)
		d->buffers[ids[i]].state = LEASED;
	d->ready -= n;
out:
	mutex_unlock(&d->lock);
	return ret;
}

static __poll_t c2h_poll(struct file *file, poll_table *table)
{
	struct c2h_dev *d = file->private_data;
	__poll_t events = 0;
	poll_wait(file, &d->wait, table);
	mutex_lock(&d->lock);
	if (d->dead || d->quarantine)
		events = EPOLLERR | EPOLLHUP;
	else if (d->ready)
		events = EPOLLIN | EPOLLRDNORM;
	mutex_unlock(&d->lock);
	return events;
}

static int c2h_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct c2h_dev *d = file->private_data;
	unsigned long pages = d->allocation_bytes >> PAGE_SHIFT;
	unsigned long id = vma->vm_pgoff / pages;
	int ret;
	if (id >= slots || vma->vm_pgoff % pages || vma->vm_end - vma->vm_start != d->allocation_bytes ||
	    (vma->vm_flags & VM_WRITE) || !(vma->vm_flags & VM_SHARED))
		return -EINVAL;
	mutex_lock(&d->lock);
	if (d->dead || d->quarantine) {
		ret = -EIO;
		goto out;
	}
	/* Linux 6.1 target. Block later mprotect(PROT_WRITE), fork and dumps. */
	vma->vm_flags &= ~VM_MAYWRITE;
	vma->vm_flags |= VM_DONTCOPY | VM_DONTDUMP | VM_DONTEXPAND;
	vma->vm_pgoff = 0;
	ret = dma_mmap_coherent(&d->pdev->dev, vma, d->buffers[id].cpu,
				d->buffers[id].dma, d->allocation_bytes);
out:
	mutex_unlock(&d->lock);
	return ret;
}

static const struct file_operations c2h_fops = {
	.owner = THIS_MODULE, .open = c2h_open, .release = c2h_release_file,
	.read = c2h_read, .poll = c2h_poll, .mmap = c2h_mmap,
	.unlocked_ioctl = c2h_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl = compat_ptr_ioctl,
#endif
	.llseek = no_llseek,
};

static int c2h_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	struct c2h_dev *d;
	u32 status;
	unsigned int i;
	int ret;
	/* new_id may match multiple endpoints: select exactly one BEFORE enable,
	 * resource requests or MMIO. No default, prefix or vendor-only target.
	 */
	if (!c2h_target_matches(target_bdf, pci_name(pdev)) ||
	    pci_domain_nr(pdev->bus) < 0 || pci_domain_nr(pdev->bus) > 0xffff)
		return -ENODEV;
	if (!slots || slots > C2H_BATCH_MAX || !capacity || capacity > C2H_MAX_RECORD_BYTES ||
	    !poll_ms || poll_ms > 1000 ||
	    !drain_ms || drain_ms > 60000 || (dma_bits != 32 && dma_bits != 64))
		return -EINVAL;
	ret = pci_enable_device_mem(pdev);
	if (ret)
		return ret;
	ret = pci_request_regions(pdev, "ph1a_c2h_candidate");
	if (ret)
		goto disable;
	if (!(pci_resource_flags(pdev, C2H_BAR) & IORESOURCE_MEM) ||
	    pci_resource_len(pdev, C2H_BAR) < C2H_LEGACY_BASE + 4096) {
		ret = -ENODEV;
		goto regions;
	}
	ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(dma_bits));
	if (ret)
		goto regions;
	d = kzalloc(sizeof(*d), GFP_KERNEL);
	if (!d) {
		ret = -ENOMEM;
		goto regions;
	}
	d->pdev = pci_dev_get(pdev);
	d->pci_domain = pci_domain_nr(pdev->bus);
	d->pci_bus = pdev->bus->number;
	d->pci_devfn = pdev->devfn;
	d->active = -1;
	/* The descriptor uses logical capacity; mmap/allocation uses whole pages. */
	d->allocation_bytes = PAGE_ALIGN((size_t)capacity);
	d->stopped = true;
	mutex_init(&d->lock);
	kref_init(&d->refs);
	init_waitqueue_head(&d->wait);
	INIT_DELAYED_WORK(&d->work, c2h_work);
	atomic64_set(&d->interrupts, 0);
	d->bar = pci_iomap(pdev, C2H_BAR, 0);
	if (!d->bar) {
		ret = -ENOMEM;
		goto object;
	}
	status = reg_read(d, C2H_R_STATUS);
	if (reg_read(d, C2H_R_MAGIC) != C2H_MAGIC ||
	    reg_read(d, C2H_LEGACY_BASE) != C2H_LEGACY_MAGIC ||
	    reg_read(d, C2H_LEGACY_BASE + C2H_LEGACY_CONTROL) != 0 ||
	    reg_read(d, C2H_R_ABI_VERSION) != C2H_ABI_VERSION ||
	    reg_read(d, C2H_R_MAX_RECORD_BYTES) != C2H_MAX_RECORD_BYTES ||
	    !(status & C2H_ST_STOPPED) || (status & (C2H_ST_OWNED | C2H_ST_QUARANTINE))) {
		ret = -ENODEV; /* No reset or replacement of an unknown active owner. */
		goto unmap;
	}
	do {
		get_random_bytes(d->session, sizeof(d->session));
	} while (!(d->session[0] | d->session[1]));
	for (i = 0; i < slots; ++i) {
		d->buffers[i].cpu = dma_alloc_coherent(&pdev->dev, d->allocation_bytes, &d->buffers[i].dma, GFP_KERNEL);
		if (!d->buffers[i].cpu) {
			ret = -ENOMEM;
			goto unmap;
		}
		if (!IS_ALIGNED(d->buffers[i].dma, 16) ||
		    (u64)d->buffers[i].dma > U64_MAX - d->allocation_bytes) {
			ret = -ERANGE;
			goto unmap;
		}
		memset(d->buffers[i].cpu, 0, d->allocation_bytes);
	}
	d->fence = dma_alloc_coherent(&pdev->dev, sizeof(*d->fence), &d->fence_dma, GFP_KERNEL);
	if (!d->fence) {
		ret = -ENOMEM;
		goto unmap;
	}
	if (!IS_ALIGNED(d->fence_dma, 4) || (u64)d->fence_dma > U64_MAX - sizeof(*d->fence)) {
		ret = -ERANGE;
		goto unmap;
	}
	if (irq_hint) {
		ret = pci_alloc_irq_vectors(pdev, 1, 1, PCI_IRQ_MSI);
		if (ret < 0)
			goto unmap;
		ret = request_irq(pci_irq_vector(pdev, 0), c2h_irq, 0, "ph1a_c2h_candidate", d);
		if (ret) {
			pci_free_irq_vectors(pdev);
			goto unmap;
		}
		d->irq = true;
	}
	d->misc.minor = MISC_DYNAMIC_MINOR;
	d->misc.name = kasprintf(GFP_KERNEL, "ph1a_c2h_%s", pci_name(pdev));
	d->misc.fops = &c2h_fops;
	d->misc.parent = &pdev->dev;
	d->misc.mode = 0600;
	if (!d->misc.name) {
		ret = -ENOMEM;
		goto irq;
	}
	pci_set_master(pdev);
	WRITE_ONCE(d->online, true);
	ret = misc_register(&d->misc);
	if (ret) {
		pci_clear_master(pdev);
		goto irq;
	}
	pci_set_drvdata(pdev, d);
	return 0;
irq:
	WRITE_ONCE(d->dead, true);
	if (d->irq) {
		free_irq(pci_irq_vector(pdev, 0), d);
		pci_free_irq_vectors(pdev);
	}
	cancel_delayed_work_sync(&d->work);
unmap:
	pci_iounmap(pdev, d->bar);
object:
	kref_put(&d->refs, final_put);
regions:
	pci_release_regions(pdev);
disable:
	pci_disable_device(pdev);
	return ret;
}

static void c2h_remove(struct pci_dev *pdev)
{
	struct c2h_dev *d = pci_get_drvdata(pdev);
	if (!d)
		return;
	misc_deregister(&d->misc);
	mutex_lock(&d->lock);
	stop_locked(d);
	mutex_unlock(&d->lock);
	wait_event_timeout(d->wait, READ_ONCE(d->active) < 0 || READ_ONCE(d->quarantine),
			   msecs_to_jiffies(drain_ms));
	mutex_lock(&d->lock);
	if (d->active >= 0)
		quarantine(d, "remove drain timed out");
	/* A file/VMA can outlive PCI removal and its IOMMU attachment. Keep
	 * allocations even after a safe fence rather than calling dma_free_* on
	 * that detached device from a later final file release.
	 */
	if (d->opened)
		quarantine(d, "file or VMA outlives device removal");
	d->dead = true;
	d->running = false;
	wake_up_interruptible(&d->wait);
	mutex_unlock(&d->lock);
	if (d->irq) {
		free_irq(pci_irq_vector(pdev, 0), d);
		pci_free_irq_vectors(pdev);
	}
	cancel_delayed_work_sync(&d->work);
	/* BME clear is damage containment, NOT proof that posted writes drained. */
	pci_clear_master(pdev);
	pci_iounmap(pdev, d->bar);
	pci_release_regions(pdev);
	pci_disable_device(pdev);
	pci_set_drvdata(pdev, NULL);
	kref_put(&d->refs, final_put); /* mmap/file references can delay safe free. */
}

/* Link/session state cannot be reconstructed safely across system sleep yet.
 * Reject it explicitly instead of silently resuming potentially owned DMA.
 */
static int c2h_suspend(struct device *dev)
{
	return -EBUSY;
}

static const struct dev_pm_ops c2h_pm = {
	.suspend = c2h_suspend, .freeze = c2h_suspend, .poweroff = c2h_suspend,
};

/* Deliberately no vendor/device wildcard and no automatic binding. A reviewed
 * candidate image and explicit dynamic PCI ID are required by the integrator.
 */
static struct pci_driver c2h_driver = {
	.name = "ph1a_c2h_candidate", .id_table = NULL,
	.probe = c2h_probe, .remove = c2h_remove, .shutdown = c2h_remove,
	.driver = { .suppress_bind_attrs = true, .pm = &c2h_pm },
};
module_pci_driver(c2h_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Isolated PH1A frame-grant C2H candidate, private ABI v1");
