# Task 3 Python pipeline foundation

This package is the standard-library-only foundation shared by the Ubuntu host
and the future RK3576 target.  It contains shared data types, contracts,
exceptions, metrics, and the Stage-B `MockFileFrameSource`.  It does not parse
PCIe records, access SGDMA devices, validate or decode JPEG, or invoke RKNN.

Run from the repository root with Python 3.10 or newer:

```bash
python3 -m compileall linux/task3_pipeline tests
python3 -m unittest discover
```

The package is imported as `linux.task3_pipeline` when commands are run from
the repository root.  Target deployment packaging is deliberately deferred
until the board runtime and deployment contract are available.

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
