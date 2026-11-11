"""Independent sorting oracle for complete S1 observations and video history.

Uses sorted samples rather than the RTL's histogram/serial divider, and derives
gain from equations rather than importing the handoff table or RTL constants.
"""
from dataclasses import dataclass
from pathlib import Path
import json

N = 57600


def sample(kind, index):
    band, k = divmod(index, 14400)
    if kind == 0:
        value = 100
    elif kind == 1:
        value = 8 if index % 2 == 0 else 200
    elif kind == 2:
        value = (8 if k < (1439 if band == 0 else 1440) else 200) if band < 2 else (255 if band == 2 else 0)
    elif kind == 3:
        value = 47 if index == 0 else 48
    elif kind == 4:
        value = 48
    elif kind == 5:
        value = 255
    elif kind == 6:
        value = 0
    else:
        raise ValueError(kind)
    return value, value, value, value


def coefficients(samples):
    assert len(samples) == N
    night = sum(p[3] for p in samples) < 2764800
    result = []
    for band in range(4):
        pixels = samples[band * 14400:(band + 1) * 14400]
        d = 4 * (sorted(min(p[:3]) for p in pixels)[1439] // 4) + 2
        mu = (sum(p[3] for p in pixels) + 7200) // 14400
        ratio = min(256, (d * 256 + 127) // 255)
        t = max(112, 256 - ((224 * ratio + 128) >> 8))
        gain = 256 if night else min(512, (65536 + t // 2) // t)
        result.append((gain, (767 + mu) >> 2))
    return result


@dataclass
class History:
    """Video oracle: compatible newer samples, age <=4, first publication raw."""
    slew: bool = True
    cohort: int = 1
    frame: int = -1
    values: object = None
    sequence: int = -1
    replay: bool = False

    def reset(self, cohort=None):
        self.values = None
        if cohort is not None:
            self.cohort = cohort

    def begin(self, frame, cohort=1):
        if cohort != self.cohort:
            self.reset(cohort)
            self.sequence = -1
        self.replay = frame <= self.sequence
        valid = self.values is not None and not self.replay and 0 < frame - self.frame <= 4
        if not valid:
            self.values = None
        self.sequence = max(self.sequence, frame)
        return self.values if valid else None

    def publish(self, frame, raw, source=True, terminal=True):
        if not source or not terminal or self.replay or not 0 <= self.sequence - frame <= 4:
            return None
        if self.slew and self.values is not None and 0 < frame - self.frame <= 4:
            raw = [(max(g - 16, min(g + 16, ng)), max(c - 4, min(c + 4, nc)))
                   for (g, c), (ng, nc) in zip(self.values, raw)]
        self.values, self.frame = raw, frame
        return raw


def generate(out):
    out.mkdir(parents=True, exist_ok=True)
    raws, histograms = [], []
    with (out / 'samples.hex').open('w') as f:
        for kind in range(7):
            pixels = [sample(kind, i) for i in range(N)]
            raws.append(coefficients(pixels))
            for band in range(4):
                bins = [min(p[:3]) // 4 for p in pixels[band*14400:(band+1)*14400]]
                histograms.extend(bins.count(b) for b in range(64))
            for r, g, b, y in pixels:
                f.write(f'{r:02x}{g:02x}{b:02x}{y:02x}\n')
    spatial, temporal = History(False), History(True)
    seq = [0, 1, 2, 3, 4, 5, 6]
    words = []
    for frame, kind in enumerate(seq, 1):
        spatial.begin(frame); temporal.begin(frame)
        a = spatial.publish(frame, raws[kind]); b = temporal.publish(frame, raws[kind])
        for values in (a, b):
            gain = sum(g << (10 * i) for i, (g, _) in enumerate(values))
            center = sum(c << (8 * i) for i, (_, c) in enumerate(values))
            words.append((gain << 32) | center)
    (out / 'expected.hex').write_text(''.join(f'{v:018x}\n' for v in words))
    (out / 'histograms.hex').write_text(''.join(f'{v:04x}\n' for v in histograms))
    gains = []
    for b in range(64):
        d = 4 * b + 2
        ratio = min(256, (d * 256 + 127) // 255)
        t = max(112, 256 - ((224 * ratio + 128) >> 8))
        gains.append(min(512, (65536 + t // 2) // t))
    (out / 'gains.hex').write_text(''.join(f'{v:03x}\n' for v in gains))
    result = {'raw': raws, 'sequence': seq, 'spatial_and_temporal_expected': [f'{v:018x}' for v in words]}
    (out / 'oracle.json').write_text(json.dumps(result, indent=2) + '\n')
    return result
