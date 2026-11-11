"""Frozen C1 integer frame reference. No sensor, transport or clock simulation.

Dependencies: registered Python 3.12, numpy, OpenCV. BGR inputs are ISP-output
approximations. Arrays are an offline convenience; only 24 winners/row are needed
by the selector. Point layout is the proposed 37 payload bits plus zero padding.
"""
from __future__ import annotations
import cv2
import numpy as np

WIDTH, HEIGHT = 1920, 1080
ROAD_FIRST, ROAD_LAST = 169, 269
WHITE, YELLOW = 1, 2


def gaussian(y):
    k = np.array([1, 2, 1], np.int16)
    total = cv2.sepFilter2D(y, cv2.CV_16S, k, k, borderType=cv2.BORDER_REPLICATE)
    return ((total + 8) >> 4).astype(np.uint8)


def features(bgr):
    assert bgr.shape == (HEIGHT, WIDTH, 3) and bgr.dtype == np.uint8
    v = bgr.astype(np.int32)
    b, g, r = v[:, :, 0], v[:, :, 1], v[:, :, 2]
    y = ((29*b + 150*g + 77*r + 128) >> 8).astype(np.uint8)
    quarter = gaussian(gaussian(y)[::2, ::2])[::2, ::2]
    gx = cv2.Sobel(quarter, cv2.CV_16S, 1, 0, ksize=3, borderType=cv2.BORDER_REPLICATE)
    gy = cv2.Sobel(quarter, cv2.CV_16S, 0, 1, ksize=3, borderType=cv2.BORDER_REPLICATE)
    lo, hi = v.min(axis=2), v.max(axis=2)
    white = ((lo >= 95) & (hi-lo <= 40)).reshape(270,4,480,4).any(axis=(1,3))
    yellow = ((r >= 70) & (g >= 70) & (b+24 < np.minimum(r,g)) &
              (np.abs(r-g) <= np.maximum(24,np.maximum(r,g) >> 2)))
    yellow = yellow.reshape(270,4,480,4).any(axis=(1,3))
    flags = np.where(yellow,YELLOW,white.astype(np.uint8)).astype(np.uint8)
    return quarter, gx, gy, flags


def ridge_candidates(q, gx, gy, flags):
    """Same preselection ridges as original C; shortest *valid* pair per left.

    For all real x, positive plateau ties choose the leftmost maximum; an
    out-of-image peak neighbour adds no test. Background indices clamp.
    Each left edge may reuse a negative edge belonging to another left edge.
    """
    assert q.shape == gx.shape == gy.shape == flags.shape == (270,480)
    dx, dy, y = gx.astype(np.int32), gy.astype(np.int32), q.astype(np.int32)
    positive = (dx >= 20) & (np.abs(dy) <= (dx << 2))
    positive[:,1:] &= dx[:,1:] > dx[:,:-1]
    positive[:,:-1] &= dx[:,:-1] >= dx[:,1:]
    ndx = -dx
    negative = (ndx >= 20) & (np.abs(dy) <= (ndx << 2))
    negative[:,1:] &= ndx[:,1:] > ndx[:,:-1]
    negative[:,:-1] &= ndx[:,:-1] >= ndx[:,1:]
    used = np.zeros(q.shape,bool)
    points = []
    for d in range(1,9):
        n = 480-d
        x = np.arange(n)
        c = x+d//2
        good = positive[:,:n] & negative[:,d:] & ~used[:,:n]
        good &= y[:,c] - np.maximum(y[:,np.maximum(x-2,0)], y[:,np.minimum(x+d+2,479)]) >= 6
        dl, dr = dy[:,:n],dy[:,d:]
        good &= (dl == 0) | (dr == 0) | ((dl < 0) != (dr < 0))
        good &= flags[:,c] != 0
        rows, lefts = np.nonzero(good)
        used[rows,lefts] = True
        for row,left in zip(rows,lefts):
            if not ROAD_FIRST <= row <= ROAD_LAST:
                continue
            strength = min(int(dx[row,left]),int(-dx[row,left+d])) + min(abs(int(dy[row,left])),abs(int(dy[row,left+d])))
            points.append(dict(native_x=int(4*left+2*d),native_y=int(4*row),
                strength=strength,width_quarter=d,marking_class=int(flags[row,left+d//2])))
    return points


def rank(p):
    return (-p['strength'],p['native_x'],p['width_quarter'])


def select_rows(points, *, bins=True, original_c=False, bin_width_quarter=40, per_bin=2):
    """C1: 12 bins x online2 then yellow-first top3, >=24 native-pixel separation.

    original_c=True reproduces old C's class quotas and x restrictions, useful
    only as the comparison control. bins=False isolates the binning loss.
    """
    out=[]
    for row in range(ROAD_FIRST,ROAD_LAST+1):
        ps=[p for p in points if p['native_y']==4*row]
        if original_c:
            for cls,limit in [(YELLOW,1),(WHITE,2)]:
                candidates=[p for p in ps if p['marking_class']==cls and
                    (p['native_x'] <= int(1344-(row-169)*384/100) if cls==YELLOW else
                     p['native_x'] >= int(192+(row-169)*384/100))]
                chosen=[]
                for p in sorted(candidates,key=rank):
                    if all(abs(p['native_x']-s['native_x'])>=24 for s in chosen):
                        chosen.append(p)
                        if len(chosen)==limit:break
                out.extend(chosen)
            continue
        if bins:
            winners={}
            # Fixed-width bin2 is explicitly an online two-slot selector, not
            # an impossible recovery of candidates suppressed earlier.
            for p in sorted(ps,key=lambda p:((p['native_x']-2*p['width_quarter'])//4,p['width_quarter'])):
                b=p['native_x']//(4*bin_width_quarter)
                kept=[]
                for candidate in sorted(winners.get(b,[])+[p],key=rank):
                    if all(abs(candidate['native_x']-s['native_x'])>=24 for s in kept):
                        kept.append(candidate)
                        if len(kept)==per_bin:break
                winners[b]=kept
            ps=[p for values in winners.values() for p in values]
        yellows=[p for p in ps if p['marking_class']==YELLOW]
        chosen=[min(yellows,key=rank)] if yellows else []
        for p in sorted(ps,key=rank):
            if len(chosen)==3:break
            if all(abs(p['native_x']-s['native_x'])>=24 for s in chosen):chosen.append(p)
        out.extend(sorted(chosen,key=lambda p:p['native_x']))
    return out


def extract(bgr):
    return select_rows(ridge_candidates(*features(bgr)))


def pack_point(p):
    x,y,s,w,c=(p[k] for k in ('native_x','native_y','strength','width_quarter','marking_class'))
    if not (0<=x<1920 and x%2==0 and y%4==0 and ROAD_FIRST<=y//4<=ROAD_LAST and
            0<=s<=2040 and 1<=w<=8 and c in (WHITE,YELLOW)):
        raise ValueError('invalid C1 point')
    word=x | ((y//4)<<11) | (s<<20) | (w<<31) | (c<<35)
    return word.to_bytes(5,'little')


def unpack_point(data):
    if len(data)!=5:raise ValueError('point length')
    v=int.from_bytes(data,'little')
    if v>>37:raise ValueError('reserved bits')
    p=dict(native_x=v&2047,native_y=((v>>11)&511)*4,strength=(v>>20)&2047,
           width_quarter=(v>>31)&15,marking_class=(v>>35)&3)
    pack_point(p)
    return p
