"""Integer HDR WB/Tone generator and same-input numerical comparison."""

import argparse
from dataclasses import dataclass
from hashlib import sha256
from itertools import product
import json
from pathlib import Path
import re
from statistics import mean, pstdev


PROJECT = Path(__file__).resolve().parents[1]
ROM_DIR = PROJECT / "src_fpga/ip/coefficients"
GAMMA_PATH = PROJECT / "src_fpga/rtl/isp/color/gamma22_10to8.mif"
DEFAULT_GAINS = (909, 410, 832)
MAX_RGB14 = 16383
MAX_RGB10 = 1023
SHORT_WHITE = (1023 - 50) << 4
NEAR_SHORT_WHITE = 15360
THIRD_CHANNEL_HIGH = 12288
FLOOR_START = 12032
FLOOR_SHIFT = 6
PAGE_DEPTH = 128
ROM_DEPTH = 512
ANCHORS = (0, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384)
PROFILES = {
    "balanced": (0, 152, 265, 420, 604, 742, 849, 904, 946, 987, 1023),
    "bright": (0, 176, 315, 487, 660, 789, 895, 937, 973, 999, 1023),
    "highlights": (0, 120, 232, 365, 505, 625, 733, 826, 902, 968, 1023),
}
KNOTS = tuple(
    x
    for start, stop, step in (
        (0, 1024, 32), (1024, 2048, 64), (2048, 4096, 128),
        (4096, 8192, 256), (8192, 16385, 512),
    )
    for x in range(start, stop, step)
)
BASELINE_HASHES = {
    "legacy": (
        "547e3dfc95d9af8db4bb9af2aa2b21f648e3ee3d6204fe86e8c3c101bba51e24",
        "9a1f5d068f617f6953988cedaf0eea275e3a2491abb2c3d65ebaa4cdf3d88a8f",
    ),
    "B": (
        "6bb828c0ca321aaf523794ef0e0bfe35cf7c47c6bfea950f3d189a20b56db31f",
        "8cd0769949bdecfd03adc6994517ada979c9a7263a054c34365e45adf11f6166",
    ),
}
GAMMA_SHA256 = "e63e58bcafbfbd5f6e0a8b54a82a9ffce2e26e56e4617c722b3326e75d1d231b"


def round_half_up(numerator, denominator):
    return (2 * numerator + denominator) // (2 * denominator)


@dataclass(frozen=True)
class Segment:
    width: int
    gain: int
    gain_delta: int
    tone: int
    tone_delta: int

    def pack(self):
        assert 0 <= self.gain < 2**17 and 0 <= self.gain_delta < 2**14
        assert 0 <= self.tone < 2**10 and 0 <= self.tone_delta < 2**8
        return (
            self.gain | ((self.gain_delta & 0xfff) << 17) | (self.tone << 29)
            | ((self.tone_delta & 0x3f) << 39) | ((self.gain_delta >> 12) << 45)
            | ((self.tone_delta >> 6) << 47)
        )


@dataclass(frozen=True)
class Curve:
    gain_bits: int
    segments: tuple[Segment, ...]

    def samples(self):
        return tuple(
            (s.gain - round_half_up(s.gain_delta * r, s.width),
             s.tone + round_half_up(s.tone_delta * r, s.width))
            for s in self.segments for r in range(s.width)
        )

    def page(self):
        return [s.pack() for s in self.segments] + [0] * (PAGE_DEPTH - len(self.segments))


def make_curve(gains, tones, gain_bits):
    segments = tuple(
        Segment(b - a, gains[i], gains[i] - gains[i + 1], tones[i], tones[i + 1] - tones[i])
        for i, (a, b) in enumerate(zip(KNOTS, KNOTS[1:]))
    )
    assert len(segments) == 96 and sum(s.width for s in segments) == 16384
    return Curve(gain_bits, segments)


def original_curve(bright=False):
    white, knee = (16383, 512) if bright else (16368, 1024)
    gains = []
    for x in KNOTS:
        gain = round_half_up(65536 * 1023 * (white + knee), white * (x + knee))
        if bright:
            gain = max(min(114688, gain), gains[-1] - 4095 if gains else 0)
        gains.append(gain)
    if bright:
        tones = [min(MAX_RGB10, round_half_up(x * g, 65536)) for x, g in zip(KNOTS, gains)]
    else:
        tones = [min(MAX_RGB10, round_half_up(x * 1023 * (white + knee), white * (x + knee))) for x in KNOTS]
    return make_curve(gains, tones, 16)


def anchor_tone(x, values):
    j = next(i for i in range(1, len(ANCHORS)) if x <= ANCHORS[i])
    x0, x1 = ANCHORS[j - 1 : j + 1]
    y0, y1 = values[j - 1 : j + 1]
    return y0 * (x1 - x) + y1 * (x - x0), x1 - x0


def enhanced_curve(values):
    gains, tones = [], []
    for x in KNOTS:
        numerator, denominator = anchor_tone(x, values)
        tones.append(round_half_up(numerator, denominator))
        gains.append(round_half_up(numerator << 14, denominator * x) if x else
                     round_half_up(values[1] << 14, ANCHORS[1]))
    return make_curve(gains, tones, 14)


def curves():
    return {"legacy": original_curve(), "B": original_curve(bright=True),
            **{name: enhanced_curve(values) for name, values in PROFILES.items()}}


def mif_images(words):
    assert len(words) == ROM_DEPTH
    for part in range(2):
        lines = ["DEPTH = 512;", "WIDTH = 40;", "ADDRESS_RADIX = HEX;", "DATA_RADIX = HEX;",
                 "CONTENT", "BEGIN"]
        lines.extend(f"{index:03X} : {(word >> (40 * part)) & (2**40 - 1):010X};"
                     for index, word in enumerate(words))
        yield ("\r\n".join([*lines, "END;"]) + "\r\n").encode("ascii")


def rom_images(modes):
    for name, expected in BASELINE_HASHES.items():
        old_image = mif_images(modes[name].page() + [0] * (ROM_DEPTH - PAGE_DEPTH))
        assert tuple(sha256(image).hexdigest() for image in old_image) == expected, name
    words = [word for name in ("legacy", *PROFILES) for word in modes[name].page()]
    return tuple(mif_images(words))


def read_gamma():
    raw = GAMMA_PATH.read_bytes()
    assert sha256(raw).hexdigest() == GAMMA_SHA256, GAMMA_PATH
    values = {int(a, 16): int(v, 16) for a, v in re.findall(rb"(?m)^\s*(\w+)\s*:\s*(\w+)\s*;", raw)}
    assert set(values) == set(range(1024))
    return tuple(values[i] for i in range(1024))


def white_balance(pixel, gains, enhanced):
    denominator = 1024 if enhanced else 256
    full = tuple(round_half_up(c * g, denominator) for c, g in zip(pixel, gains))
    return tuple(min(MAX_RGB14, value) for value in full), sum(value > MAX_RGB14 for value in full)


def highlight_weight(raw):
    return min(32, max(0, (min(raw) - FLOOR_START) >> FLOOR_SHIFT))


def apply_tone(pixel, samples, gain_bits, weight=0):
    peak = max(pixel)
    gain, tone = samples[peak]
    floor = round_half_up(tone * weight, 32) if gain_bits == 14 else 0
    return tuple(tone if c == peak else min(tone, max(floor, round_half_up(c * gain, 1 << gain_bits)))
                 for c in pixel)


def luma(pixel):
    return round_half_up(sum(c * w for c, w in zip(pixel, (54, 183, 19))), 256)


def summary(values):
    ordered = sorted(values)
    p10, p90 = (ordered[(len(ordered) - 1) * i // 10] for i in (1, 9))
    return {"mean": round(mean(values), 3), "sigma": round(pstdev(values), 3),
            "range": [ordered[0], ordered[-1]], "p10_p90_span": p90 - p10,
            "distinct": len(set(values))}


def neutral(green):
    return tuple(round_half_up(green * DEFAULT_GAINS[1], gain) for gain in DEFAULT_GAINS)


def fixtures():
    result = {}
    for name, low, high, count in (
        ("shadow_texture", 52, 92, 64), ("midtone_texture", 300, 550, 64),
        ("upper_mid_texture", 550, 1450, 96), ("neutral_highlight", 5000, 15568, 256),
    ):
        result[name] = [neutral(low + round_half_up((high - low) * i, count - 1)) for i in range(count)]
    result["warm_highlight"] = [
        tuple(round_half_up(c * (25500 + 48 * i), 25500) for c in (9800, 10500, 5900))
        for i in range(256)
    ]
    result["dark_noise"] = [tuple(max(0, c + n) for c, n in zip(neutral(12), delta))
                            for delta in product(range(-4, 5), repeat=3)]
    return result


def roi_metrics(raw_pixels, samples, gain_bits, gamma):
    clipped = white = guarded = 0
    ratios = []
    outputs = []
    for raw in raw_pixels:
        wb, n = white_balance(raw, DEFAULT_GAINS, gain_bits == 14)
        clipped += n
        weight = highlight_weight(raw) if gain_bits == 14 else 0
        rgb10 = apply_tone(wb, samples, gain_bits, weight)
        guarded += weight > 0 and rgb10 != apply_tone(wb, samples, gain_bits)
        rgb8 = tuple(gamma[c] for c in rgb10)
        outputs.append(rgb8)
        white += rgb8 == (255, 255, 255)
        ideal = tuple(c * gain for c, gain in zip(raw, DEFAULT_GAINS))
        if max(ideal) and max(rgb10):
            ratios.extend(abs(out / max(rgb10) - want / max(ideal)) for out, want in zip(rgb10, ideal))
    return {"pixels": len(outputs), "clipped_wb_components": clipped, "wb_components": 3 * len(outputs),
            "highlight_floor_raised_pixels": guarded,
            "display_white_pixels": white, "peak_rgb8": summary([max(v) for v in outputs]),
            "luma8": summary([luma(v) for v in outputs]),
            "rgb8_max_minus_min": summary([max(v) - min(v) for v in outputs]),
            "mean_linear_channel_ratio_abs_error": round(mean(ratios), 6),
            "ratio_components": len(ratios)}


def ramp_metrics(samples, gain_bits, gamma):
    # Integer RGB14 rays before WB. The first ten have ordinary nonzero channel
    # ratios; the remaining six include near-zero and pure-primary components.
    rays = ((1000, 1000, 1000), (1000, 750, 250), (300, 1000, 700), (250, 600, 1000),
            (1000, 500, 100), (550, 1000, 200), (100, 400, 1000), (400, 950, 1000),
            (1000, 990, 500), (1000, 990, 980), (1000, 1, 3), (1, 1000, 1),
            (1, 2, 1000), (1000, 0, 0), (0, 1000, 0), (0, 0, 1000))
    result = {"rays": [list(r) for r in rays], "adjacent_components": 3 * len(rays) * MAX_RGB14,
              "peak_decreases": 0, "component_decreases_rgb10": 0, "component_decreases_rgb8": 0,
              "max_component_drop_rgb10": 0, "max_component_drop_rgb8": 0,
              "max_component_drop_rgb8_first_ten_rays": 0, "max_display_drop_example": None}
    for i, ray in enumerate(rays):
        previous = (0, 0, 0)
        for code in range(1, 16384):
            raw = tuple(round_half_up(code * r, 1000) for r in ray)
            wb, _ = white_balance(raw, DEFAULT_GAINS, gain_bits == 14)
            mapped = apply_tone(wb, samples, gain_bits, highlight_weight(raw) if gain_bits == 14 else 0)
            result["peak_decreases"] += max(previous) > max(mapped)
            for c, (before, after) in enumerate(zip(previous, mapped)):
                diff10, diff8 = before - after, gamma[before] - gamma[after]
                result["component_decreases_rgb10"] += diff10 > 0
                result["component_decreases_rgb8"] += diff8 > 0
                result["max_component_drop_rgb10"] = max(result["max_component_drop_rgb10"], diff10)
                if i < 10:
                    field = "max_component_drop_rgb8_first_ten_rays"
                    result[field] = max(result[field], diff8)
                if diff8 > result["max_component_drop_rgb8"]:
                    result["max_component_drop_rgb8"] = diff8
                    result["max_display_drop_example"] = {"ray_index": i, "raw_scale_before": code - 1,
                                                          "channel": c, "rgb10_before": before,
                                                          "rgb10_after": after}
            previous = mapped
    assert result["peak_decreases"] == 0
    return result


def curve_metrics(name, curve, samples):
    tones = [tone for _, tone in samples]
    assert all(b >= a for a, b in zip(tones, tones[1:]))
    gain_bits = curve.gain_bits
    max_error = None
    adjacent_color_bound = None
    if name in PROFILES:
        max_error = max(abs(tone - round_half_up(*anchor_tone(x, PROFILES[name])))
                        for x, tone in enumerate(tones))
        adjacent_color_bound = 0
        scale = 1 << gain_bits
        for peak, ((gain, tone), (next_gain, next_tone)) in enumerate(zip(samples, samples[1:])):
            # If the component stays below the old peak, half-up rounding can
            # lose at most ceil((peak - 1) * (gain - next_gain) / scale).
            nonpeak_bound = (max(0, peak - 1) * (gain - next_gain) + scale - 1) // scale
            # If the component was tied at the old peak and then stays fixed,
            # it leaves the exact-Tone path. Check that boundary directly.
            tie_bound = tone - min(next_tone, round_half_up(peak * next_gain, scale))
            adjacent_color_bound = max(adjacent_color_bound, nonpeak_bound, tie_bound)
    return {"gain_fraction_bits": gain_bits, "gain_base_max": max(s.gain for s in curve.segments),
            "gain_delta_max": max(s.gain_delta for s in curve.segments),
            "tone_delta_max": max(s.tone_delta for s in curve.segments),
            "gain_decreases": sum(a[0] > b[0] for a, b in zip(samples, samples[1:])),
            "peak_decreases": 0, "peak_inputs": len(samples), "peak_rgb10_distinct": len(set(tones)),
            "max_anchor_interpolation_error_rgb10": max_error,
            "adjacent_peak_increment_at_most_one_non_decreasing_channels_drop_bound_rgb10": adjacent_color_bound,
            "max_peak_preclamp_product_rounding_error_rgb10": max(
                abs(round_half_up(x * g, 1 << gain_bits) - t) for x, (g, t) in enumerate(samples)
            )}


def analyze(modes, images):
    gamma = read_gamma()
    inputs = fixtures()
    records = {}
    for name, curve in modes.items():
        samples = curve.samples()
        records[name] = {"curve": curve_metrics(name, curve, samples),
                         "ramp": ramp_metrics(samples, curve.gain_bits, gamma),
                         "roi": {key: roi_metrics(values, samples, curve.gain_bits, gamma)
                                 for key, values in inputs.items()}}
    return {"fixture": "synthetic common post-demosaic RGB14 input before WB",
            "source_sha256": sha256(Path(__file__).read_bytes()).hexdigest(),
            "gamma_sha256": GAMMA_SHA256,
            "rom_sha256": {f"tone96_{i}.mif": sha256(image).hexdigest() for i, image in enumerate(images)},
            "old_rom_sha256": BASELINE_HASHES, "wb_gains_rgb_q8": DEFAULT_GAINS,
            "max_enhanced_wb_all_legal_gains": round_half_up(MAX_RGB14 * 1023, 1024),
            "highlight_floor_weight": {"start": FLOOR_START, "shift": FLOOR_SHIFT, "cap": 32},
            "wb_first_clipped_raw_code": [(16384 * 256 - 128 + gain - 1) // gain for gain in DEFAULT_GAINS],
            "anchors_x": ANCHORS, "anchors_tone10": PROFILES, "modes": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-roms", action="store_true")
    parser.add_argument("--check-roms", action="store_true")
    parser.add_argument("--metrics", type=Path)
    args = parser.parse_args()
    if not (args.write_roms or args.check_roms or args.metrics):
        parser.error("Specify --write-roms, --check-roms or --metrics")
    modes = curves()
    images = rom_images(modes)
    for i, image in enumerate(images):
        path = ROM_DIR / f"tone96_{i}.mif"
        if args.write_roms:
            path.write_bytes(image)
        if args.check_roms:
            assert path.read_bytes() == image, path
        print(f"{path.name} {sha256(image).hexdigest()}")
    if args.metrics:
        args.metrics.parent.mkdir(parents=True, exist_ok=True)
        args.metrics.write_text(json.dumps(analyze(modes, images), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
