# Task 3 Python pipeline foundation

This package is the Stage-A, standard-library-only foundation shared by the
Ubuntu host and the future RK3576 target.  It contains data types, abstract
adapter contracts, exceptions, and metrics only.  It does not parse PCIe
records, access SGDMA devices, decode JPEG, or invoke RKNN.

Run from the repository root with Python 3.10 or newer:

```bash
python3 -m compileall linux/task3_pipeline tests
python3 -m unittest discover
```

The package is imported as `linux.task3_pipeline` when commands are run from
the repository root.  Target deployment packaging is deliberately deferred
until the board runtime and deployment contract are available.
