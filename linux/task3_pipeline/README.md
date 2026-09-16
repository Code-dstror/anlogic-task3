# Task 3 Python pipeline foundation

This package is the Python foundation shared by the Ubuntu host and the future
RK3576 target. It contains shared data types, contracts, exceptions, metrics,
the Stage-B `MockFileFrameSource` and `MockProtocolRecordSource`, Stage-C JPEG
validation and decoding, and pure-memory PCIe v1 record parsing and
`EncodedFrame` mapping. It does not access SGDMA devices or invoke RKNN.

Run from the repository root with Python 3.10 or newer:

```bash
python3 -m compileall linux/task3_pipeline tests
python3 -m unittest discover
```

The package is imported as `linux.task3_pipeline` when commands are run from
the repository root.  Target deployment packaging is deliberately deferred
until the board runtime and deployment contract are available.

The `OpenCvJpegDecoder` runtime dependency is `cv2` (OpenCV) plus `numpy`.
They are environment-provided dependencies; this package does not install them.

## PCIe v1 record parsing

`PcieV1RecordParser.parse(record)` validates and parses one caller-assembled,
complete v1 `[64-byte header][payload]` buffer and returns an immutable
`PcieV1Record`. It snapshots bytes supplied through `bytes`, `bytearray`, or
`memoryview`; payload CRC, timestamp, compression, pixel format, quality,
status, error code, and slot ID remain opaque wire values.

`map_pcie_v1_record_to_encoded_frame(record, *, ingest_id,
received_monotonic_ns, source_name)` is the separate, pure-memory bridge to
an `EncodedFrame`. The caller provides the local ID and monotonic receive time;
the wire sequence remains separate metadata. Zero wire width or height maps to
an absent declared dimension (`None`). Wire `timestamp_ns`, including zero, is
preserved as `source_timestamp`, but its `timestamp_domain` is `None`. The
declared CRC is retained with an explicit unverified integrity marker, while
compression, pixel format, quality, and status remain raw `pcie_v1_*`
extension values. `encoding` remains `None`: this mapping does not establish
that the payload is JPEG.

Neither parsing nor mapping accesses SGDMA, assumes one `read()` or completion
is one frame, or manages slot/DMA ownership. In particular, slot ID remains in
the private `PcieV1Record` and is not public frame metadata. JPEG validation
and decoding remain later stages.

## In-memory protocol-record mock input

`MockProtocolRecordSource(records, *, clock=...)` is a deterministic
`FrameSource` for transport tests. Each item must already be exactly one
complete PCIe v1 `[64-byte header][payload]` record; it does not accept chunks,
perform cross-read assembly, or access a device. On each `next_frame()` call it
consumes one item, uses `PcieV1RecordParser` and
`map_pcie_v1_record_to_encoded_frame`, and publishes the resulting `FRAME`
event. The optional monotonic clock is injectable for deterministic tests.

The source preserves parser bytes-like behavior for `bytes`, `bytearray`, and
`memoryview`. Parser or mapper `ValidationError`s escape unchanged after that
one input is consumed. The existing pipeline and lifecycle runner therefore
remain the only place that classifies allowlisted invalid transport records and
records their metrics. Successful frames receive local, monotonically
increasing `ingest_id` values independently of wire `frame_sequence`; restarts
replay records while continuing the local ID sequence. EOF, stop, restart, and
close behavior matches `MockFileFrameSource`.

## JPEG payload boundary validation

`JpegPayloadValidator(max_payload_length)` accepts an `EncodedFrame` and
returns that same object when its non-empty payload is at least four bytes,
starts with JPEG SOI (`FF D8`), ends with JPEG EOI (`FF D9`), and does not
exceed the inclusive caller-configured byte limit.  The limit must be a
non-boolean integer no smaller than four; it is deliberately not derived from
an FPGA slot, image resolution, or an unconfirmed project threshold.

This is a lightweight boundary check only.  It does not decode JPEG, establish
that the bytes form a decodable image, inspect image contents, or parse/require
a PCIe protocol record, magic, version, or header.  In particular, the
four-byte `FF D8 FF D9` payload passes this stage; a later JPEG decoder decides
whether it is decodable.

## OpenCV JPEG decoding

`OpenCvJpegDecoder.decode(frame)` decodes an `EncodedFrame` that the caller has
already passed through `JpegPayloadValidator`. It uses OpenCV's `IMREAD_COLOR`
mode, so successful output is always C-contiguous BGR24, including for
grayscale JPEG input. `DecodedFrame.pixel_format` is `"bgr24"`; `row_stride`
is the byte count of one row in the final contiguous pixel buffer
(`width * 3`). The decoder preserves the source metadata, including `ingest_id`
and optional `wire_sequence`.

The decoder does not repeat SOI/EOI or maximum-payload checks, parse PCIe
records, or treat successful boundary validation as proof that JPEG decoding
will succeed. A future `Preprocessor` owns color conversion, resize, and
normalization.

## Bare-JPEG mock input

`MockFileFrameSource` requires exactly one of `files` or `directory`.  It
reads each configured ordinary `.jpg`/`.jpeg` file once and publishes a bare
`EncodedFrame`; it does not inspect JPEG markers or create a PCIe header.

An explicit list retains its supplied order, rejects non-JPEG paths, and
rejects JPEG-named symbolic links or other non-regular files.  A directory is
non-recursive and sorted by filename; it ignores ordinary non-JPEG files but
also rejects any JPEG-named symbolic link or non-regular entry.  The directory
itself must be a real directory, not a symbolic link.  At `start()`, directory
mode opens and retains that directory inode, then enumerates and opens JPEG
candidates relative to its directory FD; renaming or replacing the configured
path cannot redirect an active pass.  Candidate opens are non-blocking and
validated with `fstat`, so a file replaced by a FIFO or other non-regular type
fails with a source error rather than blocking the pipeline.

At completion (or after `stop()`/`close()`), `next_frame()` returns
`END_OF_STREAM`.  `start()` may begin a new pass only after stop or exhaustion;
it is rejected while already running and after `close()`.  Each new source
starts at ingest ID 0, while re-started passes on the same source continue the
same monotonically increasing IDs.

```python
from threading import Event

from linux.task3_pipeline import FrameEventKind, MockFileFrameSource

source = MockFileFrameSource(directory="tests/fixtures/jpeg")
source.start()
while (event := source.next_frame(Event())).kind is FrameEventKind.FRAME:
    frame = event.frame
    assert frame is not None
    print(frame.metadata.ingest_id, frame.metadata.payload_length)
source.close()
```
