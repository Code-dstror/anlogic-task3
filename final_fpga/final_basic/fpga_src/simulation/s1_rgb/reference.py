"""Independent scalar S1-spatial-v1 gold; no production RTL/model imports."""
from pathlib import Path
import argparse
import json
import random


def row_coefficients(y, gains, centers):
    if y < 135:
        return gains[0], centers[0]
    if y >= 945:
        return gains[3], centers[3]
    j, offset = divmod(y - 135, 270)
    w = (offset * 256 + 135) // 270
    return tuple(((256-w)*v[j] + w*v[j+1] + 128) // 256 for v in (gains, centers))


def restore_channel(value, gain, center):
    delta = ((value-center)*(gain-256)+128)//256
    down = min(80, value-((value+2)//4))
    up = min(80, 255-value)
    bounded = min(up, max(-down, delta))
    return min(255, max(0, value+bounded)), delta != bounded


def restore_group(rgb, gain, center, keep=15, enabled=True):
    result = luminance = clipped = 0
    for lane in range(4):
        channels = []
        lane_clipped = False
        for channel in range(3):
            value = (rgb >> (lane*24+channel*8)) & 255
            out, clip = restore_channel(value, gain, center)
            channels.append(out if enabled else value)
            lane_clipped |= clip
        if keep & (1 << lane):
            result |= sum(c << (lane*24+i*8) for i, c in enumerate(channels))
            b, g, r = channels
            luminance |= ((77*r+150*g+29*b+128)//256) << (lane*8)
            clipped |= int(lane_clipped and enabled) << lane
    return result, luminance, clipped


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0x513041)
    patterns = [([256,512,256,512], [255,0,254,1]),
                ([512,256,512,256], [0,255,1,254]),
                ([512,420,336,294], [238,229,223,217]),
                ([256]*4, [255]*4)]
    patterns += [(list(rng.choices(range(256,513), k=4)),
                  list(rng.choices(range(256), k=4))) for _ in range(4)]
    with (output/'rows.mem').open('w') as f:
        for gains, centers in patterns:
            for y in range(1080):
                gain, center = row_coefficients(y, gains, centers)
                f.write(f'{(gain | center << 10):05x}\n')
    with (output/'bands.mem').open('w') as f:
        for gains, centers in patterns:
            packed = sum(g << (10*i) for i,g in enumerate(gains))
            packed |= sum(c << (40+8*i) for i,c in enumerate(centers))
            f.write(f'{packed:018x}\n')
    with (output/'inputs.mem').open('w') as fi, (output/'outputs.mem').open('w') as fo:
        for n in range(4096):
            if n < 768:
                rgb = sum(((n+i*37)&255) << (8*i) for i in range(12))
                gain = [256,512,257][n//256]
                center = (n*17+129)&255
            else:
                rgb = rng.getrandbits(96)
                gain = rng.randint(256,512)
                center = rng.randrange(256)
            keep = [1,3,7,15][n%4] if n%31 == 0 else 15
            inp = rgb | gain << 96 | center << 106 | keep << 114
            out, y, clipped = restore_group(rgb, gain, center, keep)
            fi.write(f'{inp:030x}\n')
            fo.write(f'{(out | y << 96 | clipped << 128):033x}\n')
    # Exhaustive channel input range at endpoint gains, and signed half ties.
    for gain in (256,257,384,511,512):
        for center in range(256):
            for value in range(256):
                out, _ = restore_channel(value, gain, center)
                assert 0 <= out <= 255
                numerator=(value-center)*(gain-256)+(value<<8)+128
                assert -65152<=numerator<=130688
                raw=numerator//256
                assert raw==value+((value-center)*(gain-256)+128)//256
                assert -255<=raw<=510
                if gain == 256:
                    assert out == value
    assert restore_channel(254,512,255)[0] == 253
    assert restore_channel(255,512,255)[0] == 255
    assert restore_channel(1,384,2)[0] == 1  # negative half rounds toward +infinity
    assert restore_channel(1,511,2)[0] == 0
    # Prove the output-domain clamp over every possible valid pixel delta,
    # independently of which G/C generated it. This covers both thresholds.
    for value in range(256):
        for delta in range(-255,256):
            down=min(80,value-((value+2)//4))
            up=min(80,255-value)
            gold=value+max(-down,min(up,delta))
            lo=value-80 if value>=107 else (value+2)//4
            hi=255 if value>=175 else value+80
            actual=max(lo,min(hi,value+delta))
            assert actual==gold
            assert (actual!=value+delta)==(delta< -down or delta>up)
    (output/'reference.json').write_text(json.dumps({
        'contract':'S1-spatial-v1','row_patterns':len(patterns),'rows_each':1080,
        'restore_groups':4096,'scalar_channel_checks':5*256*256,
        'exhaustive_clamp_equivalence_checks':256*511,
        'MAC_Z_exact_identity_and_width_checks':5*256*256,
        'model':'independent integer // floor and direct 77/150/29 luminance'
    }, indent=2)+'\n')


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    generate(parser.parse_args().output)
