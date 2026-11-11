"""Scalar arithmetic contracts. Not RTL, image-quality or timing validation."""
from __future__ import annotations
from math import floor

def clamp(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))

def gray(rgb: tuple[int, int, int]) -> int:
    if any(not isinstance(x, int) or not 0 <= x <= 255 for x in rgb):
        raise ValueError("RGB8 required")
    r, g, b = rgb
    return (77*r + 150*g + 29*b + 128) >> 8

def gaussian3x3(values: list[list[int]]) -> int:
    if len(values) != 3 or any(len(row) != 3 for row in values):
        raise ValueError("3x3 window required")
    k = (1, 2, 1)
    return (sum(values[y][x]*k[y]*k[x] for y in range(3) for x in range(3)) + 8) >> 4

def he_lut(hist: list[int]) -> list[int]:
    if len(hist) != 256 or any(not isinstance(n, int) or n < 0 for n in hist):
        raise ValueError("256 nonnegative integer bins required")
    n = sum(hist)
    if n == 0:
        return list(range(256))
    first = next(h for h in hist if h)
    if n == first:
        return list(range(256))
    cdf = 0
    result = []
    for h in hist:
        cdf += h
        result.append(max(0, 255 * (cdf-first) // (n-first)))
    return result

def color_he(rgb: tuple[int,int,int], lut: list[int]) -> tuple[int,int,int]:
    y = gray(rgb)
    if len(lut) != 256 or any(not 0 <= n <= 255 for n in lut):
        raise ValueError("LUT8 required")
    delta = clamp(lut[y]-y, -32, 32)
    return tuple(clamp(c+delta, 0, 255) for c in rgb)

def lerp_q8(a: int, b: int, w: int) -> int:
    if not 0 <= w <= 256:
        raise ValueError("Q8 weight outside unit interval")
    return ((256-w)*a + w*b + 128) >> 8

def group_gain(r00: int, r01: int, r10: int, r11: int, wx: int, wy: int) -> int:
    """00 top-left,01 top-right,10 bottom-left,11 bottom-right.
    Vertical interpolation, then horizontal, each rounded half-up.
    """
    if any(not 256 <= r <= 512 for r in (r00,r01,r10,r11)):
        raise ValueError("dehaze inverse transmission outside frozen range")
    return lerp_q8(lerp_q8(r00,r10,wy), lerp_q8(r01,r11,wy),wx)

def same_color_predict(samples: list[int], width: int, start_x: int = 0) -> list[int]:
    if width < 1 or not 0 <= start_x < width or any(not 0 <= x < 1024 for x in samples):
        raise ValueError("invalid RAW geometry or value")
    out=[]
    for i,x in enumerate(samples):
        col=(start_x+i)%width
        pred=samples[i-2] if i>=2 and col>=2 else 0
        out.append((x-pred)&1023)
    return out

def same_color_restore(residuals: list[int], width: int, start_x: int = 0) -> list[int]:
    if width < 1 or not 0 <= start_x < width or any(not 0 <= x < 1024 for x in residuals):
        raise ValueError("invalid RAW geometry or value")
    out=[]
    for i,x in enumerate(residuals):
        col=(start_x+i)%width
        pred=out[i-2] if i>=2 and col>=2 else 0
        out.append((x+pred)&1023)
    return out

def aligned(n: int, alignment: int=64) -> int:
    if n < 0 or alignment <= 0: raise ValueError("invalid length/alignment")
    return ((n+alignment-1)//alignment)*alignment

def cfs_store_mode(raw_len: int, candidate_len: int | None, *, encode_busy=False, candidate_overflow=False, integrity_ok=True) -> str:
    if raw_len <= 0: raise ValueError("nonempty raw block required")
    if not integrity_ok: return "FAILED"
    if encode_busy: return "RAW_ENC_BUSY"
    if candidate_overflow: return "RAW_CANDIDATE_OVERFLOW"
    if candidate_len is None: return "FAILED"
    if candidate_len < 0: raise ValueError("invalid candidate")
    return "LZ77" if aligned(candidate_len)+64 <= aligned(raw_len) else "RAW_NO_BENEFIT"
