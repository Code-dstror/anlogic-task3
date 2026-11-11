"""Independent scalar F23 fixtures; no RTL hierarchy or history-state model."""
from pathlib import Path
import json

YB = [0, 67, 135, 202]
YE = [67, 135, 202, 270]


def pack(fields):
    value = 0
    for item, width in fields:
        assert 0 <= item < 1 << width, (item, width)
        value = value << width | item
    return value


def array(values):
    return sum(v << (13 * i) for i, v in enumerate(values))


def config(c):
    return pack([(c[k], n) for k, n in [
        ('context', 160), ('native_w', 13), ('native_h', 13), ('threshold', 11),
        ('gx_min', 11), ('ratio', 2), ('sign', 2), ('min_count', 20), ('min_strips', 4)]]
        + [(array(c[k]), 52) for k in ('yb', 'ye', 'left', 'split', 'right')])


def expected(c, points, error=0):
    """Filter scalar points independently for each of the eight rectangles."""
    rows = []
    paired = 0
    for band in range(4):
        sides = []
        for side in range(2):
            selected = []
            for x, y, gx, gy in points:
                if not (c['yb'][band] <= y < c['ye'][band]
                        and c['left'][band] <= x < c['right'][band]
                        and (x >= c['split'][band]) == bool(side)):
                    continue
                mag = abs(gx) + abs(gy)
                if (gx == 0 or mag < c['threshold'] or abs(gx) < c['gx_min']
                        or abs(gy) > abs(gx) * 2 ** c['ratio']
                        or c['sign'] == 1 and gx < 0 or c['sign'] == 2 and gx > 0):
                    continue
                selected.append((4 * x, 4 * y, mag))
            valid = len(selected) >= c['min_count']
            peak = min(selected, key=lambda p: (-p[2], p[1], p[0])) if selected else (0, 0, 0)
            fields = [(len(selected), 20), (sum(p[0] for p in selected), 32),
                      (sum(p[2] for p in selected), 30), (peak[2], 11),
                      (peak[0], 13), (peak[1], 13), (int(valid), 1)]
            sides.append((0 if error else pack(fields), valid))
        paired += sides[0][1] and sides[1][1]
        rows.append(pack([(4*c['yb'][band], 13),
                          (min(4*c['ye'][band], c['native_h']), 13),
                          (sides[0][0], 120), (sides[1][0], 120)]))
    header = pack([(c['context'], 160), (int(error == 0), 1), (error, 8),
                   (int(error == 0 and paired >= c['min_strips']), 1),
                   (c['native_w'], 13), (c['native_h'], 13),
                   ((c['native_w']+3)//4, 13), ((c['native_h']+3)//4, 13),
                   (c['threshold'], 11), (c['gx_min'], 11), (c['ratio'], 2),
                   (c['sign'], 2), (c['min_count'], 20), (c['min_strips'], 4),
                   (0 if error else len(points), 20)])
    return header << 1064 | sum(row << (266*s) for s, row in enumerate(rows))


def make_case(index, mode, ratio=0, sign=0, threshold=0, gx_min=0, mono=True):
    c = dict(context=(0x23040000 << 128) | index, native_w=1920 if mono else 28,
             native_h=1080 if mono else 31, threshold=threshold, gx_min=gx_min,
             ratio=ratio, sign=sign, min_count=1, min_strips=4,
             yb=YB if mono else [0, 2, 4, 6], ye=YE if mono else [2, 4, 6, 8],
             left=[0]*4, split=[240 if mono else 3]*4, right=[480 if mono else 7]*4)
    w, h = (c['native_w']+3)//4, (c['native_h']+3)//4
    points, events = [], []
    choices = [(0,0), (1,0), (29,101), (30,100), (31,99), (100,29), (100,30), (100,99), (100,100),
               (100,101), (100,200), (100,201), (100,400), (100,401),
               (100,800), (100,801), (-100,-100), (-1020,1020), (1020,1020)]
    for y in range(h):
        for x in range(0, w, 4):
            keep = (1 << min(4, w-x)) - 1
            gx, gy, mag = [], [], []
            for lane in range(4):
                px = x+lane
                if not (keep >> lane & 1):
                    dx, dy = -1024, -1024
                elif mode == 'dense':
                    dx, dy = 1020, 1020
                elif mode == 'boundaries':
                    # Every band/side has a different count/sum. Repeated equal
                    # peaks on a vector and later rows prove raster tie order.
                    band = next(b for b in range(4) if YB[b] <= y < YE[b])
                    dx, dy = (100+band*11+int(px>=240)*3, 0) if (
                        y in [0,66,67,134,135,201,202,269]
                        and px in [0,1,2,3,238,239,240,241,478,479]
                        and (px+y) % (band+2) != 0) else (0,0)
                elif mode == 'negative':
                    dx, dy = -1020, -1020
                elif mode == 'flat':
                    dx, dy = 0, 0
                else:
                    dx, dy = choices[(px*7+y*11) % len(choices)]
                if keep >> lane & 1:
                    points.append((px,y,dx,dy))
                gx.append(dx & 2047); gy.append(dy & 2047)
                mag.append((abs(dx)+abs(dy)) & 2047)
            meta = pack([(c['context'],160),(2,2),(w,13),(h,13),(x,13),(y,13),
                         (keep,4),(int(x==0 and y==0),1),(int(x+keep.bit_count()==w),1),
                         (int(x+keep.bit_count()==w and y==h-1),1)])
            events.append(pack([(1,1),(meta,221),
                (sum(v << (11*k) for k,v in enumerate(gx)),44),
                (sum(v << (11*k) for k,v in enumerate(gy)),44),
                (sum(v << (11*k) for k,v in enumerate(mag)),44)]))
    return c, points, events


def generate(out):
    out.mkdir(parents=True, exist_ok=True)
    cases = []
    specs = [('dense',0,0,2040,1020,True), ('boundaries',0,0,1,0,True),
             ('negative',0,2,2040,1020,True), ('flat',0,0,0,0,True)]
    specs += [('mixed',r,s,130,30,True) for r,s in [(0,1),(1,2),(2,0),(3,1)]]
    specs += [('mixed',r,s,130,30,False) for r in range(4) for s in range(3)]
    specs += [('dense',0,0,2040,1020,True)] * 2
    for index, spec in enumerate(specs):
        c, points, events = make_case(index, *spec)
        # 68-row bands reach 16320; 67-row bands reach 16080. A count
        # threshold above the narrowed register capacity must not alias.
        if index == 20:
            c.update(min_count=16320, min_strips=2)
        if index == 21:
            c.update(min_count=16384, min_strips=1)
        (out/f'case_{index}.hex').write_text(''.join(f'{e:089x}\n' for e in events), encoding='ascii')
        result = expected(c, points)
        cases.append(dict(index=index, mode=spec[0], mono=spec[-1], events=len(events),
                          config=f'{config(c):0124x}', record=f'{result:0339x}', config_values=c))
    for key, filename, fmt in [('config','configs.hex','{}'), ('record','records.hex','{}'),
                               ('events','counts.hex','{:08x}'), ('mono','mono.hex','{:x}')]:
        (out/filename).write_text(''.join(fmt.format(c[key])+'\n' for c in cases), encoding='ascii')
    (out/'reference.json').write_text(json.dumps({'cases':cases, 'model':'scalar rectangle lists'}, indent=2)+'\n')
    return cases
