"""Copy completed C2H records once, before releasing their exact host lease."""
from __future__ import annotations

from dataclasses import asdict
import time

from linux.dma_c2h_candidate.receiver import BATCH_MAX
from linux.dma_c2h_candidate.c2h_abi import RESULT_COMPLETE


class OwnedRecordReader:
    """Only the receiving thread calls poll_once; controls share the same fd.

    Inspector consumes immutable copies. No parser/display/recorder can retain a
    DMA mapping. Unknown IO or RELEASE failure stops this reader permanently;
    it never guesses which remaining leases can be returned.
    """
    def __init__(self, receiver, inspector, *, maximum_batch=4, record_budget=None,
                 clock_ns=time.monotonic_ns):
        if type(maximum_batch) is not int or not 1 <= maximum_batch <= BATCH_MAX:
            raise ValueError('invalid completion batch bound')
        self.receiver, self.inspector = receiver, inspector
        if record_budget is not None and (type(record_budget) is not int or record_budget < 1):
            raise ValueError('record budget must be a positive count')
        self.record_budget = record_budget
        self.maximum_batch, self.clock = maximum_batch, clock_ns
        self.records = self.copied_bytes = self.safe_errors = 0
        self.inspected_records = self.budget_discards = 0
        self.fault = None

    @property
    def limit_reached(self):
        return self.record_budget is not None and self.inspected_records >= self.record_budget

    def poll_once(self, timeout_s):
        if self.fault is not None:
            raise RuntimeError('debug receiver is terminal after uncertain transport IO')
        try:
            self.receiver.poll(timeout_s)
            events = []
            for lease in self.receiver.receive_available(self.maximum_batch):
                identity = tuple(lease.record_identity)
                self.records += 1
                if lease.result != RESULT_COMPLETE:
                    result = lease.result
                    lease.release()
                    self.safe_errors += 1
                    events.append(dict(kind='TRANSPORT_RESULT', status='SAFE_NEGATIVE',
                                       result=result, transport_identity=identity))
                    continue
                if not 0 < lease.length <= self.receiver.capacity:
                    raise ValueError('completed record exceeds the established DMA pool')
                if self.limit_reached:
                    length = lease.length
                    lease.release()
                    self.budget_discards += 1
                    events.append(dict(kind='RECORD_LIMIT', status='DRAIN_DISCARD',
                        wire_bytes=length, transport_identity=identity))
                    continue
                with lease.view() as view:
                    wire = bytes(view)
                self.copied_bytes += len(wire)
                lease.release()
                events.append(self.inspector.feed(wire, host_ns=self.clock(), transport_identity=identity))
                self.inspected_records += 1
            return tuple(events)
        except BaseException as error:
            self.fault = f'{type(error).__name__}: {error}'[:512]
            raise

    def drained(self):
        if self.receiver.leased_count or self.receiver.poll(0):
            return False
        info = self.receiver.snapshot()
        if info.quarantined:
            raise RuntimeError('C2H quarantined while stopping')
        return info.transport_drained

    def snapshot(self):
        return dict(records=self.records, copied_bytes=self.copied_bytes, safe_errors=self.safe_errors,
                    inspected_records=self.inspected_records, budget_discards=self.budget_discards,
                    limit_reached=self.limit_reached,
                    fault=self.fault, hardware=asdict(self.receiver.snapshot()),
                    leased=self.receiver.leased_count,
                    scope='HOST_COMPLETIONS_NOT_FPGA_GLOBAL_DRAIN')
