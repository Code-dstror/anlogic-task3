"""Integer oracle from the public HDR, Tone and ISP contracts."""

import random
from functools import cache


def rounded(numerator, denominator):
    return (2 * numerator + denominator) // (2 * denominator)


def pack(fields):
    value = 0
    for width, field in fields:
        assert 0 <= field < 1 << width, (width, field)
        value = (value << width) | field
    return value


def lanes(values, width):
    return pack((width, value) for value in reversed(values))


def rgb_lanes(pixels, width):
    return lanes([pack((width, channel) for channel in pixel) for pixel in pixels], 3 * width)


def fuse(long, short, base, shift, preset):
    l = [max(0, code - 50) for code in long]
    s = [max(0, code - 50) for code in short]
    difference = [abs(x - 16 * y) for x, y in zip(l, s)]
    weight = [min(16, max(0, (code - 768) // 8)) for code in long]
    hits = [d if raw < 896 and y > 4 and d > base + (x >> shift) else 0
            for raw, x, y, d in zip(long, l, s, difference)]
    if preset == 1 or any(weight):
        motion = any(hits)
    else:
        motion = max(hits) >= 128 or (sum(d >= 64 for d in hits) >= 2 and min(s) >= 8)
    if motion:
        return [16 * y for y in s], 15
    return [rounded((16 - w) * x + w * (16 * y), 16) for x, y, w in zip(l, s, weight)], 0


def merge_vectors():
    cases = [
        ((0, 49, 50, 51), (0, 50, 51, 52), 0, 0),
        ((1023, 1022, 896, 775), (1023, 1022, 1021, 1020), 16383, 0),
        ((350, 50, 50, 50), (54, 54, 80, 54), 0, 15),
        ((700, 600, 550, 500), (54, 50, 49, 0), 0, 15),
        ((178, 178, 178, 178), (58, 58, 58, 58), 0, 15),
    ]
    for residual in (63, 64, 112, 127, 128, 129):
        for neighbor in (57, 58):
            cases.extend([
                ((690 - residual, 690 - residual, 178, 178), (90, 90, 58, neighbor), 0, 15),
                ((690 - residual, 178, 178, 178), (90, 58, 58, 58), 0, 15),
            ])
        cases.extend(((690 - residual, 178, 178, 178), (90, 58, 58, 58), limit, 15)
                     for limit in (residual - 1, residual, residual + 1))
    for knee in range(768, 897, 8):
        for code in (knee - 1, knee, knee + 1):
            cases.append(((code, 775, 896, 1023), (91, 95, 173, 977), 16383, 0))
    for long_code in (775, 776, 895, 896):
        for short_code in (54, 55, 57, 58, 1023):
            cases.append(((long_code, 178, 178, 178), (short_code, 58, 58, 58), 0, 15))

    rng = random.Random(0xF05E)
    for index in range(1024):
        long = tuple(rng.randrange(1024) for _ in range(4))
        short = tuple(rng.randrange(1024 if index % 2 else 100) for _ in range(4))
        base = rng.randrange(16384 if index % 3 else 161)
        cases.append((long, short, base, index % 16))

    for index, (long, short, base, shift) in enumerate(cases):
        for preset in (0, 1):
            row_index = index * 2 + preset
            value, motion = fuse(long, short, base, shift, preset)
            yield pack(((40, lanes(long, 10)), (40, lanes(short, 10)), (14, base), (4, shift),
                        (2, preset), (1, row_index % 64 == 0), (1, row_index % 8 == 7),
                        (56, lanes(value, 14)), (4, motion)))


ANCHOR_X = (0, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384)
ANCHOR_Y = (
    (),
    (0, 152, 265, 420, 604, 742, 849, 904, 946, 987, 1023),
    (0, 176, 315, 487, 660, 789, 895, 937, 973, 999, 1023),
    (0, 120, 232, 365, 505, 625, 733, 826, 902, 968, 1023),
)


@cache
def endpoint(page, x):
    if page == 0:
        white, knee = 16368, 1024
        base = 1023 * (white + knee)
        denominator = white * (x + knee)
        return rounded(65536 * base, denominator), min(1023, rounded(x * base, denominator))

    anchors = ANCHOR_Y[page]
    if x == 0:
        return rounded(16384 * anchors[1], ANCHOR_X[1]), 0
    upper = next(index for index in range(1, len(ANCHOR_X)) if x <= ANCHOR_X[index])
    low, high = ANCHOR_X[upper - 1:upper + 1]
    step = high - low
    value = (high - x) * anchors[upper - 1] + (x - low) * anchors[upper]
    return rounded(16384 * value, step * x), rounded(value, step)


def tone(pixel, hdr, page, weight):
    if not hdr:
        return tuple(min(1023, channel) for channel in pixel)
    maximum = max(pixel)
    width = 32 << max(0, maximum.bit_length() - 10)
    a = maximum // width * width
    r = maximum - a
    gain_a, tone_a = endpoint(page, a)
    gain_b, tone_b = endpoint(page, a + width)
    gain = gain_a - rounded((gain_a - gain_b) * r, width)
    mapped = tone_a + rounded((tone_b - tone_a) * r, width)
    floor = rounded(mapped * weight, 32) if page else 0
    quantization = 16384 if page else 65536
    return tuple(mapped if channel == maximum else
                 max(floor, min(mapped, rounded(channel * gain, quantization))) for channel in pixel)


def tone_record(pixels, hdr, page, weights, sof, eol, clipped):
    result = [tone(pixel, hdr, page, w) for pixel, w in zip(pixels, weights)]
    return pack(((168, rgb_lanes(pixels, 14)), (1, hdr), (2, page), (24, lanes(weights, 6)),
                 (1, sof), (1, eol), (1, clipped), (120, rgb_lanes(result, 10))))


def tone_vectors():
    for page in range(4):
        for start in range(0, 16384, 4):
            pixels = [(code, code, code) for code in range(start, start + 4)]
            yield tone_record(pixels, True, page, (0, 1, 31, 32), start == 0,
                              start % 64 == 60, start % 12 == 0)

    rng = random.Random(0x946E)
    edges = (0, 1, 31, 32, 33, 63, 64, 127, 128, 255, 256, 511, 512, 1022, 1023,
             1024, 1025, 2047, 2048, 4095, 4096, 8191, 8192, 15568, 16367, 16368, 16382, 16383)
    for index in range(768):
        if index < 4 * len(edges):
            peak = edges[index // 4]
            pixels = [(peak, 0, peak), (0, peak, peak), (peak, peak, 0), (1 if peak else 0, peak, peak // 3)]
        else:
            pixels = [tuple(rng.randrange(16384) for _ in range(3)) for _ in range(4)]
        hdr = index < 4 * len(edges) or index % 5 not in (2, 3)
        weights = (0, (index % 32) + 1, 31, 32)
        yield tone_record(pixels, hdr, index % 4, weights, index % 24 == 0,
                          index % 8 == 7, index % 7 == 0)


def color(pixel, hdr, page, gains, gamma):
    divisor = 1024 if hdr and page else 256
    limit = 16383 if hdr else 1023
    scaled = [rounded(raw * gain, divisor) for raw, gain in zip(pixel, gains)]
    clipped = max(scaled) > limit
    normalized = tuple(min(limit, v) for v in scaled)
    weight = min(32, max(0, (min(pixel) - 12032) // 64))
    return tuple(gamma[v] for v in tone(normalized, hdr, page, weight)), clipped


def color_record(pixels, bus, geom, hdr, page, gains, shift, sof, eol, frame_end, gamma):
    values = [color(pixel, hdr, page, gains, gamma) for pixel in pixels]
    return pack(((168, bus), (13, geom[0]), (13, geom[1]), (2, 3), (1, hdr), (2, page),
                 (30, lanes(gains, 10)), (4, shift), (1, sof), (1, eol),
                 (96, rgb_lanes([pixel for pixel, _ in values], 8)),
                 (1, any(clipped for _, clipped in values)), (1, frame_end)))


FACTORY = (909, 410, 832)
UNITY = (256, 256, 256)


def direct_color_vectors(gamma):
    rng = random.Random(0xC0102)
    edges = (12031, 12032, 12095, 12096, 12159, 12160, 13952, 14016, 14079, 14080, 15568)
    frames = ((False, 3, (1023, 1, 256)), (True, 0, FACTORY), (True, 1, FACTORY),
              (True, 2, (1023, 1023, 1023)), (True, 3, (1023, 0, 511)),
              (False, 0, UNITY), (True, 3, (0, 1, 1023)))
    for frame, (hdr, page, gains) in enumerate(frames):
        for index in range(48):
            if index < len(edges):
                low = edges[index]
                pixels = [(low, 15568, 15568), (15568, low, 15360), (15568, 15568, low), (low, low, low)]
            elif index == len(edges):
                pixels = [(0, 0, 0), (1, 1, 1), (16383, 16383, 16383), (15568, 15568, 2000)]
            elif index == len(edges) + 1:
                pixels = [(1, 128, 512), (255, 256, 257), (1022, 1023, 1024), (16382, 16383, 16367)]
            else:
                pixels = [tuple(rng.randrange(16384 if hdr else 1024) for _ in range(3)) for _ in range(4)]
            yield color_record(pixels, rgb_lanes(pixels, 14), (32, 6), hdr, page, gains,
                               (frame + index) % 16, index == 0, index % 8 == 7, index == 47, gamma)


BAYER = (("G", "B"), ("R", "G"))


def demosaic(raw, x, y, width, height):
    def reflect(coord, length):
        if coord < 0:
            return -coord
        if coord >= length:
            return 2 * (length - 1) - coord
        return coord

    center = BAYER[y % 2][x % 2]
    neighbors = {"R": [], "G": [], "B": []}
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ny, nx = reflect(y + dy, height), reflect(x + dx, width)
            channel = BAYER[ny % 2][nx % 2]
            if channel != center:
                neighbors[channel].append(raw[ny * width + nx])
    return tuple(raw[y * width + x] if channel == center else
                 rounded(sum(neighbors[channel]), len(neighbors[channel])) for channel in ("R", "G", "B"))


def isp_vectors(gamma):
    rng = random.Random(0x15B10C)
    frames = ((8, 3, False, 3, FACTORY), (20, 3, True, 0, FACTORY),
              (32, 4, True, 1, UNITY), (16, 5, True, 2, (1023, 1023, 1023)),
              (12, 4, True, 3, (0, 1023, 701)), (3840, 4, False, 1, (512, 127, 1023)))
    for frame, (width, height, hdr, page, gains) in enumerate(frames):
        limit = 15568 if hdr else 1023
        edges = (0, 49, 50, 51, 255, 1023, limit - 1, limit)
        raw = []
        for y in range(height):
            for x in range(width):
                if x < 4 or x >= width - 4:
                    raw.append(edges[(x * 3 + y * 5 + frame) % len(edges)])
                elif hdr and x < 12:
                    raw.append(12031 + (x - 4) * 64 + y % 3)
                else:
                    raw.append(rng.randrange(limit + 1))
        corrected = raw if hdr else [max(0, value - 50) for value in raw]
        for y in range(height):
            for x in range(0, width, 4):
                index = y * width + x
                pixels = [demosaic(corrected, x + lane, y, width, height) for lane in range(4)]
                yield color_record(pixels, lanes(raw[index:index + 4], 14), (width, height), hdr, page,
                                   gains, (x + y) % 16, index == 0, x + 4 == width,
                                   index + 4 == len(raw), gamma)


def write_vectors(run, gamma):
    counts = {}
    streams = {"MERGE": merge_vectors(), "TONE": tone_vectors(),
               "COLOR": direct_color_vectors(gamma), "ISP": isp_vectors(gamma)}
    for name, records in streams.items():
        with (run / f"{name.lower()}.mem").open("w", encoding="ascii", newline="\n") as stream:
            count = 0
            for count, value in enumerate(records, 1):
                stream.write(f"{value:x}\n")
        counts[name] = count
    (run / "vectors_sizes.vh").write_text(
        "".join(f"`define {name}_COUNT {count}\n" for name, count in counts.items()), encoding="ascii"
    )
    return counts
