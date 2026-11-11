"""Explicit r3 debug commands. No device is opened by import or offline commands."""
from __future__ import annotations

import argparse
from dataclasses import fields
import json
import math
import os
from pathlib import Path
from queue import Empty, Queue
import re
import signal
import sys
import threading
import time
import uuid

from linux.task3_pipeline.advanced_config import AdvancedConfiguration
from linux.task3_pipeline.config_transaction import Configuration
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration
from .catalog import R3_SOURCE, parameter_catalog
from .journal import load_document, parse_document, public_value, save_report
from .products import PRODUCT_COUNTER_NAMES


RETAINED_OWNERS = []  # Keep native/file/DMA owners alive when safety is uncertain.


class TestGoalFailed(RuntimeError):
    """An observation target was not met; it is safe to request normal drain."""


def _positive(text):
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError('finite positive seconds required')
    return value


def _uint(text):
    if not re.fullmatch(r'(?:0|[1-9][0-9]*|0x[0-9a-fA-F]+)', text):
        raise argparse.ArgumentTypeError('unsigned decimal or 0x integer required')
    value = int(text, 16 if text.startswith('0x') else 10)
    if value > 0xffffffff: raise argparse.ArgumentTypeError('uint32 range exceeded')
    return value


def _bdf(text):
    if not re.fullmatch(r'[0-9a-f]{4}:[0-9a-f]{2}:[01][0-9a-f]\.[0-7]', text):
        raise argparse.ArgumentTypeError('canonical lowercase PCI BDF dddd:bb:ss.f required')
    return text


def build_parser():
    parser = argparse.ArgumentParser(description='r3 RK debug owner: explicit targets; guarded source reset opt-in, no rebind or model execution')
    sub = parser.add_subparsers(dest='command', required=True)
    catalog = sub.add_parser('catalog', help='static source-bound parameter catalogue; no device/native library')
    catalog.add_argument('--output', type=Path)
    preflight = sub.add_parser('preflight', help='Linux read-only inventory; no /dev or BAR access')
    preflight.add_argument('--library', type=Path, action='append', default=[])
    preflight.add_argument('--kernel-build', type=Path)
    preflight.add_argument('--output', type=Path)
    display = sub.add_parser('display-info', help='Linux read-only connector/plane query; no modeset, Receiver or MPP')
    display.add_argument('--modetest', type=Path, required=True, help='explicit trusted absolute modetest executable')
    display.add_argument('--timeout', type=_positive, required=True)
    display.add_argument('--driver', default='rockchip')
    display.add_argument('--max-output-bytes', type=int, default=65536)
    inspect = sub.add_parser('inspect', help='strict explicit files or qualification outputs; no device')
    source = inspect.add_mutually_exclusive_group(required=True)
    source.add_argument('--input', type=Path, action='append')
    source.add_argument('--qualification', type=Path)
    inspect.add_argument('--repo-root', type=Path, default=Path(__file__).resolve().parents[2])
    inspect.add_argument('--jpeg-version', type=int, choices=(1, 2, 3), default=3)
    inspect.add_argument('--session', type=_uint)
    inspect.add_argument('--epoch', type=_uint)
    inspect.add_argument('--lz-library', type=Path)
    inspect.add_argument('--max-records', type=int, default=100000)
    inspect.add_argument('--max-input-bytes', type=int, default=64*1024*1024)
    inspect.add_argument('--export-dir', type=Path)
    inspect.add_argument('--report-output', type=Path)
    for name in ('run', 'shell'):
        live = sub.add_parser(name, help='finite scripted capture' if name == 'run' else 'interactive same-owner session')
        live.add_argument('--device', required=True, help='explicit Linux C2H /dev path')
        live.add_argument('--expected-bdf', required=True, type=_bdf)
        live.add_argument('--jpeg-version', type=int, choices=(1, 2, 3, 4))
        live.add_argument('--shared-camera', choices=('mono','dual'),
                          help='R1 physical camera topology for this cold session; selects v4')
        live.add_argument('--shared-hdr-policy',type=Path,help='existing complete schema2 HDR file for the mode hdr shortcut')
        live.add_argument('--config-timeout', type=_positive, required=True)
        live.add_argument('--drain-timeout', type=_positive, required=True)
        live.add_argument('--command-timeout', type=_positive, required=True,
                          help='whole command wait budget; timeout retains process/owner, no retry')
        live.add_argument('--report-output', required=True, type=Path, help='new JSON file, never overwritten')
        live.add_argument('--config', type=Path, help='initial complete/patch JSON applied while receiving')
        live.add_argument('--max-records', type=int, default=200000)
        live.add_argument('--poll-seconds', type=_positive, default=.01)
        live.add_argument('--lz-library', type=Path, help='explicit native LZ library; also required before switching to LZ')
        live.add_argument('--allow-lab-hdr', action='store_true', help='permit digital LAB HDR only; no sensor exposure qualification')
        live.add_argument('--allow-source-reset', action='store_true',
                          help='opt into guarded debug-driver source reset after pause; never auto-resume')
        live.add_argument('--decode', action='store_true', help='explicitly create persistent MPP decoder')
        live.add_argument('--mpp-library', type=Path)
        live.add_argument('--mpp-timeout-ms', type=int)
        live.add_argument('--pixel-library', type=Path)
        live.add_argument('--connector-id', type=int)
        live.add_argument('--plane-id', type=int)
        live.add_argument('--gst-colorimetry', help='explicit GStreamer colorimetry matching the NV12 source; never guessed')
        live.add_argument('--consumer-queue-depth', type=int, default=2)
        live.add_argument('--consumer-close-timeout', type=_positive, default=1,
                          help='owned consumer sink close budget, at most10 seconds')
        live.add_argument('--jpeg-record-dir', type=Path, help='new bounded MJPEG recording directory')
        live.add_argument('--raw-record-dir', type=Path, help='new bounded complete RAW10 recording directory')
        live.add_argument('--raw-preview-dir', type=Path, help='new bounded PGM inspection directory, not live RAW HDMI')
        live.add_argument('--raw-preview-max-frames', type=int, default=1)
        live.add_argument('--raw-preview-max-bytes', type=int, default=4*1024*1024)
        if name == 'run':
            live.add_argument('--max-seconds', type=_positive, required=True)
            live.add_argument('--script', type=Path, help='version1 JSON steps, at most128; no eval')
    return parser


def _new_path(path, *, directory=False):
    path = Path(path).absolute()
    if os.path.lexists(path): raise ValueError('output already exists: ' + str(path))
    if not path.parent.is_dir(): raise ValueError('output parent must already exist: ' + str(path.parent))
    for part in (path, *path.parents):
        if part.is_symlink() or getattr(part, 'is_junction', lambda: False)():
            raise ValueError('output path must not traverse links: ' + str(path))
    return path


def validate_config_shape(document):
    """Reject typos before native/device construction; live semantic checks remain CFG's job."""
    if type(document) is not dict or set(document) - {'schema', 'base', 'extension'}:
        raise ValueError('configuration accepts only schema/base/extension')
    if 'schema' in document and (type(document['schema']) is not int or document['schema'] not in (0, 1, 2)):
        raise ValueError('configuration schema must be integer0/1/2')
    for section, cls in (('base', Configuration), ('extension', None)):
        patch = document.get(section, {})
        if section == 'extension' and patch is None and document.get('schema') == 0: continue
        if type(patch) is not dict: raise ValueError(section + ' must be an object')
        extension_classes = ((AdvancedConfiguration,) if document.get('schema') == 1 else
                             (MonoConfiguration,) if document.get('schema') == 2 else
                             (AdvancedConfiguration, MonoConfiguration))
        names = ({f.name for f in fields(cls)} if cls else
                 {f.name for item in extension_classes for f in fields(item)})
        if section == 'extension' and document.get('schema') == 0 and patch:
            raise ValueError('schema0 requires an empty/null extension')
        if set(patch) - names: raise ValueError('unknown ' + section + ' parameter')
        for name, value in patch.items():
            if type(value) in (bool, float, dict) or value is None:
                raise ValueError('configuration parameters require exact integer/symbol values')
            if type(value) not in (int, str, list, tuple): raise ValueError('invalid configuration value')
            if type(value) is str and len(value) > 64: raise ValueError('configuration scalar too long')
            if type(value) in (list, tuple) and (len(value) > 8 or
                    any(type(v) not in (int, str) for v in value)):
                raise ValueError('invalid bounded vector/flag list')
    return document


def load_steps(path):
    doc = load_document(path)
    if (type(doc) is not dict or set(doc) != {'version', 'steps'} or type(doc['version']) is not int
            or doc['version'] != 1 or type(doc['steps']) is not list or not 1 <= len(doc['steps']) <= 128):
        raise ValueError('script requires version1 and1..128 steps')
    result = []
    for step in doc['steps']:
        if type(step) is not dict or type(step.get('op')) is not str:
            raise ValueError('invalid script step')
        op = step['op']
        if op in ('expect', 'wait-for'):
            comparator = 'equals' if 'equals' in step else 'at_least'
            expected = {'op', 'path', comparator} | ({'timeout_s'} if op == 'wait-for' else set())
            if (type(step.get('path')) is not str or len(step['path']) > 128 or
                    not re.fullmatch(r'[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+){0,7}', step['path'])):
                raise ValueError('assertion requires a bounded dictionary path')
            if (step['path'].startswith('products.counters.') and
                    step['path'].removeprefix('products.counters.') not in PRODUCT_COUNTER_NAMES):
                raise ValueError('unknown product counter in assertion')
            target = step.get(comparator)
            if comparator == 'at_least' and (type(target) not in (int, float) or not math.isfinite(target)):
                raise ValueError('at_least requires a finite numeric target')
            if comparator == 'equals' and (type(target) not in (str, int, bool, type(None)) or
                    type(target) is str and len(target) > 128):
                raise ValueError('equals requires a bounded scalar')
        elif op == 'wait-product':
            expected = {'op', 'kind', 'epoch', 'timeout_s'} | ({'at_least'} if 'at_least' in step else set())
            if step.get('kind') not in ('JPEG', 'RAW') or step.get('epoch') != 'active':
                raise ValueError('wait-product requires kind JPEG/RAW and epoch active')
            if type(step.get('at_least', 1)) is not int or not 1 <= step.get('at_least', 1) <= 64:
                raise ValueError('wait-product count must be1..64')
        else:
            expected = {'op', 'configuration'} if op == 'configure' else (
                {'op', 'generation'} if op == 'load-lut' else {'op', 'seconds'} if op == 'wait' else {'op'})
        if set(step) != expected or op not in ('configure', 'active', 'discover', 'load-lut', 'query-lut',
                                              'pause', 'resume', 'source-reset', 'status', 'wait', 'expect', 'wait-for', 'wait-product'):
            raise ValueError('unknown script operation or argument')
        if op in ('wait-for', 'wait-product') and (type(step['timeout_s']) not in (int, float) or
                not math.isfinite(step['timeout_s']) or not 0 < step['timeout_s'] <= 3600):
            raise ValueError('observation timeout must be positive and at most3600 seconds')
        if op == 'configure': validate_config_shape(step['configuration'])
        if op == 'load-lut' and (type(step['generation']) is not int or not 1 <= step['generation'] <= 0xffffffff):
            raise ValueError('load-lut generation must be a nonzero uint32')
        if op == 'wait' and (type(step['seconds']) not in (int, float) or
                not math.isfinite(step['seconds']) or not 0 <= step['seconds'] <= 60):
            raise ValueError('script wait must be0..60 finite seconds')
        result.append(step)
    return tuple(result)


def validate_options(args):
    if args.command == 'display-info':
        if not args.modetest.is_absolute(): raise ValueError('--modetest must be an explicit absolute executable path')
        if not .01 <= args.timeout <= 30: raise ValueError('display query timeout must be0.01..30 seconds')
        if not 1 <= args.max_output_bytes <= 4*1024*1024: raise ValueError('display output bound must be1..4MiB')
        if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}', args.driver):
            raise ValueError('bounded option-free DRM driver name required')
        return ()
    if args.command in ('catalog', 'preflight'):
        if args.output: _new_path(args.output)
        if args.command == 'preflight' and len(args.library) > 8: raise ValueError('at most eight libraries')
        return ()
    if args.report_output: _new_path(args.report_output)
    if not 1 <= args.max_records <= 1000000: raise ValueError('max-records must be1..1000000')
    if args.command == 'inspect':
        selected = (args.session is not None, args.epoch is not None, args.lz_library is not None)
        if any(selected) and not all(selected): raise ValueError('LZ inspection requires session, epoch and library together')
        if args.session == 0: raise ValueError('LZ session must be nonzero')
        if args.input and len(args.input) > 512: raise ValueError('at most512 explicit input files')
        if not 1 <= args.max_input_bytes <= 1 << 30: raise ValueError('input byte budget must be1..1GiB')
        if args.export_dir: _new_path(args.export_dir, directory=True)
        return ()
    if not args.device or len(args.device) > 4096: raise ValueError('bounded explicit device path required')
    if args.allow_source_reset and args.config_timeout > 60:
        raise ValueError('source-reset requires --config-timeout at most60 seconds')
    if not 1 <= args.consumer_queue_depth <= 8: raise ValueError('consumer queue depth must be1..8')
    if args.consumer_close_timeout > 10: raise ValueError('consumer close timeout must be at most10 seconds')
    if not 1 <= args.raw_preview_max_frames <= 16: raise ValueError('raw preview frame limit must be1..16')
    if not 1 <= args.raw_preview_max_bytes <= 64*1024*1024: raise ValueError('raw preview byte limit must be1..64MiB')
    if args.jpeg_version is None:
        args.jpeg_version = 4 if args.shared_camera else 3
    if (args.jpeg_version == 4) != bool(args.shared_camera):
        raise ValueError('R1 shared-camera sessions select v4; existing r3 sessions select v1/v2/v3')
    if args.shared_camera and (args.lz_library or args.allow_lab_hdr or args.allow_source_reset):
        raise ValueError('R1 uses physical SDR/HDR and the existing cold session')
    if args.shared_hdr_policy and not args.shared_camera:
        raise ValueError('--shared-hdr-policy requires --shared-camera')
    if args.decode != (args.mpp_library is not None and args.mpp_timeout_ms is not None):
        raise ValueError('--decode requires explicit --mpp-library and --mpp-timeout-ms')
    if not args.decode and (args.mpp_library is not None or args.mpp_timeout_ms is not None):
        raise ValueError('MPP arguments require --decode')
    if args.mpp_timeout_ms is not None and not 1 <= args.mpp_timeout_ms <= 7999:
        raise ValueError('MPP timeout must be1..7999 milliseconds')
    display = (args.connector_id, args.plane_id, args.gst_colorimetry, args.pixel_library)
    if any(value is not None for value in display):
        if not args.decode or not all(value is not None for value in display):
            raise ValueError('HDMI requires decode, explicit connector/plane/colorimetry/pixel library')
        if args.connector_id <= 0 or args.plane_id <= 0 or not args.gst_colorimetry.strip():
            raise ValueError('positive connector/plane and nonempty colorimetry required')
    paths = [Path(path).absolute() for path in (args.jpeg_record_dir, args.raw_record_dir, args.raw_preview_dir) if path]
    for path in paths: _new_path(path, directory=True)
    if any(a == b or a in b.parents or b in a.parents for index, a in enumerate(paths) for b in paths[index+1:]):
        raise ValueError('record and preview directories must be distinct and nonnested')
    if (args.raw_record_dir or args.raw_preview_dir) and args.lz_library is None:
        raise ValueError('RAW consumers require an explicit LZ library')
    for library in (args.lz_library, args.mpp_library, args.pixel_library):
        if library is not None and not library.is_file(): raise ValueError('explicit library file missing: ' + str(library))
    steps = list(load_steps(args.script)) if args.command == 'run' and args.script else []
    if args.config:
        steps.insert(0, {'op': 'configure', 'configuration': validate_config_shape(load_document(args.config))})
    if len(steps) > 128: raise ValueError('initial configuration plus script exceeds128 steps')
    return tuple(steps)


class ResourceOwner:
    def __init__(self, resources, failure): self.resources, self.failure = resources, str(failure)[:512]
    def snapshot(self):
        return dict(state='FAULTED', ownership_retained=True, failure=self.failure,
                    resource_names=[name for name, _ in self.resources])


class StartupRetained(RuntimeError):
    def __init__(self, owner): self.owner = owner; super().__init__(owner.failure)


class NativeFactory:
    actual_run = True

    def consumers(self, args):
        if not any((args.decode, args.jpeg_record_dir, args.raw_record_dir, args.raw_preview_dir)):
            return None
        from .consumers import DebugConsumers
        decoder = pixels = presenter = jpeg = raw = consumer = None
        created = []
        cohort = 'rk-debug-' + uuid.uuid4().hex
        try:
            if args.decode:
                from linux.stream_diag.decoder import PersistentMppDecoder
                decoder = PersistentMppDecoder(args.mpp_library, max_width=1920, max_height=1080,
                                               timeout_ms=args.mpp_timeout_ms)
                created.append(('decoder', decoder))
            if args.connector_id is not None:
                from linux.pixel_native import NativePixels
                from linux.stream_diag.presentation import GstKmsPresenter
                pixels = NativePixels(args.pixel_library)
                presenter = GstKmsPresenter(width=1920, height=1080, connector_id=args.connector_id,
                    plane_id=args.plane_id, colorimetry=args.gst_colorimetry, force_modesetting=False)
                created.append(('presenter', presenter))
            if args.jpeg_record_dir:
                from linux.task3_runtime.recording import BoundedRecorderWorker
                jpeg = BoundedRecorderWorker(args.jpeg_record_dir, receiver_cohort=cohort,
                                              jpeg_version=args.jpeg_version).start()
                created.append(('jpeg_recorder', jpeg))
            if args.raw_record_dir:
                from linux.task3_runtime.raw_recording import BoundedRawRecorderWorker
                raw = BoundedRawRecorderWorker(args.raw_record_dir, receiver_cohort=cohort).start()
                created.append(('raw_recorder', raw))
            deadline = time.monotonic() + args.drain_timeout
            for recorder in (jpeg, raw):
                if recorder is None: continue
                while recorder.snapshot()['state'] in ('NEW', 'STARTING'):
                    if time.monotonic() >= deadline: raise TimeoutError('recorder startup budget exceeded')
                    time.sleep(.005)
                if recorder.snapshot()['state'] != 'RUNNING': raise RuntimeError('recorder startup failed')
            consumer = DebugConsumers(decode=args.decode, decoder=decoder, pixels=pixels, presenter=presenter,
                jpeg_recorder=jpeg, raw_recorder=raw, receiver_cohort=cohort, jpeg_version=args.jpeg_version,
                queue_depth=args.consumer_queue_depth, raw_preview_dir=args.raw_preview_dir,
                raw_preview_max_frames=args.raw_preview_max_frames, raw_preview_max_bytes=args.raw_preview_max_bytes,
                close_worker_timeout_s=args.consumer_close_timeout)
            consumer.check()
            return consumer
        except BaseException as error:
            failures = []
            if consumer is not None:
                try:
                    if not consumer.close(timeout_s=args.drain_timeout).get('worker_done'):
                        raise RuntimeError('consumer startup owner remains active')
                except BaseException as close_error:
                    raise StartupRetained(ResourceOwner([('consumers', consumer)], close_error)) from error
                raise
            for name, resource in reversed(created):
                try:
                    result = resource.close() if name == 'decoder' else resource.close(timeout_s=args.drain_timeout)
                    if isinstance(result, dict) and not result.get('worker_done', True):
                        failures.append(name + ' still active')
                except BaseException as close_error: failures.append(str(close_error))
            if failures: raise StartupRetained(ResourceOwner(created, '; '.join(failures))) from error
            raise

    def receiver(self, args):
        from linux.dma_c2h_candidate.receiver import Receiver
        return Receiver(args.device, nonblocking=True)

    def session(self, receiver, args, consumers):
        if args.shared_camera:
            from dual_host.debug_modes import SharedDebugSession
            return SharedDebugSession(receiver, topology=args.shared_camera, jpeg_version=args.jpeg_version,
                config_timeout_s=args.config_timeout, drain_timeout_s=args.drain_timeout, consumers=consumers,
                expected_bdf=args.expected_bdf, max_records=args.max_records, poll_seconds=args.poll_seconds)
        from .session import DebugSession
        return DebugSession(receiver, jpeg_version=args.jpeg_version, config_timeout_s=args.config_timeout,
            drain_timeout_s=args.drain_timeout, consumers=consumers, lz_library=args.lz_library,
            allow_lab_hdr=args.allow_lab_hdr, expected_bdf=args.expected_bdf,
            max_records=args.max_records, poll_seconds=args.poll_seconds,
            allow_source_reset=args.allow_source_reset)


def _emit(value, output):
    output.write(json.dumps(public_value(value), ensure_ascii=False, allow_nan=False) + '\n')
    output.flush()


def hold_retained_owner(owner, report, *, output=sys.stderr):
    """Intentionally never exits on EOF, SIGINT or SIGTERM; no hidden close path."""
    try:
        _emit({'state': 'OWNERSHIP_RETAINED', 'action': 'process retained; no retry/reset/close',
               'report_error': report.get('report_error')}, output)
    except Exception: pass
    while True:
        try: threading.Event().wait(1)
        except KeyboardInterrupt:
            try: _emit({'state': 'OWNERSHIP_RETAINED', 'action': 'interrupt did not prove safe release'}, output)
            except Exception: pass


def _retain(owner, report, args, hold, output):
    if not any(item is owner for item in RETAINED_OWNERS): RETAINED_OWNERS.append(owner)
    report = dict(report, ownership_retained=True)
    try: save_report(args.report_output, report)
    except Exception as error: report['report_error'] = type(error).__name__ + ': ' + str(error)[:512]
    try: _emit(report, output)
    except Exception: pass  # A broken status pipe cannot release a retained native owner.
    hold(owner, report, output=output)
    raise RuntimeError('retained-owner handler must not return')


def _safe_snapshot(session):
    try:
        return session.snapshot()
    except Exception as error:
        return dict(state='FAULTED', ownership_retained=True,
                    failure={'phase': 'CLI_STATUS_UNAVAILABLE', 'error': str(error)[:512]})


def _faulted(session):
    state = _safe_snapshot(session)
    return state if state.get('failure') or state.get('state') == 'FAULTED' else None


def _wait_capture(session, seconds, stop, *, clock=time.monotonic):
    deadline = clock() + seconds
    while not stop.is_set() and clock() < deadline:
        fault = _faulted(session)
        if fault: raise RuntimeError('live debug session faulted')
        stop.wait(min(.05, max(0, deadline-clock())))


def _lookup(snapshot, path):
    # 'base' is the documented convenience alias of ActiveConfiguration.
    path = path.replace('active.base.', 'active.configuration.', 1)
    current = snapshot
    components = path.split('.')
    for index, name in enumerate(components):
        if not isinstance(current, dict) or name not in current:
            if (index == 2 and components[:2] == ['products', 'counters']
                    and len(components) == 3 and name in PRODUCT_COUNTER_NAMES and isinstance(current, dict)):
                return 0
            raise TestGoalFailed('status path is unavailable: ' + path)
        current = current[name]
    return current


def _observe(session, step, budget, stop):
    deadline = time.monotonic() + min(step.get('timeout_s', 0), budget)
    active = _safe_snapshot(session).get('active') if step['op'] == 'wait-product' else None
    if step['op'] == 'wait-product' and (not isinstance(active, dict) or
            type(active.get('session')) is not int or type(active.get('mode_epoch')) is not int):
        raise TestGoalFailed('wait-product requires an actual active SOURCE session/epoch')
    while True:
        snapshot = _safe_snapshot(session)
        if snapshot.get('failure') or snapshot.get('state') == 'FAULTED':
            raise RuntimeError('session faulted during observation')
        if step['op'] == 'wait-product':
            counter = 'jpeg_complete' if step['kind'] == 'JPEG' else 'raw_complete'
            value = sum(item.get(counter, 0) for item in snapshot.get('observed_products', [])
                        if item.get('source_session') == active['session'] and
                        item.get('source_epoch') == active['mode_epoch'])
            passed = value >= step.get('at_least', 1)
        else:
            value = _lookup(snapshot, step['path'])
            passed = value == step['equals'] if 'equals' in step else (
                type(value) in (int, float) and value >= step['at_least'])
        if passed:
            return dict(assertion='PASS', observed=value, source_session=None if active is None else active['session'],
                        source_epoch=None if active is None else active['mode_epoch'])
        if step['op'] == 'expect' or stop.is_set() or time.monotonic() >= deadline:
            raise TestGoalFailed('observation target not met: ' + json.dumps(step, sort_keys=True))
        stop.wait(min(.02, max(0, deadline-time.monotonic())))


def _execute(session, step, budget, stop):
    op = step['op']
    if op in ('expect', 'wait-for', 'wait-product'): return _observe(session, step, budget, stop)
    if op == 'status': return _safe_snapshot(session)
    if op == 'wait': return _wait_capture(session, step['seconds'], stop)
    if op == 'pause': return session.pause(timeout_s=budget)
    if op == 'resume': return session.resume()
    if op == 'source-reset': return session.source_reset()
    value = step.get('configuration') if op == 'configure' else step.get('generation')
    return session.submit(op, value).wait(budget)


def _shell_step(line, *, shared_camera=None, hdr_policy=None):
    items = line.strip().split(maxsplit=1)
    if not items: return None
    op, value = items[0], items[1] if len(items) == 2 else None
    if op == 'quit' and value is None: return {'op': 'quit'}
    if op == 'caps': op = 'discover'
    if op == 'mode' and shared_camera:
        from dual_host.debug_modes import mode_document
        return {'op':'configure','configuration':mode_document(value or '', shared_camera, hdr_policy)}
    if op == 'configure':
        if value is None: raise ValueError('configure requires JSON or @file/path')
        document = parse_document(value) if value.startswith('{') else load_document(value.removeprefix('@'))
        return {'op': op, 'configuration': validate_config_shape(document)}
    if op == 'load-lut' and value is not None:
        generation = _uint(value)
        if not generation: raise ValueError('nonzero LUT generation required')
        return {'op': op, 'generation': generation}
    if op in ('active', 'discover', 'query-lut', 'pause', 'resume', 'source-reset', 'status') and value is None:
        return {'op': op}
    raise ValueError('commands: configure JSON/@file, status, active, caps, load-lut N, query-lut, pause, source-reset, resume, quit')


class _ShellInput:
    """One requested bounded line on a daemon holding stdin only, never hardware.

    Closing only revokes future reads. An external blocked readline is neither
    killed nor closed; it may return later and then exits without executing input.
    """
    def __init__(self, stream):
        self.stream = stream
        self.items, self.requested, self.closing = Queue(maxsize=1), threading.Event(), threading.Event()
        self.pending, self.failed = False, False
        self.worker = threading.Thread(target=self._read, name='rk-debug-stdin-only', daemon=True)
        self.worker.start()

    def _read(self):
        while True:
            self.requested.wait()
            self.requested.clear()
            if self.closing.is_set(): return
            terminal = False
            try:
                line = self.stream.readline(65538)
                if type(line) is not str or len(line.encode('utf-8')) > 65536:
                    raise ValueError('shell input exceeds64 KiB or is not text; further reads revoked')
                item = ('line', line)
                terminal = not line
            except Exception as error:
                item, terminal = ('error', type(error).__name__ + ': ' + str(error)[:512]), True
            if self.closing.is_set(): return
            self.items.put_nowait(item)
            if terminal: return

    def poll(self, output):
        if self.failed: return ('line', '')
        if not self.pending:
            output.write('rk-debug> '); output.flush()
            self.pending = True
            self.requested.set()
        try: item = self.items.get(timeout=.05)
        except Empty: return None
        self.pending = False
        self.failed = item[0] == 'error'
        return item

    def close(self):
        self.closing.set()
        self.requested.set()


def run_owned(args, steps, *, factory, input_stream=sys.stdin, output=sys.stdout,
              hold=hold_retained_owner, stop=None):
    stop = threading.Event() if stop is None else stop
    session = receiver = consumers = shell_input = None
    errors, assertions, completed_steps = [], [], 0
    saved_handlers = {}
    try:
        if threading.current_thread() is threading.main_thread():
            for sig in (signal.SIGINT, signal.SIGTERM):
                saved_handlers[sig] = signal.signal(sig, lambda *_: stop.set())
        try:
            consumers = factory.consumers(args)  # Construct and check consumers before opening C2H.
            receiver = factory.receiver(args)
            session = factory.session(receiver, args, consumers)
            session.prepare()
            session.start()
        except StartupRetained as error:
            return _retain(error.owner, error.owner.snapshot(), args, hold, output)
        except BaseException as error:
            if session is not None:
                return _retain(session, dict(_safe_snapshot(session), cli_error=str(error)[:512]), args, hold, output)
            if receiver is not None:
                owner = ResourceOwner([('receiver', receiver), ('consumers', consumers)], error)
                return _retain(owner, owner.snapshot(), args, hold, output)
            if consumers is not None:
                try:
                    result = consumers.close(timeout_s=args.drain_timeout)
                    if not result.get('worker_done'): raise RuntimeError('consumer startup owner remains active')
                except BaseException as close_error:
                    owner = ResourceOwner([('consumers', consumers)], close_error)
                    return _retain(owner, owner.snapshot(), args, hold, output)
            raise
        deadline = time.monotonic() + args.max_seconds if args.command == 'run' else None
        pending_steps = iter(steps)
        scripted = True
        while not stop.is_set():
            fault = _faulted(session)
            if fault: return _retain(session, fault, args, hold, output)
            if deadline is not None and time.monotonic() >= deadline: break
            try:
                if scripted:
                    try: step = next(pending_steps)
                    except StopIteration:
                        scripted = False
                        continue
                elif args.command == 'run':
                    _wait_capture(session, max(0, deadline-time.monotonic()), stop)
                    break
                else:
                    if shell_input is None: shell_input = _ShellInput(input_stream)
                    item = shell_input.poll(output)
                    if item is None: continue
                    if stop.is_set(): break
                    if _faulted(session): continue  # Next loop retains without executing queued input.
                    if item[0] == 'error': raise ValueError(item[1])
                    line = item[1]
                    if not line: break  # normal EOF requests a real drain, never a force close
                    step = _shell_step(line, shared_camera=args.shared_camera, hdr_policy=args.shared_hdr_policy)
                    if step is None: continue
                    if step['op'] == 'quit': break
                budget = args.command_timeout if deadline is None else min(args.command_timeout, max(.001, deadline-time.monotonic()))
                if step['op'] in ('wait-for', 'wait-product'):
                    budget = step['timeout_s'] if deadline is None else min(step['timeout_s'], max(0, deadline-time.monotonic()))
                if step['op'] == 'wait' and deadline is not None:
                    step = dict(step, seconds=min(step['seconds'], max(0, deadline-time.monotonic())))
                result = _execute(session, step, budget, stop)
                if scripted: completed_steps += 1
                if step['op'] in ('expect', 'wait-for', 'wait-product'):
                    assertions.append({'step': step, 'result': result})
                _emit({'operation': step['op'], 'result': result}, output)
            except TimeoutError as error:
                return _retain(session, dict(_safe_snapshot(session), cli_error=str(error)[:512],
                    reason='COMMAND_OR_PAUSE_UNCONFIRMED_NO_RETRY'), args, hold, output)
            except Exception as error:
                fault = _faulted(session)
                if fault: return _retain(session, dict(fault, cli_error=str(error)[:512]), args, hold, output)
                errors.append(type(error).__name__ + ': ' + str(error)[:512])
                errors = errors[-128:]
                _emit({'command_rejected': errors[-1], 'session_preserved': True}, output)
                if scripted:
                    pending_steps = iter(())  # do not run dependent script steps after a rejection
        if completed_steps < len(steps) and not errors:
            errors.append('explicit run/signal budget ended before all script steps completed')
        report = session.close()
        report = dict(report, cli_errors=errors, clock_scope='HOST_BUDGET_NOT_SENSOR_OR_PHYSICAL_HDMI_TIME')
        report['script_steps'] = {'planned': len(steps), 'completed': completed_steps}
        if report.get('ownership_retained'):
            return _retain(session, report, args, hold, output)
        report['test_result'] = 'FAIL' if errors else 'PASS' if assertions else 'COMPLETED_WITHOUT_ASSERTIONS'
        report['assertions'] = assertions
        report['verification_scope'] = 'EXPLICIT_SCRIPT_OBSERVATIONS_NOT_ALL_FUNCTIONS_OR_PHYSICAL_QUALIFICATION'
        save_report(args.report_output, report)
        _emit(report, output)
        return 2 if errors else 0
    except Exception as error:
        if session is not None and _safe_snapshot(session).get('ownership_retained'):
            return _retain(session, dict(_safe_snapshot(session), cli_error=str(error)[:512]), args, hold, output)
        raise
    finally:
        # Revoke stdin reads and restore handlers only; never close hardware here.
        if shell_input is not None: shell_input.close()
        for sig, previous in saved_handlers.items(): signal.signal(sig, previous)


def main(argv=None, *, factory=None, input_stream=sys.stdin, output=sys.stdout, hold=hold_retained_owner):
    parser = build_parser()
    args = parser.parse_args(argv)
    try: steps = validate_options(args)
    except (OSError, ValueError) as error: parser.error(str(error))
    try:
        if args.command == 'display-info':
            from .display_info import inspect_display
            result = inspect_display(args.modetest, args.driver, timeout_s=args.timeout,
                                     max_output_bytes=args.max_output_bytes)
            _emit(result, output)
            return 0 if result['status'] == 'QUERY_COMPLETED' else 2
        if args.command == 'catalog':
            result = dict(format='RK_DEBUG_CATALOG_V1', source_reference=R3_SOURCE, parameters=parameter_catalog(),
                          scope='STATIC_SOURCE_REFERENCE_NOT_DEVICE_CAPABILITIES')
            if args.output: save_report(args.output, result)
            _emit(result, output)
            return 0
        if args.command == 'preflight':
            if sys.platform != 'linux': raise ValueError('actual host inventory requires Linux')
            from linux.task3_runtime.preflight import inspect_host
            result = inspect_host(libraries=args.library, kernel_build=args.kernel_build)
            if args.output: save_report(args.output, result)
            _emit(result, output)
            return 0
        if args.command == 'inspect':
            from .offline import inspect_paths, inspect_qualification
            options = dict(output_dir=args.export_dir, report_path=args.report_output,
                lz_session=args.session, lz_epoch=args.epoch, lz_library=args.lz_library,
                expected_jpeg_version=args.jpeg_version, max_records=args.max_records,
                max_input_bytes=args.max_input_bytes)
            result = (inspect_qualification(args.qualification, repo_root=args.repo_root, **options)
                      if args.qualification else inspect_paths(args.input, **options))
            _emit(result, output)
            return 0 if result['result'] == 'PASS' else 2
        factory = NativeFactory() if factory is None else factory
        if getattr(factory, 'actual_run', True) and sys.platform != 'linux':
            raise ValueError('native run/shell requires Linux; no device or network fallback')
        return run_owned(args, steps, factory=factory, input_stream=input_stream, output=output, hold=hold)
    except (OSError, ValueError, RuntimeError) as error:
        _emit({'error': type(error).__name__ + ': ' + str(error)[:512]}, output)
        return 2


if __name__ == '__main__': raise SystemExit(main())
