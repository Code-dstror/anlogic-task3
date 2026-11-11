"""Bounded mixed AJPG/LZC1 file checking and exclusive complete-product exports.

Only explicitly listed regular files/qualification outputs are consumed. There
is no glob, resynchronization, device open, fake JPEG decoder or Python LZ codec.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat

from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.product_receiver import JpegProduct, RawProduct
from linux.task3_pipeline.record_selection import header_length

from .products import MAX_RECORD_BYTES, ProductInspector


MAX_INPUT_BYTES = 64 * 1024 * 1024
MAX_REPORT_BYTES = 4 * 1024 * 1024
MAX_INPUT_FILES = 512
_SHA = re.compile(r'[0-9a-f]{64}\Z')


def _json(value, maximum=MAX_REPORT_BYTES):
    raw = (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode()
    if len(raw) > maximum:
        raise ValueError('JSON report byte bound exceeded')
    return raw


def _read_file(path, maximum):
    path = Path(path).absolute()
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_size > maximum:
        raise ValueError('input must be a bounded regular non-link file')
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_CLOEXEC', 0)
                 | getattr(os, 'O_NONBLOCK', 0))
    try:
        opened = os.fstat(fd)
        if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise ValueError('input identity changed before read')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(maximum + 1)
        after = os.fstat(fd)
        if (len(data) > maximum or len(data) != opened.st_size
                or (after.st_size, after.st_mtime_ns, after.st_ctime_ns)
                != (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns)):
            raise ValueError('input changed or exceeded byte bound')
        return data
    finally:
        os.close(fd)


@dataclass(frozen=True)
class SourceFile:
    path: Path
    sha256: str | None = None

    def __post_init__(self):
        if not isinstance(self.path, (str, Path)) or not 1 <= len(str(self.path)) <= 4096:
            raise ValueError('bounded explicit source path required')
        if self.sha256 is not None and (type(self.sha256) is not str or not _SHA.fullmatch(self.sha256)):
            raise ValueError('expected source SHA256 must be lowercase hex')


def iter_mixed_records(stream, *, max_record_bytes=MAX_RECORD_BYTES):
    """Frame a concatenated mixed stream using generated lengths; never recover.

    ProductInspector remains the strict parser/codec authority. A framing error
    terminates this file; arbitrary later SOI/magic bytes are never scanned for.
    """
    if type(max_record_bytes) is not int or not 1 <= max_record_bytes <= MAX_RECORD_BYTES:
        raise ValueError('invalid record byte bound')
    def exact(size):
        data = stream.read(size)
        if len(data) != size:
            raise ValueError('truncated mixed-record stream')
        return data
    while True:
        prefix = stream.read(4)
        if not prefix:
            return
        if len(prefix) != 4:
            raise ValueError('truncated product magic')
        magic = int.from_bytes(prefix, 'little')
        if magic == p.FRAME_MAGIC:
            base = prefix + exact(p.FRAME_HEADER_SIZE - 4)
            fields = dict(zip(p.FRAME_HEADER_FIELD_NAMES, p.FRAME_HEADER_STRUCT.unpack(base), strict=True))
            size = header_length(fields['protocol_version'])
            total = size + fields['payload_length']
            if not size <= total <= max_record_bytes:
                raise ValueError('AJPG framing byte bound exceeded')
            yield base + exact(total - len(base))
        elif magic == p.PCIE_LZ_MAGIC:
            base = prefix + exact(p.PCIE_LZ_HEADER_LENGTH - 4)
            fields = dict(zip(p.LZ_HEADER_FIELD_NAMES, p.LZ_HEADER_STRUCT.unpack(base), strict=True))
            total = fields['record_length']
            if not p.PCIE_LZ_HEADER_LENGTH <= total <= min(p.PCIE_LZ_MAX_RECORD_BYTES, max_record_bytes):
                raise ValueError('LZC1 framing byte bound exceeded')
            yield base + exact(total - len(base))
        else:
            raise ValueError('unknown mixed-record magic; no resynchronization')


def sources_from_qualification(path, *, repo_root):
    """Explicit outputs only, in recorded order. No source/RTL tree is scanned."""
    root = Path(repo_root).resolve(strict=True)
    raw = _read_file(path, 2 * 1024 * 1024)
    def unique_pairs(pairs):
        output = {}
        for key, value in pairs:
            if key in output:
                raise ValueError('duplicate qualification JSON key')
            output[key] = value
        return output
    document = json.loads(raw, object_pairs_hook=unique_pairs)
    rows = document.get('outputs') if type(document) is dict else None
    if (type(document) is not dict or type(document.get('status')) is not str
            or not document['status'].startswith('PASS') or type(rows) is not list
            or not 1 <= len(rows) <= MAX_INPUT_FILES):
        raise ValueError('qualification must name a bounded PASS output list')
    sources = []
    for row in rows:
        if type(row) is not dict or set(row) != {'path', 'sha256'} or type(row['path']) is not str:
            raise ValueError('invalid explicit qualification output')
        selected = root / row['path']
        if not selected.resolve(strict=True).is_relative_to(root) or Path(row['path']).is_absolute():
            raise ValueError('qualification output escaped explicit repository root')
        sources.append(SourceFile(selected, row['sha256']))
    return tuple(sources), dict(path=str(Path(path).absolute()), sha256=hashlib.sha256(raw).hexdigest(),
                               status=document['status'], scope='OUTPUT_HASH_BINDING_NOT_HARDWARE_QUALIFICATION')


class OwnedExporter:
    """New directory, complete products only; never overwrites or adopts a run."""
    def __init__(self, directory, *, max_bytes=MAX_INPUT_BYTES, max_files=128):
        if type(max_bytes) is not int or not 65536 <= max_bytes <= 1 << 30:
            raise ValueError('invalid export byte bound')
        if type(max_files) is not int or not 1 <= max_files <= 256:
            raise ValueError('invalid export file bound')
        self.directory = Path(directory).absolute()
        for parent in (self.directory, *self.directory.parents):
            if parent.is_symlink() or getattr(parent, 'is_junction', lambda: False)():
                raise ValueError('export directory must not traverse links')
        self.directory.mkdir(mode=0o700, exist_ok=False)
        self.max_bytes, self.max_files = max_bytes, max_files
        self.bytes = self.jpeg = self.raw = 0
        self.files = []

    def _write(self, name, data):
        temporary, final = self.directory / (name + '.partial'), self.directory / name
        if final.exists():
            raise FileExistsError('owned export filename already exists')
        with temporary.open('xb') as stream:
            if stream.write(data) != len(data):
                raise OSError('short product export; partial file retained')
            stream.flush()
            os.fsync(stream.fileno())
        temporary.rename(final)
        self.bytes += len(data)
        self.files.append(dict(path=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))

    def export(self, event):
        product = event.product
        if product is None:
            return
        if event.status != 'COMPLETE':
            raise ValueError('incomplete or rejected event cannot be exported')
        if isinstance(product, JpegProduct):
            name = f'jpeg-{self.jpeg + 1:06d}'
            payloads = ((name + '.jpg', product.record.jpeg), (name + '.ajpg', product.wire))
        elif isinstance(product, RawProduct):
            name = f'raw-{self.raw + 1:06d}'
            payloads = ((name + '.raw10', product.frame.raw),)
        else:
            raise TypeError('only owned complete JPEG/RAW products may be exported')
        payloads += ((name + '.json', _json(event.summary, 65536)),)
        if (self.bytes + sum(len(data) for _, data in payloads) + 65536 > self.max_bytes
                or len(self.files) + len(payloads) + 1 > self.max_files):
            raise ValueError('export budget exhausted; no new product files written')
        for filename, data in payloads:
            self._write(filename, data)
        if isinstance(product, JpegProduct):
            self.jpeg += 1
        else:
            self.raw += 1

    def finish(self):
        result = dict(format='RK_DEBUG_OWNED_EXPORT_V1', complete_jpeg=self.jpeg, complete_raw=self.raw,
                      files=list(self.files), payload_bytes=self.bytes,
                      media_durability='NOT_QUALIFIED', hardware='NOT_RUN')
        raw = _json(result, 65536)
        self._write('exports.json', raw)
        return result


def inspect_paths(paths, *, output_dir=None, report_path=None, lz_session=None, lz_epoch=None,
                  lz_library=None, expected_jpeg_version=None, max_records=100_000,
                  max_input_bytes=MAX_INPUT_BYTES, event_limit=64,
                  max_export_bytes=MAX_INPUT_BYTES, max_export_files=128):
    if type(paths) not in (tuple, list) or not 1 <= len(paths) <= MAX_INPUT_FILES:
        raise ValueError('bounded explicit input file list required')
    if type(max_input_bytes) is not int or not 1 <= max_input_bytes <= 1 << 30:
        raise ValueError('invalid total input byte bound')
    sources = tuple(item if isinstance(item, SourceFile) else SourceFile(item) for item in paths)
    if report_path is not None and os.path.lexists(report_path):
        raise FileExistsError('report already exists')
    inputs, errors, consumed = [], [], 0
    inspector = ProductInspector(expected_jpeg_version=expected_jpeg_version, lz_session=lz_session,
                                 lz_epoch=lz_epoch, lz_library=lz_library, max_records=max_records,
                                 event_limit=event_limit)
    exporter = None
    try:
        exporter = None if output_dir is None else OwnedExporter(output_dir, max_bytes=max_export_bytes, max_files=max_export_files)
        for source in sources:
            try:
                data = _read_file(source.path, max_input_bytes - consumed)
                consumed += len(data)
                sha = hashlib.sha256(data).hexdigest()
                inputs.append(dict(path=str(Path(source.path).absolute())[:512], bytes=len(data), sha256=sha,
                                   expected_sha256=source.sha256))
                if source.sha256 is not None and sha != source.sha256:
                    raise ValueError('input SHA256 differs from explicit qualification')
                if not data:
                    raise ValueError('empty input is not a record stream')
                for wire in iter_mixed_records(io.BytesIO(data)):
                    event = inspector.feed(wire)
                    if exporter is not None:
                        exporter.export(event)
            except (OSError, ValueError) as exc:
                errors.append(dict(path=str(source.path)[:512], reason=str(exc)[:512]))
                # Preserve a bounded error sample; counters distinguish omitted rows.
                if len(errors) >= 64:
                    break
        products = inspector.finish()
        incomplete = products['counters'].get('incomplete_lz_frames', 0)
        rejected = products['counters'].get('rejected', 0)
        negative = sum(products['counters'].get(name, 0) for name in
                       ('lz_negative_terminals', 'analysis_negative_terminals', 'analysis_frame_errors'))
        result = dict(format='RK_DEBUG_OFFLINE_V1', result='PASS' if not (errors or incomplete or rejected or negative) else 'FAIL',
                      inputs=inputs, input_bytes=consumed, errors=errors, products=products,
                      exports=None if exporter is None else exporter.finish(),
                      limits=dict(input_files=MAX_INPUT_FILES, input_bytes=max_input_bytes,
                                  report_bytes=MAX_REPORT_BYTES, error_rows=64),
                      scope='OFFLINE_STRICT_PARSING_NATIVE_LZ_AND_OWNED_EXPORT_NOT_DEVICE_OR_PIXEL_QUALIFICATION')
        raw = _json(result)
        if report_path is not None:
            with Path(report_path).open('xb') as stream:
                stream.write(raw)
        return result
    finally:
        inspector.close()


def inspect_qualification(path, *, repo_root, **options):
    sources, identity = sources_from_qualification(path, repo_root=repo_root)
    # Callers wanting a saved report should include this identity themselves;
    # default returned JSON preserves the original source-bound evidence link.
    report_path = options.pop('report_path', None)
    if report_path is not None and os.path.lexists(report_path):
        raise FileExistsError('report already exists')
    result = inspect_paths(sources, **options)
    result['qualification'] = identity
    raw = _json(result)
    if report_path is not None:
        with Path(report_path).open('xb') as stream:
            stream.write(raw)
    return result
