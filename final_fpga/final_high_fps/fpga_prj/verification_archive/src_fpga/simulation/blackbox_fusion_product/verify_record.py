"""Decode the transferred AJPG independently of HDL and of the RK parser."""

from hashlib import sha256
from io import BytesIO
from pathlib import Path
import re


WIDTH, HEIGHT = 480, 32
HEADER_BYTES = 2112
GAINS = (333, 178, 226)
MAX_RGB_ERROR = 4
NORMAL_PRODUCTS = {"first": (11, (172, 440, 858)), "recovery": (13, (613, 328, 234))}
SCENES = {
    "normal": NORMAL_PRODUCTS,
    "stopped": {"first": NORMAL_PRODUCTS["first"]},
    "deadline": NORMAL_PRODUCTS,
    "timeout": {"cold_recovery": (21, (613, 328, 234))},
    "stress": NORMAL_PRODUCTS,
}


def need(condition, reason):
    if not condition:
        raise ValueError(reason)


def read_gamma(table_path):
    contents = table_path.read_text(encoding="ascii")
    lookup = {}
    for address, value in re.findall(r"^\s*([0-9a-f]+)\s*:\s*([0-9a-f]+)\s*;", contents, re.I | re.M):
        index = int(address, 16)
        need(index not in lookup, f"duplicate public Gamma index {index}")
        lookup[index] = int(value, 16)
    need(set(lookup) == set(range(1024)) and max(lookup.values()) < 256, "invalid public Gamma table")
    return lookup


def expected_rgb(raw_rgb, gamma):
    linear = [
        min(1023, (max(0, value - 50) * gain + 128) // 256)
        for value, gain in zip(raw_rgb, GAINS)
    ]
    return tuple(gamma[code] for code in linear)


def expected_raw_bytes(raw_rgb):
    red, green, blue = raw_rgb
    rows = [(green, blue, green, blue), (red, green, red, green)]
    packed_rows = [
        sum(value << (10 * lane) for lane, value in enumerate(row)).to_bytes(5, "little")
        * (WIDTH // 4)
        for row in rows
    ]
    return b"".join(packed_rows[row % 2] for row in range(HEIGHT))


def inspect_jpeg(jpeg):
    need(jpeg[:2] == b"\xff\xd8" and jpeg[-2:] == b"\xff\xd9", "JPEG SOI or final EOI missing")
    position = 2
    sof = None
    while position < len(jpeg):
        need(jpeg[position] == 0xFF, f"missing marker at JPEG offset {position}")
        while position < len(jpeg) and jpeg[position] == 0xFF:
            position += 1
        need(position + 3 <= len(jpeg), "incomplete JPEG marker")
        marker = jpeg[position]
        length = int.from_bytes(jpeg[position + 1 : position + 3], "big")
        end = position + 1 + length
        need(length >= 2 and end <= len(jpeg) - 2, f"invalid length for JPEG marker {marker:02x}")
        body = jpeg[position + 3 : end]
        if marker == 0xC0:
            need(sof is None and len(body) == 15 and body[0] == 8 and body[5] == 3,
                 "expected one baseline 8-bit three-component SOF0")
            height = int.from_bytes(body[1:3], "big")
            width = int.from_bytes(body[3:5], "big")
            need((width, height) == (WIDTH, HEIGHT), f"bad JPEG SOF geometry {width}x{height}")
            sampling = tuple(body[7::3])
            need(sampling == (0x21, 0x11, 0x11), f"bad JPEG sampling factors {sampling}")
            sof = {"width": width, "height": height, "sampling_factors": sampling,
                   "mcu_grid": ((width + 15) // 16, (height + 7) // 8),
                   "mcu_count": ((width + 15) // 16) * ((height + 7) // 8)}
        if marker == 0xDA:
            need(sof is not None, "JPEG scan before SOF0")
            need(len(body) == 10 and body[0] == 3 and body[-3:] == bytes((0, 63, 0)),
                 "expected an interleaved baseline scan")
            entropy = jpeg[end:-2]
            need(entropy and re.search(rb"\xff(?!\x00)", entropy) is None,
                 "unexpected marker or early EOI in entropy data with restarts disabled")
            return sof
        position = end
    raise ValueError("JPEG SOS missing")


def validate_record(record_path, sequence, session, epoch, raw_rgb, gamma):
    from PIL import Image

    record = record_path.read_bytes()

    def field(offset, size):
        return int.from_bytes(record[offset : offset + size], "little")

    need(len(record) >= HEADER_BYTES + 4, "short AJPG")
    need((field(0, 4), field(4, 2), field(6, 2)) == (0x47504A41, 4, HEADER_BYTES),
         "AJPG v4 signature or header size")
    need(field(8, 4) == sequence and field(12, 4) + HEADER_BYTES == len(record),
         "AJPG capture sequence or payload length")
    need((field(16, 2), field(18, 2), field(22, 1)) == (WIDTH, HEIGHT, 73),
         "AJPG geometry or configured Q73")
    need(field(36, 4) == 0 and field(44, 4) == 0, "AJPG error or unfrozen CRC field")
    need((field(64, 4), field(68, 2)) == (0x32585443, 1), "CTX2 signature or schema")
    validity = field(70, 2)
    need(validity & 1 and validity & 0x700 == 0, "SOURCE or neutral qualification flags")
    need((field(72, 4), field(76, 4), field(80, 4), field(84, 1), field(180, 1))
         == (session, epoch, sequence, 0, 0x80), "CTX2 source identity or schema2 processing mask")
    need(field(192, 4) == 878071891 and field(196, 1) == 1, "RCD4 sparse magic or schema")
    need(field(198, 6) == 0, "disabled RCD4 algorithms published a record or error")

    jpeg = record[HEADER_BYTES:]
    metrics = inspect_jpeg(jpeg)
    expected = expected_rgb(raw_rgb, gamma)
    maxima = [0, 0, 0]
    totals = [0, 0, 0]
    squared = [0, 0, 0]
    with Image.open(BytesIO(jpeg)) as image:
        need(image.format == "JPEG" and image.size == (WIDTH, HEIGHT), "decoder format or geometry")
        image.load()
        rgb_bytes = image.convert("RGB").tobytes()
        for offset in range(0, len(rgb_bytes), 3):
            pixel = rgb_bytes[offset : offset + 3]
            for channel, (actual, target) in enumerate(zip(pixel, expected)):
                error = abs(actual - target)
                maxima[channel] = max(maxima[channel], error)
                totals[channel] += error
                squared[channel] += error * error
    count = WIDTH * HEIGHT
    metrics.update(
        frame_sequence=sequence,
        source_camera=0,
        source_session=session,
        source_epoch=epoch,
        processing_mode=0x80,
        jpeg_session=field(88, 4),
        jpeg_generation=field(92, 4),
        jpeg_slot=field(40, 2),
        quality=73,
        raw_rgb10=raw_rgb,
        manual_wb_q8=GAINS,
        expected_rgb8=expected,
        max_abs_error_rgb8=maxima,
        mean_abs_error_rgb8=[value / count for value in totals],
        rmse_rgb8=[(value / count) ** 0.5 for value in squared],
        pixel_count=count,
        tolerance_rgb8=MAX_RGB_ERROR,
        raw_input_sha256=sha256(expected_raw_bytes(raw_rgb)).hexdigest(),
        record_bytes=len(record),
        jpeg_bytes=len(jpeg),
        record_sha256=sha256(record).hexdigest(),
        jpeg_sha256=sha256(jpeg).hexdigest(),
    )
    record_path.with_suffix(".jpg").write_bytes(jpeg)
    return metrics
