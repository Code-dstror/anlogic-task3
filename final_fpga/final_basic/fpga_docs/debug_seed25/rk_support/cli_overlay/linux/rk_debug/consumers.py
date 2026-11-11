"""Optional bounded consumers of complete owned debug products.

The caller has already copied/released transport leases. This layer has no DMA,
CFG or reset access. MPP/NativePixels/GstKmsPresenter and recorders are explicitly
constructed by the caller; pure packet inspection loads none of those libraries.
RAW preview is a finite static PGM value dump, not demosaic/ISP or live video.
"""
from __future__ import annotations

from collections import deque
from dataclasses import asdict
import hashlib
import math
from pathlib import Path
from threading import Condition, Thread
import time
from uuid import uuid4

from linux.task3_pipeline.product_receiver import JpegProduct, RawProduct
from linux.stream_diag.records import parse_record
from linux.task3_runtime.pipeline import SourceKey
from linux.task3_runtime.raw_recording import validate_frame
from linux.task3_runtime.recording import _directory, _open_new, _write, _sync, _sync_dir, _publish_owned
from .products import ProductEvent, json_value


class ConsumerError(RuntimeError):
    pass


def raw10_static_pgm(raw, width=1920, height=1080):
    """Finite diagnostic conversion of RAW10_PACKED_LE5_RASTER, sample >> 2.

    Python group conversion is deliberately confined to explicitly capped
    static previews. It is never a claimed 30fps RAW/HDMI implementation.
    """
    if (type(raw) is not bytes or type(width) is not int or type(height) is not int or
            not 4 <= width <= 1920 or width % 4 or not 1 <= height <= 1080 or
            len(raw) != width * height * 5 // 4):
        raise ValueError('complete bounded canonical RAW10 raster required')
    gray = bytearray(width * height)
    for group in range(width * height // 4):
        a, b, c, d, e = raw[group*5:group*5+5]
        offset = group*4
        gray[offset] = (a >> 2) | ((b & 3) << 6)
        gray[offset+1] = (b >> 4) | ((c & 15) << 4)
        gray[offset+2] = (c >> 6) | ((d & 63) << 2)
        gray[offset+3] = e
    return f'P5\n{width} {height}\n255\n'.encode('ascii') + gray


class _StaticRawPreviews:
    """New owned directory, finite files/bytes, no eviction or directory reuse."""
    def __init__(self, root, cohort, max_frames, max_bytes):
        import json
        path = Path(root)
        if not path.name or '..' in path.parts:
            raise ValueError('explicit new RAW preview directory required')
        self.root, self.cohort = path.absolute(), cohort
        self.max_frames, self.max_bytes = max_frames, max_bytes
        self.written = self.skipped = 0
        self.bytes = 0
        for parent in reversed(self.root.parents):
            _directory(parent)
        self.root.mkdir(mode=0o700)
        data = (json.dumps(dict(format='rk-debug-static-raw-pgm-v1', receiver_cohort=cohort,
            max_frames=max_frames, max_bytes=max_bytes,
            interpretation='RAW10 sample >> 2; no ISP/debayer/physical color or live FPS claim'),
            sort_keys=True) + '\n').encode()
        if len(data) > max_bytes:
            raise ValueError('preview quota cannot fit manifest')
        with _open_new(self.root / 'run.json') as file:
            _write(file, data)
            _sync(file)
        self.bytes = len(data)
        _sync_dir(self.root)

    def append(self, product):
        import json
        if self.written >= self.max_frames:
            self.skipped += 1
            return False
        frame, header = validate_frame(product)
        # Reserve against the exact known output size before the static CPU loop.
        pgm_header = b'P5\n1920 1080\n255\n'
        row = (json.dumps(dict(format='rk-debug-static-raw-pgm-frame-v1', receiver_cohort=self.cohort,
            source=asdict(frame.identity), terminal_header=json_value(header),
            raw_sha256=hashlib.sha256(frame.raw).hexdigest(), transform='sample >> 2',
            physical_color_qualified=False, real_time_qualified=False),
            sort_keys=True, separators=(',', ':')) + '\n').encode()
        total = len(pgm_header) + 1920*1080 + len(row)
        if len(row) > 8192 or self.bytes + total > self.max_bytes:
            self.skipped += 1
            return False
        self.bytes += total  # A failed/partial write is never recycled as quota.
        pgm = raw10_static_pgm(frame.raw)
        name = f'preview-{self.written+1:04d}'
        partial, final = self.root / (name + '.partial'), self.root / (name + '.segment')
        partial.mkdir(mode=0o700)
        for filename, content in (('frame.pgm', pgm), ('source.json', row)):
            with _open_new(partial / filename) as file:
                _write(file, content)
                _sync(file)
        _sync_dir(partial)
        _publish_owned(partial, final, self.root)
        self.written += 1
        return True

    def snapshot(self):
        return dict(written=self.written, skipped=self.skipped, reserved_bytes=self.bytes,
            max_frames=self.max_frames, max_bytes=self.max_bytes,
            max_files=1+2*self.max_frames, live_raw_preview=False,
            interpretation='STATIC_RAW_VALUES_NOT_ISP_OR_DEBAYER', target_fps='NOT_MEASURED')


class DebugConsumers:
    """One bounded decode/static-preview worker plus explicit bounded sinks.

    Constructor transfers ownership of supplied decoder/presenter/recorders only
    after validating options. Recorders must already be started. consume does no
    decode, pixel packing or disk/pipe write; queue-full drops a NEW whole copy.
    close only requests drain and joins; the worker closes native resources after
    its active decode completes. A blocked worker remains owned and reported.
    """
    def __init__(self, *, decode=False, decoder=None, pixels=None, presenter=None,
                 jpeg_recorder=None, raw_recorder=None, queue_depth=2,
                 max_product_bytes=33554880, receiver_cohort=None, jpeg_version=None,
                 raw_preview_dir=None, raw_preview_max_frames=1,
                 raw_preview_max_bytes=4194304, close_worker_timeout_s=1.0):
        if type(decode) is not bool or type(queue_depth) is not int or not 1 <= queue_depth <= 8:
            raise ValueError('invalid decode/queue options')
        if type(max_product_bytes) is not int or not 1 <= max_product_bytes <= 64*1024*1024:
            raise ValueError('invalid product byte bound')
        if decode and (decoder is None or type(jpeg_version) is not int or jpeg_version not in (1, 2, 3, 4)):
            raise ValueError('decode requires explicit decoder and selected JPEG version')
        if not decode and any(value is not None for value in (decoder, pixels, presenter)):
            raise ValueError('pure capture cannot implicitly enable native decode/display')
        if presenter is not None and (pixels is None or
                not isinstance(getattr(presenter, 'colorimetry', None), str) or not presenter.colorimetry or
                type(getattr(presenter, 'connector_id', None)) is not int or presenter.connector_id < 0 or
                type(getattr(presenter, 'plane_id', None)) is not int or presenter.plane_id < 0 or
                getattr(presenter, 'force_modesetting', False)):
            raise ValueError('HDMI requires explicit pixel packer/connector/plane/colorimetry and no forced modeset')
        for value, high, name in ((raw_preview_max_frames, 16, 'preview frames'),
                                   (raw_preview_max_bytes, 64*1024*1024, 'preview bytes')):
            if type(value) is not int or not 1 <= value <= high:
                raise ValueError(f'invalid {name} bound')
        if (type(close_worker_timeout_s) not in (int, float) or not math.isfinite(close_worker_timeout_s) or
                not 0 < close_worker_timeout_s <= 10):
            raise ValueError('invalid owned sink close budget')
        cohort = receiver_cohort if receiver_cohort is not None else 'rk-debug-' + uuid4().hex
        if type(cohort) is not str or not 1 <= len(cohort) <= 128:
            raise ValueError('invalid receiver cohort')
        self.decode, self.decoder, self.pixels, self.presenter = decode, decoder, pixels, presenter
        self.jpeg_recorder, self.raw_recorder = jpeg_recorder, raw_recorder
        self.cohort, self.jpeg_version = cohort, jpeg_version
        self.depth, self.max_product_bytes = queue_depth, max_product_bytes
        self.raw_preview_dir = raw_preview_dir
        self.preview_limits = raw_preview_max_frames, raw_preview_max_bytes
        self.close_worker_timeout_s = close_worker_timeout_s
        self._cv, self._queue = Condition(), deque()
        self._closing = self._done = False
        self._failure = None
        # Explicit preview setup occurs before the caller opens transport. Only
        # constructor setup may touch disk on this thread; consume never does.
        self._preview = (None if raw_preview_dir is None else
                         _StaticRawPreviews(raw_preview_dir, cohort, *self.preview_limits))
        self._preview_snapshot = None if self._preview is None else self._preview.snapshot()
        self._received = self._processed = self._dropped = self._pending_bytes = 0
        self._ignored = self._decoded = self._raw = self._inflight_bytes = 0
        self._decode_ns = 0
        self._last_identity = None
        self._jpeg_record_dropped = self._raw_record_dropped = 0
        self._thread = Thread(target=self._run, name='rk-debug-owned-consumers', daemon=True)
        self._thread.start()

    def _error(self, error):
        with self._cv:
            self._failure = self._failure or f'{type(error).__name__}: {error}'[:512]
            self._closing = True
            self._cv.notify_all()

    def consume(self, value):
        self.check()
        if isinstance(value, ProductEvent):
            value = value.product
            if value is None:
                with self._cv:
                    self._ignored += 1
                return False
        if isinstance(value, JpegProduct):
            if type(value.wire) is not bytes or type(value.record.jpeg) is not bytes:
                raise ValueError('JPEG product must own immutable complete bytes')
            size = len(value.wire) + len(value.record.jpeg)
            needs_worker = self.decode
            recorder = self.jpeg_recorder
        elif isinstance(value, RawProduct):
            if type(value.frame.raw) is not bytes or len(value.frame.raw) != 2592000:
                raise ValueError('RAW product must own the entire recovered RAW10 frame')
            size = len(value.frame.raw) + 8192
            needs_worker = self.raw_preview_dir is not None
            recorder = self.raw_recorder
        else:
            raise TypeError('expected complete JpegProduct/RawProduct or ProductEvent')
        if size > self.max_product_bytes:
            raise ValueError('product exceeds consumer copy bound')
        with self._cv:
            if self._closing:
                raise ConsumerError('consumers are closing')
            self._received += 1
        try:
            if recorder is not None and not recorder.submit(value):
                with self._cv:
                    if isinstance(value, JpegProduct): self._jpeg_record_dropped += 1
                    else: self._raw_record_dropped += 1
        except BaseException as error:
            self._error(error)
            raise
        with self._cv:
            if not needs_worker:
                self._processed += 1
                if isinstance(value, RawProduct): self._raw += 1
                return True
            if self._closing:
                self._dropped += 1
                return False
            if len(self._queue) >= self.depth:
                self._dropped += 1
                return False
            self._queue.append((value, size))
            self._pending_bytes += size
            self._cv.notify()
            return True

    def _jpeg(self, product):
        record = parse_record(product.wire, expected_version=self.jpeg_version)
        if record != product.record:
            raise ConsumerError('owned JPEG record differs from its wire')
        key = SourceKey.from_record(self.cohort, record)
        frame = self.decoder.decode_record(product.wire, expected_version=self.jpeg_version,
                                           copy_nv12=self.presenter is not None)
        if (frame.sequence, frame.width, frame.height) != (record.sequence, record.width, record.height):
            raise ConsumerError('MPP output identity/geometry mismatch')
        if type(frame.decode_ns) is not int or frame.decode_ns < 0:
            raise ConsumerError('invalid decoder timing')
        if self.presenter is not None:
            if type(frame.nv12) is not bytes:
                raise ConsumerError('HDMI requires owned NV12 copy')
            tight = self.pixels.pack(frame.nv12, frame.width, frame.height, frame.hor_stride, frame.ver_stride)
            identity = dict(asdict(key), record_version=self.jpeg_version)
            self.presenter.submit_owned(tight, identity=identity)
        with self._cv:
            self._decoded += 1
            self._decode_ns += frame.decode_ns
            self._last_identity = asdict(key)

    def _close_sinks(self):
        # This runs only after our worker owns no active decoder call. Native
        # close can block: the main close() still has a bounded join and retains us.
        errors = []
        if self.decoder is not None:
            try:
                self.decoder.close()
            except Exception as error:
                errors.append(f'decoder close: {type(error).__name__}: {error}')
        if self.presenter is not None:
            try:
                self.presenter.close(timeout_s=self.close_worker_timeout_s)
            except Exception as error:
                errors.append(f'presenter close: {type(error).__name__}: {error}')
        for recorder in (self.jpeg_recorder, self.raw_recorder):
            if recorder is None:
                continue
            try:
                recorder.request_stop()
                while True:
                    state = recorder.close(timeout_s=self.close_worker_timeout_s)
                    if state.get('worker_done'):
                        if state.get('failure'):
                            self._error(ConsumerError(state['failure']))
                        break
                    # A slow disk owner remains alive; no forced file close/release.
                    time.sleep(min(.01, self.close_worker_timeout_s))
            except Exception as error:
                errors.append(f'recorder close: {type(error).__name__}: {error}')
        if errors:
            raise ConsumerError('; '.join(errors)[:512])

    def _run(self):
        cleanup_complete = False
        try:
            while True:
                with self._cv:
                    self._cv.wait_for(lambda: self._queue or self._closing)
                    if self._failure or not self._queue:
                        break
                    product, size = self._queue.popleft()
                    self._pending_bytes -= size
                    self._inflight_bytes = size
                if isinstance(product, JpegProduct):
                    self._jpeg(product)
                else:
                    self._preview.append(product)
                    with self._cv:
                        self._raw += 1
                        self._preview_snapshot = self._preview.snapshot()
                with self._cv:
                    self._processed += 1
                    self._inflight_bytes = 0
        except BaseException as error:
            self._error(error)
        finally:
            with self._cv:
                self._dropped += len(self._queue) + int(self._inflight_bytes != 0)
                self._queue.clear()
                self._pending_bytes = self._inflight_bytes = 0
            try:
                self._close_sinks()
                cleanup_complete = True
            except BaseException as error:
                self._error(error)
            with self._cv:
                # On uncertain native/presenter close, root must keep the owner;
                # a terminated worker alone is not a cleanup proof.
                self._done = cleanup_complete
                self._cv.notify_all()

    def check(self):
        with self._cv:
            error = self._failure
        if error:
            raise ConsumerError(error)
        try:
            if self.presenter is not None:
                self.presenter.check()
            for recorder in (self.jpeg_recorder, self.raw_recorder):
                if recorder is not None:
                    state = recorder.snapshot()
                    if state.get('failure'):
                        raise ConsumerError(state['failure'])
        except BaseException as error:
            self._error(error)
            raise ConsumerError(self._failure) from error

    def close(self, timeout_s=3):
        if type(timeout_s) not in (int, float) or not math.isfinite(timeout_s) or timeout_s < 0:
            raise ValueError('invalid close timeout')
        with self._cv:
            self._closing = True
            self._cv.notify_all()
        self._thread.join(timeout_s)
        return self.snapshot()

    def snapshot(self):
        with self._cv:
            result = dict(received=self._received, processed=self._processed, dropped=self._dropped,
                ignored_events=self._ignored, decoded=self._decoded, raw_complete=self._raw,
                decode_ns=self._decode_ns, pending=len(self._queue), pending_bytes=self._pending_bytes,
                inflight_bytes=self._inflight_bytes, queue_depth=self.depth,
                max_product_bytes=self.max_product_bytes, receiver_cohort=self.cohort,
                last_identity=None if self._last_identity is None else dict(self._last_identity),
                jpeg_record_dropped=self._jpeg_record_dropped, raw_record_dropped=self._raw_record_dropped,
                failure=self._failure, worker_done=self._done, worker_alive=self._thread.is_alive(),
                closing=self._closing, decode_enabled=self.decode,
                raw_preview=None if self._preview_snapshot is None else dict(self._preview_snapshot),
                hdmi_physical='NOT_RUN', raw_live_hdmi='NOT_IMPLEMENTED_STATIC_PGM_ONLY', board='NOT_RUN')
        if self.presenter is not None:
            result['presenter'] = self.presenter.snapshot()
        for name, recorder in (('jpeg_recorder', self.jpeg_recorder), ('raw_recorder', self.raw_recorder)):
            if recorder is not None:
                result[name] = recorder.snapshot()
        return result
