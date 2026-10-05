# Anlogic single-frame capture (initial version)

This standard-library-only package receives one AJPG v1 JPEG record from an
already configured Anlogic streaming C2H device. It does not load the driver,
configure PCIe, program the FPGA, or implement a continuous video service.
Python 3.10 or newer is required.

## Before running

Confirm the loaded FPGA image and exclusive ownership of both Linux and FPGA
controls. Discover the endpoint by VID:DID and verify its driver and character
node mappings through sysfs; do not assume a fixed BDF or PCI instance number.
Supply the verified user and C2H nodes explicitly. The tested endpoint was
1edb:abcd with FDI4; other bitstreams or drivers require interface review.

The tested driver adds the application base 0x80000 inside the user node, so
register accesses here use relative offsets. It also interprets O_TRUNC when
opening C2H as EOP short-completion mode. These are driver-specific semantics.

The command writes application control registers and starts DMA. Ensure these
operations are authorized and no other process holds the devices. The helper
requires that any previous DMA has stopped before it is called; it cannot
arbitrate ownership against another process or FPGA UART operator.

## Capture one record

From the repository root, substitute the verified device paths:

```bash
python3 -m linux.pcie_transport.capture_v1_record \
  --user-device /dev/ANLOGIC-PCI0_user \
  --c2h-device /dev/ANLOGIC-PCI0_c2h_0 \
  --capacity 16777280 \
  --timeout-seconds 10 \
  --output /tmp/fdi4-frame.record
```

The output path is overwritten if it already exists; choose a fresh path when
preserving evidence. Capacity is 64 header bytes plus the maximum 16 MiB JPEG
payload, not the required read return length. The receiver performs one read
and accepts only a record whose actual length equals 64 + payload_length.
It checks the header and JPEG boundary markers; full image decoding is a
separate host-side operation. The CLI writes the record only after validation.

For diagnostic raw preservation, capture_one accepts a record_sink callback.
It runs after APP_ENABLE is cleared, before record parsing, and can save even
an invalid record. Do not save or hash data in ReaderWorker.receive: that would
delay clearing APP_ENABLE. The parent still receives data through a process
pipe before clearing enable; this does not eliminate all prefetch windows.

## Single-frame session behavior

An already armed session gets one application SOFT_RESET at the beginning of
the next capture. The receiver waits for SESSION_REARM_READY with TX_BUSY clear,
starts C2H, observes C2H_RUNNING, then enables the application and waits for
SESSION_ARMED. After receiving bytes, it clears APP_ENABLE before optional raw
saving, parsing and file output. No additional reset is added at the end.

Stopping does not require an immediate STATUS of 0x83. FDI4 may retain part of
the next frame and report TX_BUSY until the next session reset. Preserve that
state for diagnostics; a failure to clear busy and become ready after the next
reset is a recovery failure. Frame sequence and timestamp may restart from
zero on application reset, while the observed user-domain counters continue.
FDI4 DROP/OVERFLOW registers are constants and cannot measure actual losses.

Do not use this open/read/close and reset-per-session helper as a continuous
video loop with throughput guarantees. A continuous implementation must keep
receiving buffers available and separate receive from storage/decode; its
request chaining and buffer reuse have not been validated.

## Evidence and limits

The initial code came from FPGA commit
581148cd41404a47925d2c2a3697723a181e1230, with the reviewed Linux stop-order and
ready/busy checks recorded in SOURCE_ORIGIN.json. The protocol module is a
frozen upstream snapshot. It preserves the existing pipeline wire layout;
this change does not replace the shared protocol generator or merge the FPGA
branch. Package relocation avoids the existing pipeline package's OpenCV and
NumPy imports. Relocation is locally tested; board evidence used an isolated
package with the same receiver, session and protocol module bytes.

See the [checkpoint](../../docs/coordination/evidence/pcie-resume-20261004/checkpoint.json)
and [board validation](../../docs/coordination/evidence/pcie-resume-20261004/single-stop-v2-validation/review-summary.json).
The corrected flow passed ten independent records and complete 1920x1080 JPEG
decodes, plus one no-data driver timeout followed by successful capture/decode.

Timeout applies separately to each readiness, DMA start, arm, read and cleanup
phase; it is not a total-command deadline. Python deadlines cannot guarantee
termination of a task blocked inside a kernel driver. The tested no-data read
returned errno 512 after about ten seconds; the driver maps that path to
-ERESTARTSYS rather than ETIMEDOUT. This version preserves the error instead of
reclassifying or automatically retrying it. Driver errno normalization,
host-forced cancellation before driver timeout, and further recovery changes
belong in follow-up commits. Continuous DMA, sustained throughput, color
accuracy, NPU and HDMI acceptance are outside this version.

Run the focused tests from the repository root:

```bash
python3 -m unittest tests.test_capture_v1_record tests.test_session_rearm \
  tests.test_single_frame_stop_order tests.test_pcie_transport_protocol
```
