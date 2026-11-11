"""Strict owned product inspection; no device, codec fallback or negotiation.

Returned products are the existing JpegProduct/RawProduct consumed by the runtime.
Offline bytes establish no DMA SAFE/fence, physical SOURCE or capture-time proof.
Only a trusted live owner may authorize/confirm an additional CFG epoch.
"""
from __future__ import annotations

from collections import Counter, deque
from dataclasses import asdict, dataclass
import hashlib
from pathlib import Path
import time

from linux.lz_native import NativeLzError, NativeReassembler
from linux.stream_diag.records import parse_record
from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.lz_stream import _parse_header as parse_lz_header
from linux.task3_pipeline.product_receiver import JpegProduct, RawProduct
from linux.task3_pipeline.record_selection import header_length


MAX_RECORD_BYTES = p.MAX_PAYLOAD + p.PCIE_RECORD_V3_HEADER_LENGTH
PRODUCT_COUNTER_NAMES = frozenset(('records', 'wire_bytes', 'jpeg_frames', 'jpeg_bytes',
    'raw_frames', 'raw_bytes', 'lz_records_seen', 'lz_chunks_crc_verified', 'lz_blocks_crc_verified',
    'lz_crc_failures', 'lz_negative_terminals', 'incomplete_lz_frames', 'rejected',
    'analysis_negative_terminals', 'analysis_frame_errors', 'events', 'event_summaries_evicted',
    'jpeg_records_seen', 'sequence_gap_events', 'sequence_missing'))


def _uint(value, name, *, minimum=0, bits=32):
    if type(value) is not int or not minimum <= value < 1 << bits:
        raise ValueError(f'invalid {name}')
    return value


def json_value(value):
    """Lossless bounded parser data, never raw image bytes in a JSON report."""
    if isinstance(value, bytes):
        return {'hex': value.hex()}
    if isinstance(value, dict):
        return {str(key): json_value(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [json_value(item) for item in value]
    return value


@dataclass(frozen=True)
class ProductEvent:
    kind: str
    status: str
    summary: dict
    product: JpegProduct | RawProduct | None = None


class ProductInspector:
    """Serialized, bounded inspection with at most two explicit native epochs.

    No bytes or returned products are retained in the diagnostic event ring.
    Callers must bound their own product queues. Epoch retirement never proves
    kernel READY drain or FPGA-wide quiescence, and never releases DMA resources.
    """
    def __init__(self, *, expected_jpeg_version=None, lz_session=None, lz_epoch=None,
                 lz_library=None, max_records=100_000, event_limit=64,
                 max_record_bytes=MAX_RECORD_BYTES):
        if expected_jpeg_version is not None:
            header_length(expected_jpeg_version)
        for value, maximum, name in ((max_records, 1_000_000, 'max_records'),
                                      (event_limit, 128, 'event_limit'),
                                      (max_record_bytes, MAX_RECORD_BYTES, 'max_record_bytes')):
            if type(value) is not int or not 1 <= value <= maximum:
                raise ValueError(f'invalid {name}')
        configured = (lz_session is not None, lz_epoch is not None, lz_library is not None)
        if any(configured) and not all(configured):
            raise ValueError('LZ needs explicit source session, epoch and existing native library together')
        self.expected_jpeg_version = expected_jpeg_version
        self.max_records, self.event_limit, self.max_record_bytes = max_records, event_limit, max_record_bytes
        self.source_session = None
        self.library_path = None
        self._epochs, self._sequences = {}, {}
        self._retired = deque(maxlen=64)
        self._epoch_highwater = None
        self._events = deque(maxlen=event_limit)
        self._counts = Counter(dict.fromkeys(('records', 'wire_bytes', 'jpeg_frames', 'jpeg_bytes',
            'raw_frames', 'raw_bytes', 'lz_records_seen', 'lz_chunks_crc_verified', 'lz_blocks_crc_verified',
            'lz_crc_failures', 'lz_negative_terminals', 'incomplete_lz_frames', 'rejected',
            'analysis_negative_terminals', 'analysis_frame_errors'), 0))
        self._rates = {}
        self._last_host_ns = None
        self._finished = self._closed = False
        if all(configured):
            self.source_session = _uint(lz_session, 'source session', minimum=1)
            _uint(lz_epoch, 'source epoch')
            self.library_path = Path(lz_library).resolve(strict=True)
            if not self.library_path.is_file():
                raise ValueError('explicit native library must be an existing regular file')
            self._add_epoch(lz_epoch, confirmed=True)

    def _add_epoch(self, epoch, *, confirmed):
        owner = NativeReassembler(self.source_session, epoch, self.library_path)
        self._epochs[epoch] = dict(owner=owner, confirmed=confirmed, boundary_seen=False,
                                   pending=None, accepted_chunks=0, completed_frames=0)
        self._epoch_highwater = epoch

    def authorize_epoch(self, epoch):
        """Trusted owner only, before COMMIT; preserve previous epoch assembly."""
        _uint(epoch, 'epoch')
        if self._closed or self._finished or self.source_session is None:
            raise RuntimeError('no open configured LZ epoch owner')
        if len(self._epochs) >= 2 or epoch != self._epoch_highwater + 1:
            raise ValueError('only one next epoch may be explicitly authorized; retired epochs cannot be reused')
        self._add_epoch(epoch, confirmed=False)

    def confirm_epoch(self, epoch):
        """Caller has observed real APPLIED. Record bytes cannot call this."""
        _uint(epoch, 'epoch')
        if epoch not in self._epochs or self._closed or self._finished:
            raise ValueError('unknown or closed authorized epoch')
        self._epochs[epoch]['confirmed'] = True

    def retire_epoch(self, epoch, *, require_complete=True):
        _uint(epoch, 'epoch')
        state = self._epochs.get(epoch)
        newer = [item for key, item in self._epochs.items() if key > epoch
                 and item['confirmed'] and item['boundary_seen']]
        if (require_complete is not True or state is None or self._closed or self._finished
                or state['pending'] is not None or state['owner'].buffered_bytes or not newer):
            raise ValueError('retire needs empty old assembly and a confirmed observed newer epoch boundary')
        self._retired.append(self._epoch_snapshot(epoch, state))
        state['owner'].close()
        del self._epochs[epoch]
        self._sequences = {key: value for key, value in self._sequences.items()
                           if not ((key[0] == 'JPEG' and key[2:4] == (self.source_session, epoch))
                                   or (key[0] == 'LZC1' and key[1:3] == (self.source_session, epoch)))}

    def _epoch_snapshot(self, epoch, state):
        return dict(epoch=epoch, confirmed=state['confirmed'], boundary_seen=state['boundary_seen'],
                    pending=None if state['pending'] is None else dict(state['pending']), buffered_bytes=state['owner'].buffered_bytes,
                    highest_sequence=state['owner'].highest_sequence,
                    accepted_chunks=state['accepted_chunks'], completed_frames=state['completed_frames'])

    def _drop_pending(self, epoch, reason):
        state = self._epochs[epoch]
        pending = state['pending']
        state['owner'].fail_pending()
        state['pending'] = None
        if pending is None:
            return None
        self._counts['incomplete_lz_frames'] += 1
        return dict(pending, reason=reason[:256],
                    missing_chunks=max(0, p.PCIE_LZ_FRAME_CHUNKS - pending['next_chunk']))

    def fail_pending(self, reason='explicit software assembly stop', *, epoch=None):
        if self._closed:
            raise RuntimeError('inspector closed')
        if type(reason) is not str or not 1 <= len(reason) <= 256:
            raise ValueError('bounded reason required')
        if epoch is not None and epoch not in self._epochs:
            raise ValueError('epoch not authorized')
        return [item for key in tuple(self._epochs) if epoch is None or key == epoch
                if (item := self._drop_pending(key, reason)) is not None]

    def _sequence(self, key, sequence):
        previous = self._sequences.get(key)
        if previous is None and len(self._sequences) >= 128:
            raise ValueError('sequence cohort bound reached')
        state = 'FIRST' if previous is None else ('NEXT' if sequence == previous + 1 else
                'GAP' if sequence > previous + 1 else 'REPEAT' if sequence == previous else 'BACKWARD')
        if state == 'GAP':
            self._counts['sequence_gap_events'] += 1
            self._counts['sequence_missing'] += sequence - previous - 1
        if state in ('REPEAT', 'BACKWARD'):
            self._counts['sequence_' + state.lower()] += 1
        self._sequences[key] = max(sequence, previous) if previous is not None else sequence
        return dict(status=state, previous=previous, current=sequence)

    def _rate(self, kind, host_ns):
        rate = self._rates.setdefault(kind, dict(count=0, first_host_ns=host_ns, last_host_ns=host_ns))
        rate['count'] += 1
        rate['last_host_ns'] = host_ns

    def _emit(self, kind, status, summary, product=None):
        self._counts['events'] += 1
        if status == 'REJECTED':
            self._counts['rejected'] += 1
        if len(self._events) == self.event_limit:
            self._counts['event_summaries_evicted'] += 1
        event = ProductEvent(kind, status, summary, product)
        self._events.append(json_value(dict(kind=kind, status=status, **summary)))
        return event

    def feed(self, wire, *, host_ns=None, transport_identity=()):
        if self._closed or self._finished:
            raise RuntimeError('inspector closed/finished')
        if type(wire) is not bytes:
            raise TypeError('owned immutable record bytes required')
        if self._counts['records'] >= self.max_records:
            raise ValueError('record count bound reached')
        host_ns = time.monotonic_ns() if host_ns is None else _uint(host_ns, 'host_ns', bits=64)
        if self._last_host_ns is not None and host_ns < self._last_host_ns:
            raise ValueError('host observation clock moved backwards')
        if (type(transport_identity) is not tuple or len(transport_identity) > 16
                or any(type(value) is not int or not 0 <= value < 1 << 64 for value in transport_identity)):
            raise ValueError('bounded transport identity tuple required')
        self._last_host_ns = host_ns
        self._counts['records'] += 1
        self._counts['wire_bytes'] += len(wire)
        summary = dict(index=self._counts['records'], host_ns=host_ns, wire_bytes=len(wire),
                       transport_identity=list(transport_identity), dma_safety='NOT_ESTABLISHED_FROM_RECORD_BYTES')
        if len(wire) > self.max_record_bytes:
            return self._emit('UNKNOWN', 'REJECTED', dict(summary, reason='record byte bound exceeded'))
        summary['wire_sha256'] = hashlib.sha256(wire).hexdigest()
        magic = int.from_bytes(wire[:4], 'little') if len(wire) >= 4 else None
        if magic == p.FRAME_MAGIC:
            return self._jpeg(wire, host_ns, transport_identity, summary)
        if magic == p.PCIE_LZ_MAGIC:
            return self._lz(wire, host_ns, transport_identity, summary)
        return self._emit('UNKNOWN', 'REJECTED', dict(summary, reason='unknown/truncated product magic; no resynchronization'))

    def _jpeg(self, wire, host_ns, transport_identity, summary):
        self._counts['jpeg_records_seen'] += 1
        observed = None
        try:
            if len(wire) < p.FRAME_HEADER_SIZE:
                raise ValueError('short AJPG base header')
            observed = dict(zip(p.FRAME_HEADER_FIELD_NAMES, p.FRAME_HEADER_STRUCT.unpack_from(wire), strict=True))
            version = observed['protocol_version']
            header_length(version)
            summary['jpeg_version'] = version
            if self.expected_jpeg_version is not None and version != self.expected_jpeg_version:
                raise ValueError('JPEG version differs from explicit selection')
            record = parse_record(wire, expected_version=version)
            meta, sparse = record.metadata, record.s07
            source = None if meta is None or meta.source is None else asdict(meta.source)
            session, epoch, camera = (None, None, None) if source is None else (source['session'], source['epoch'], source['camera'])
            summary.update(source_session=session, source_epoch=epoch, source=source,
                           base_header=json_value(observed), width=record.width, height=record.height,
                           jpeg_bytes=len(record.jpeg), jpeg_sha256=hashlib.sha256(record.jpeg).hexdigest(),
                           timestamp_ns=record.timestamp_ns,
                           metadata=None if meta is None else json_value(asdict(meta)),
                           metadata_qualified=None if meta is None else meta.qualified,
                           f20=None if meta is None else json_value(dict(context=None if meta.neutral_context is None else asdict(meta.neutral_context),
                                                                       stats=None if meta.neutral_stats is None else asdict(meta.neutral_stats))),
                           sparse=None if sparse is None else json_value(asdict(sparse)),
                           f24_scope='TERMINAL_ONLY_NO_COMPLETE_MASK',
                           jpeg_crc='NOT_DEFINED_BY_SELECTED_PROTOCOL',
                           jpeg_validation='STRICT_RECORD_AND_MARKER_BOUNDARIES_NOT_PIXEL_DECODE')
            if source is not None and self._epochs:
                if session != self.source_session or epoch not in self._epochs:
                    raise ValueError('JPEG SOURCE session/epoch not explicitly authorized')
                self._epochs[epoch]['boundary_seen'] = True
            summary['sequence'] = self._sequence(('JPEG', version, session, epoch, camera), record.sequence)
            negative = [] if sparse is None else [name for name in ('f22', 'f23', 'f24', 'f25')
                     if (item := getattr(sparse, name)) is not None and
                     (item.status not in (p.PCIE_RECORD_V4_STATUS_OK,p.PCIE_RECORD_V4_STATUS_NO_CANDIDATES)
                      if version == 4 and name == 'f23' else item.error or not item.ok)]
            summary['negative_analysis_terminals'] = negative
            summary['sparse_frame_error'] = None if sparse is None else sparse.frame_error
            self._counts['analysis_negative_terminals'] += len(negative)
            self._counts['analysis_frame_errors'] += int(sparse is not None and sparse.frame_error)
            self._counts['jpeg_frames'] += 1
            self._counts['jpeg_bytes'] += len(record.jpeg)
            self._rate('jpeg', host_ns)
            return self._emit('JPEG', 'COMPLETE', summary, JpegProduct(record, wire, transport_identity))
        except ValueError as exc:
            if observed is not None:
                summary['untrusted_base_header'] = json_value(observed)
            return self._emit('JPEG', 'REJECTED', dict(summary, reason=str(exc)[:512]))

    def _lz(self, wire, host_ns, transport_identity, summary):
        self._counts['lz_records_seen'] += 1
        try:
            header = parse_lz_header(wire)
        except ValueError as exc:
            return self._emit('LZC1', 'REJECTED', dict(summary, reason=str(exc)[:512]))
        epoch = header['mode_epoch']
        summary.update(source_session=header['source_session'], source_epoch=epoch, header=json_value(header))
        if header['source_session'] != self.source_session or epoch not in self._epochs:
            return self._emit('LZC1', 'REJECTED', dict(summary, reason='LZ source session/epoch/native owner not explicitly authorized'))
        state = self._epochs[epoch]
        try:
            frame = state['owner'].push(wire)
        except NativeLzError as exc:
            negative = header['product_type'] == p.PCIE_LZ_PRODUCT_TYPES_FAILURE and 'negative frame terminal' in str(exc)
            if negative:
                self._counts['lz_negative_terminals'] += 1
                state['boundary_seen'] = True
            if 'CRC' in str(exc):
                self._counts['lz_crc_failures'] += 1
            aborted = self._drop_pending(epoch, str(exc))
            return self._emit('LZC1', 'NEGATIVE_TERMINAL' if negative else 'REJECTED',
                              dict(summary, reason=str(exc)[:512], native_error_code=exc.code, aborted_lz=aborted))
        state['boundary_seen'] = True
        state['accepted_chunks'] += 1
        self._counts['lz_chunks_crc_verified'] += 1
        self._counts['lz_blocks_crc_verified'] += header['block_count']
        summary['crc'] = 'NATIVE_STORED_AND_RAW_BLOCK_CRC_VERIFIED'
        if header['chunk_index'] == 0:
            summary['sequence'] = self._sequence(('LZC1', self.source_session, epoch, header['camera']), header['capture_sequence'])
        if frame is None:
            state['pending'] = dict(source_session=self.source_session, source_epoch=epoch,
                                    sequence=header['capture_sequence'], generation=header['generation'],
                                    next_chunk=header['chunk_index'] + 1, buffered_bytes=state['owner'].buffered_bytes)
            return self._emit('LZC1', 'PARTIAL', summary)
        state['pending'] = None
        state['completed_frames'] += 1
        self._counts['raw_frames'] += 1
        self._counts['raw_bytes'] += len(frame.raw)
        self._rate('raw', host_ns)
        summary.update(raw_bytes=len(frame.raw), raw_sha256=hashlib.sha256(frame.raw).hexdigest(),
                       raw_identity=asdict(frame.identity))
        return self._emit('LZC1', 'COMPLETE', summary, RawProduct(frame, transport_identity))

    def snapshot(self):
        rates = {}
        for name, sample in self._rates.items():
            elapsed = sample['last_host_ns'] - sample['first_host_ns']
            rates[name] = dict(sample, fps=None if sample['count'] < 2 or elapsed <= 0 else
                               (sample['count'] - 1) * 1e9 / elapsed)
        return dict(format='RK_DEBUG_PRODUCTS_V1', counters=dict(self._counts), rates=rates,
                    rate_scope='HOST_INSPECTION_COMPLETIONS_NOT_SENSOR_LINK_OR_REPLAY_RATE',
                    epochs={str(key): self._epoch_snapshot(key, value) for key, value in self._epochs.items()},
                    retired_epochs=json_value(list(self._retired)), epoch_highwater=self._epoch_highwater,
                    events=json_value(list(self._events)), finished=self._finished,
                    limits=dict(records=self.max_records, events=self.event_limit, record_bytes=self.max_record_bytes,
                                authorized_epochs=2, epoch_history=64, sequence_cohorts=128),
                    hardware='NOT_RUN', jpeg_pixel_decode='NOT_RUN')

    def finish(self):
        if not self._finished and not self._closed:
            incomplete = self.fail_pending('end of input before complete LZ frame')
            for item in incomplete:
                self._emit('LZC1', 'INCOMPLETE_EOF', item)
            self._finished = True
        return self.snapshot()

    def close(self):
        if self._closed:
            return
        self.finish()
        # Freeze snapshots before destroying native contexts.
        for epoch, state in tuple(self._epochs.items()):
            self._retired.append(self._epoch_snapshot(epoch, state))
            state['owner'].close()
        self._epochs.clear()
        self._closed = True

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
