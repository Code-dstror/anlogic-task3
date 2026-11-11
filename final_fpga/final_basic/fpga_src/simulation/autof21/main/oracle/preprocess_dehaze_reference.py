"""Independent scalar F21 oracle; no DUT roundtrip, RAM or packed-multiply model."""
from dataclasses import dataclass


def reciprocal(index):
    if not 0 <= index <= 256:
        raise ValueError('reciprocal index')
    return 0 if index < 64 else (65536 + index // 2) // index


def valid_reciprocal(index, value):
    if not 0 <= index <= 256:
        return False
    if index < 64:
        return value == 0
    return 256 <= value <= 1024 and 131072-index < 2*value*index <= 131072+index


@dataclass(frozen=True)
class Config:
    enable: bool = True
    omega: int = 224
    t_min: int = 128
    a_step: int = 8
    t_step: int = 16
    max_delta: int = 64
    night_floor: int = 48
    sky_floor: int = 208
    sky_span: int = 24


@dataclass(frozen=True)
class Identity:
    camera: int
    key: int
    frame: int
    epoch: int = 1
    exposure: int = 1000
    gain: int = 256


@dataclass(frozen=True)
class Map:
    identity: Identity
    config: Config
    width: int
    height: int
    atmosphere: int
    transmission: tuple[int, ...]
    coefficients: tuple[int, ...]
    dark: tuple[int, ...]
    night: bool


def luma(rgb):
    r, g, b = rgb
    return (77*r+150*g+29*b+128)//256


def clamp(value, lo, hi):
    return min(hi, max(lo, value))


def compatible(history, identity, config, width, height):
    if history is None:
        return False
    old = history.identity
    return (old.camera, old.key, old.epoch, old.exposure, old.gain,
            history.config, history.width, history.height) == (
            identity.camera, identity.key, identity.epoch, identity.exposure,
            identity.gain, config, width, height)


def estimate(image, width, height, identity, config=Config(), previous=None):
    if width % 6 or height % 6 or not 6 <= width <= 1920 or not 6 <= height <= 1080:
        raise ValueError('frozen observer geometry')
    if len(image) != width*height or not 128 <= config.t_min <= 256:
        raise ValueError('image/config')
    ow, oh = width//6, height//6
    dark = [255]*144
    seen = [False]*144
    maximum = 0
    sum_y = 0
    for v in range(oh):
        for u in range(ow):
            rgb = image[(3+6*v)*width+3+6*u]
            value = min(rgb)
            tile = (v//20)*16+u//20
            dark[tile] = min(dark[tile], value)
            seen[tile] = True
            maximum = max(maximum, value)
            sum_y += luma(rgb)
    same = (compatible(previous, identity, config, width, height) and
            1 <= identity.frame-previous.identity.frame <= 4)
    a = clamp(maximum, 64, 255)
    if same:
        a = clamp(a, previous.atmosphere-config.a_step, previous.atmosphere+config.a_step)
    night = sum_y < (ow*oh)*48
    ts, rs = [256]*144, [256]*144
    for tile in range(144):
        if not seen[tile]:
            continue
        drop = (config.omega*dark[tile]*reciprocal(a)+32768)//65536
        target = 256 if night else max(config.t_min, 256-drop)
        if same:
            target = clamp(target, previous.transmission[tile]-config.t_step,
                           previous.transmission[tile]+config.t_step)
        ts[tile] = clamp(target, config.t_min, 256)
        rs[tile] = reciprocal(ts[tile])
    return Map(identity, config, width, height, a, tuple(ts), tuple(rs), tuple(dark), night)


def apply(image, width, height, identity, config=Config(), history=None, lut_valid=True):
    use = (config.enable and lut_valid and compatible(history, identity, config, width, height)
           and 1 <= identity.frame-history.identity.frame <= 4)
    output, clipped, protected = [], 0, 0
    for y in range(height):
        for x in range(width):
            rgb = image[y*width+x]
            if not use:
                output.append(rgb)
                continue
            yy = luma(rgb)
            safe = yy < config.night_floor or (yy >= config.sky_floor and max(rgb)-min(rgb) <= config.sky_span)
            if safe:
                output.append(rgb)
                protected += 1
                continue
            r = history.coefficients[(y//120)*16+x//120]
            a = history.atmosphere
            restored = [((channel-a)*r+128)//256+a for channel in rgb]
            limited = [clamp(channel+clamp(new-channel, -config.max_delta, config.max_delta), 0, 255)
                       for channel, new in zip(rgb, restored)]
            clipped += limited != restored
            output.append(tuple(limited))
    return tuple(output), dict(used=bool(use), atmosphere=history.atmosphere if use else 0,
                              age=identity.frame-history.identity.frame if use else 0,
                              clipped=clipped, protected=protected)


def self_check():
    for n in range(257):
        assert valid_reciprocal(n, reciprocal(n))
        if n >= 64:
            assert not valid_reciprocal(n, reciprocal(n)+1)
            assert not valid_reciprocal(n, reciprocal(n)-1)
    assert reciprocal(64) == 1024 and reciprocal(128) == 512 and reciprocal(256) == 256
    image = tuple((80, 100, 120) if x < 120 else (200, 210, 220)
                  for _ in range(12) for x in range(240))
    ident = Identity(0, 0x1234, 1)
    first = estimate(image, 240, 12, ident)
    assert first.dark[0] == 80 and first.dark[1] == 200 and first.atmosphere == 200
    out, stats = apply(image, 240, 12, Identity(0, ident.key, 2), history=first)
    assert stats['used'] and out != image
    assert all(abs(a-b) <= 64 for old, new in zip(image, out) for a, b in zip(old, new))
    night = tuple((5, 10, 15) for _ in image)
    assert estimate(night, 240, 12, Identity(0, ident.key, 2)).night
    assert apply(night, 240, 12, Identity(0, ident.key, 2), history=first)[0] == night
    sky = tuple((225, 230, 235) for _ in image)
    assert apply(sky, 240, 12, Identity(0, ident.key, 2), history=first)[0] == sky
    assert not apply(image, 240, 12, Identity(1, ident.key, 2), history=first)[1]['used']
    assert not apply(image, 240, 12, Identity(0, ident.key, 2, exposure=1001), history=first)[1]['used']
    assert not apply(image, 240, 12, Identity(0, ident.key, 6), history=first)[1]['used']


if __name__ == '__main__':
    self_check()
    print('F21 scalar golden self-check PASS')
