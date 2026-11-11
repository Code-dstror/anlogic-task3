"""Independent full-HD multi-frame fixed-F21 map, interpolation and RGB oracle.

The byte-frozen scalar authorities in oracle/ predate this candidate. This driver
creates synthetic original observations and foreground pixels, never DUT output.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'oracle'))
from preprocess_dehaze_reference import Config, Identity, estimate, luma, self_check
from numerics import clamp, group_gain

WIDTH, HEIGHT, GROUPS, FRAMES = 1920, 1080, 518400, 4


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class TiledImage:
    def __init__(self, grid): self.grid = grid
    def __len__(self): return WIDTH * HEIGHT
    def __getitem__(self, i): return self.grid[(i // WIDTH) // 120][(i % WIDTH) // 120]


def source_pixels(index):
    out = []
    for lane in range(4):
        p = 4 * index + lane
        row = p // WIDTH
        rgb = ((p * 17 + row * 3 + 29) % 256,
               (p * 29 + row * 5 + 73) % 256,
               (p * 43 + row * 7 + 101) % 256)
        if index % 19 == 0: rgb = ((index + lane) % 48,) * 3
        elif index % 19 == 1: rgb = (210 + lane,) * 3
        out.append(rgb)
    return out


def generate(output, *, smoke=False):
    output.mkdir(parents=True, exist_ok=False)
    self_check()
    provenance = json.loads((HERE/'oracle/PROVENANCE.json').read_text(encoding='utf-8-sig'))
    for row in provenance['files']:
        assert sha(HERE/'oracle'/Path(row['copy']).name) == row['original_sha256'], row['copy']
    tables = json.loads((HERE / 'oracle/tables_1920.json').read_text())
    maps = []
    for frame in range(1, FRAMES):
        grid = [[(lambda d: (d, min(255, d + 10), min(255, d + 20)))(
                    25 + (17*x + 29*y + 7*x*y + 23*(frame-1)) % (150+35*(frame-1)))
                 for x in range(16)] for y in range(9)]
        current = estimate(TiledImage(grid), WIDTH, HEIGHT,
                           Identity(0, 0x10203040, frame), Config(), maps[-1] if maps else None)
        maps.append(current)
        with (output / f'observation_{frame}.hex').open('w') as stream:
            for v in range(180):
                for u in range(320):
                    rgb = grid[v//20][u//20]
                    stream.write(f'{(rgb[0]<<24)|(rgb[1]<<16)|(rgb[2]<<8)|luma(rgb):08x}\n')
    (output / 'maps.hex').write_text(''.join(f'{(t<<11)|r:05x}\n'
        for m in maps for t, r in zip(m.transmission, m.coefficients)))
    rows = 2 if smoke else HEIGHT
    groups = rows * 480
    changed, protected, clipped = [0]*FRAMES, [0]*FRAMES, [0]*FRAMES
    with (output / 'source.hex').open('w') as source:
        for index in range(groups):
            rgb = source_pixels(index)
            word = sum(((r<<16)|(g<<8)|b) << (24*k) for k, (r,g,b) in enumerate(rgb))
            word |= sum(luma(p) << (96+8*k) for k, p in enumerate(rgb))
            source.write(f'{word:032x}\n')
    for frame in range(FRAMES):
        with (output / f'expected_{frame+1}.hex').open('w') as golden:
            for index in range(groups):
                rgb_group = source_pixels(index)
                left, right, wx = tables['dehaze_x_group4'][index%480].values()
                top, bottom, wy = tables['dehaze_y_pixel'][index//480].values()
                if frame:
                    history = maps[frame-1]
                    rs = history.coefficients
                    gain = group_gain(rs[top*16+left], rs[top*16+right],
                                      rs[bottom*16+left], rs[bottom*16+right], wx, wy)
                    a = history.atmosphere
                packed_rgb = packed_y = clipmask = protectmask = 0
                for lane, rgb in enumerate(rgb_group):
                    safe = luma(rgb)<48 or (luma(rgb)>=208 and max(rgb)-min(rgb)<=24)
                    raw = [((c-a)*gain+128)//256+a for c in rgb] if frame else list(rgb)
                    restored = rgb if not frame or safe else tuple(clamp(c+clamp(j-c,-64,64),0,255) for c,j in zip(rgb,raw))
                    clipmask |= int(bool(frame) and not safe and list(restored)!=raw) << lane
                    protectmask |= int(bool(frame) and safe) << lane
                    packed_rgb |= ((restored[0]<<16)|(restored[1]<<8)|restored[2]) << (24*lane)
                    packed_y |= luma(restored) << (8*lane)
                    changed[frame] += restored != rgb
                    protected[frame] += bool(frame) and safe
                    clipped[frame] += bool(frame) and not safe and list(restored)!=raw
                golden.write(f'{packed_rgb|(packed_y<<96)|(clipmask<<128)|(protectmask<<132):034x}\n')
    assert changed[0] == 0 and all(v > groups for v in changed[1:]), changed
    assert len(set(m.atmosphere for m in maps)) >= 2
    result = dict(status='PASS_ORACLE_GENERATION', rows=rows, groups_per_frame=groups,
                  frames=FRAMES, original_observation_frames=FRAMES-1, map_tiles=144*(FRAMES-1),
                  atmospheres=[m.atmosphere for m in maps], changed_pixels=changed,
                  protected_pixels=protected, clipped_pixels=clipped,
                  scope='Four foreground frames using three independently estimated full-HD original-observation histories; bilinear gain and RGB/Y checked',
                  authorities=[{'path':p.as_posix(),'sha256':sha(p)} for p in sorted((HERE/'oracle').iterdir()) if p.is_file()],
                  outputs=[{'path':p.as_posix(),'sha256':sha(p)} for p in sorted(output.glob('*.hex'))])
    (output/'reference.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ('status','rows','frames','atmospheres','changed_pixels')}), flush=True)
    return result


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--smoke', action='store_true')
    args = ap.parse_args()
    generate(args.output.resolve(), smoke=args.smoke)
