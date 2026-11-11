"""F23 scalar golden. No fitted lanes, road accuracy claims or RTL state mirror."""
from __future__ import annotations
import argparse
import hashlib
import json
import random
from pathlib import Path

STRIPS = 4
RECORD_BITS = 292 + 266 * STRIPS


def pack(fields):
    value = 0
    for item, width in fields:
        assert 0 <= item < (1 << width)
        value = (value << width) | item
    return value


def array(values):
    return sum(v << (13 * n) for n, v in enumerate(values))


def config(case):
    return pack([(case[k], n) for k, n in [
        ("context",160),("native_w",13),("native_h",13),("threshold",11),
        ("gx_min",11),("ratio",2),("sign",2),("min_count",20),("min_strips",4)]]
        + [(array(case[k]),52) for k in ("yb","ye","left","split","right")])


def metadata(case, x, y, keep, scale=2):
    w, h = (case["native_w"] + 3) // 4, (case["native_h"] + 3) // 4
    count = keep.bit_count()
    return pack([(case["context"],160),(scale,2),(w,13),(h,13),(x,13),(y,13),
                 (keep,4),(int(x == 0 and y == 0),1),(int(x + count == w),1),
                 (int(x + count == w and y == h - 1),1)])


def evaluate(case, points, error=0):
    stats = []
    paired = 0
    for strip in range(STRIPS):
        sides = []
        for side in range(2):
            accepted = []
            for x, y, gx, gy in points:
                if not (case["yb"][strip] <= y < case["ye"][strip]
                        and case["left"][strip] <= x < case["right"][strip]):
                    continue
                if int(x >= case["split"][strip]) != side:
                    continue
                strength = abs(gx) + abs(gy)
                if gx == 0 or strength < case["threshold"] or abs(gx) < case["gx_min"]:
                    continue
                if abs(gy) > abs(gx) * (1 << case["ratio"]):
                    continue
                if case["sign"] == 1 and gx <= 0 or case["sign"] == 2 and gx >= 0:
                    continue
                accepted.append((x * 4, y * 4, strength))
            count = len(accepted)
            valid = count >= case["min_count"]
            if accepted:
                peak = sorted(accepted, key=lambda p: (-p[2],p[1],p[0]))[0]
            else:
                peak = (0,0,0)
            sides.append((pack([(count,20),(sum(p[0] for p in accepted),32),
                               (sum(p[2] for p in accepted),30),(peak[2],11),
                               (peak[0],13),(peak[1],13),(int(valid),1)]), valid))
        paired += sides[0][1] and sides[1][1]
        stats.append(pack([(case["yb"][strip]*4,13),
                           (min(case["ye"][strip]*4,case["native_h"]),13),
                           (0 if error else sides[0][0],120),(0 if error else sides[1][0],120)]))
    header = pack([(case["context"],160),(int(not error),1),(error,8),
                   (int(not error and paired >= case["min_strips"]),1),
                   (case["native_w"],13),(case["native_h"],13),
                   ((case["native_w"]+3)//4,13),((case["native_h"]+3)//4,13),
                   (case["threshold"],11),(case["gx_min"],11),(case["ratio"],2),
                   (case["sign"],2),(case["min_count"],20),(case["min_strips"],4),
                   (0 if error else len(points),20)])
    return (header << (266 * STRIPS)) | sum(v << (266 * s) for s,v in enumerate(stats))


def make_case(index, w, h, rng, variant):
    low_w, low_h = (w+3)//4, (h+3)//4
    horizon = low_h // 5
    yb = [horizon + (low_h-horizon) * k // STRIPS for k in range(STRIPS)]
    ye = yb[1:] + [low_h]
    # Scalar config coordinates, not a generated interpolation divider in RTL.
    left = [min(3-k, (low_w-2)//2) for k in range(STRIPS)]
    right = [low_w-v for v in left]
    c = dict(context=((0xAA001100 + index%2) << 128) | (index << 32) | 0x12345678,
             native_w=w,native_h=h,threshold=[0,80,300,2040][(index//4)%4],
             gx_min=[0,30,100,1020][(index//4)%4],ratio=(index//4)%4,sign=(index//3)%3,
             min_count=1+index%5,min_strips=1+index%4,yb=yb,ye=ye,left=left,
             split=[low_w//2]*4,right=right)
    if variant == "none":
        c.update(threshold=0,gx_min=0,sign=0,min_count=1,min_strips=1)
    points = []
    events = []
    for y in range(low_h):
        for x in range(0,low_w,4):
            count = min(4,low_w-x)
            keep = (1<<count)-1
            gx,gy,mag = [],[],[]
            for lane in range(4):
                if lane >= count:
                    dx,dy = -1024,-1024 # poison unused lanes, must be ignored
                elif variant == "ties":
                    dx,dy = 200,100
                elif variant == "none":
                    dx,dy = 0,0
                else:
                    choices = [(0,0),(1020,1020),(-1020,-1020),(-1020,0),
                               (100,101),(-100,-100),(100,200),(100,201),
                               (100,400),(100,401),(100,800),(100,801),
                               (100,-200),(30,0),(29,0),(0,1020)]
                    dx,dy = choices[rng.randrange(len(choices))]
                if lane < count: points.append((x+lane,y,dx,dy))
                gx.append(dx & 2047);gy.append(dy & 2047)
                mag.append((abs(dx)+abs(dy)) & 2047)
            meta = metadata(c,x,y,keep)
            events.append(pack([(1,1),(meta,221),(sum(v<<(11*k) for k,v in enumerate(gx)),44),
                               (sum(v<<(11*k) for k,v in enumerate(gy)),44),
                               (sum(v<<(11*k) for k,v in enumerate(mag)),44)]))
            # Interleaved half event with foreign context and invalid numbers:
            # quarter consumer must ignore it completely.
            if variant != "throughput" and len(events)%5 == 0:
                half = meta ^ (3 << 59) ^ (1 << 160)
                events.append(pack([(1,1),(half,221),((1<<44)-1,44),((1<<44)-1,44),(0,44)]))
    error = 0
    if variant == "keep":
        events[0] ^= (15 ^ 5) << (132+3)
        error = 4
    elif variant == "coordinate":
        events[1] ^= 1 << (132+20)
        error = 6
    elif variant == "gradient":
        events[0] ^= 1 # magnitude mismatch in lane0
        error = 2
    elif variant == "truncated":
        events = events[:len(events)//2]
        error = 7
    elif variant == "source_error":
        error = 0x85
    elif variant == "config":
        c["right"][0] = low_w+1
        error = 1
    elif variant == "context":
        events[0] ^= 1 << (132+61)
        error = 3
    elif variant == "marker":
        events[0] ^= 1 << (132+2)
        error = 5
    elif variant == "extra_tail":
        events.append(events[-1])
        error = 5
    return c,events,evaluate(c,points,error),error


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--out-dir",type=Path,required=True)
    args=parser.parse_args();args.out_dir.mkdir(parents=True,exist_ok=True)
    rng=random.Random(2307)
    cases=[]
    variants=["random","ties","none","keep","coordinate","gradient","truncated","source_error","config","context","marker","extra_tail"]
    for index in range(42):
        w=[8,12,16,20,24,28,36,1920][index%8]
        h=[16,17,20,31,1080][index%5]
        variant=variants[index%len(variants)]
        if index >= 40:
            w,h=1920,1080
            variant="ties" if index == 40 else "throughput"
        c,events,result,error=make_case(index,w,h,rng,variant)
        (args.out_dir/f"case_{index}.hex").write_text("".join(f"{e:089x}\n" for e in events),encoding="ascii")
        cases.append(dict(index=index,variant=variant,events=len(events),error=error,
                          config=f"{config(c):0124x}",record=f"{result:0339x}",
                          event_sha256=hashlib.sha256((args.out_dir/f"case_{index}.hex").read_bytes()).hexdigest()))
    (args.out_dir/"configs.hex").write_text("".join(c["config"]+"\n" for c in cases),encoding="ascii")
    (args.out_dir/"records.hex").write_text("".join(c["record"]+"\n" for c in cases),encoding="ascii")
    (args.out_dir/"counts.hex").write_text("".join(f"{c['events']:08x}\n" for c in cases),encoding="ascii")
    (args.out_dir/"errors.hex").write_text("".join(f"{c['error']:02x}\n" for c in cases),encoding="ascii")
    (args.out_dir/"reference.json").write_text(json.dumps(dict(model="scalar candidates and exact rational sums",cases=cases),indent=2)+"\n",encoding="utf-8")
    print(f"RESULT: PASS F23 lane golden {len(cases)} cases")


if __name__=="__main__":main()
