"""Integer reference for the shared 4PPC atmospheric-scattering pipeline."""
import numpy as np


def luma(rgb):
    rgb = np.asarray(rgb, dtype=np.int32)
    return (77*rgb[..., 0] + 150*rgb[..., 1] + 29*rgb[..., 2] + 128) >> 8


def estimate(rgb, *, protect=True):
    """Raster-order tie break. Four-by-four tiles, 64 sampled 8x4 patches per tile."""
    height, width = rgb.shape[:2]
    tw, th = width//4, height//4
    xs, ys = tw//(8*4)*4, th//8
    sums = np.zeros((4, 4), dtype=np.int32)
    dark_peak, air = 0, 192
    bright = chromatic = highlights = 0
    for ty in range(4):
        for by in range(8):
            y = ty*th + by*ys
            for tx in range(4):
                for bx in range(8):
                    x = tx*tw + bx*xs
                    patch = rgb[y:y+4,x:x+8]
                    representative = patch[-1,-1].astype(int)
                    light = int(luma(representative))
                    bright += light >= 96
                    highlights += light >= 224
                    chromatic += int(np.ptp(representative)) > 8
                    dark = int(patch.min())
                    sums[ty,tx] += dark
                    if dark > dark_peak:
                        dark_peak = dark
                        air = int(np.clip(luma(patch[-1,-1])//8*8, 192, 248))
    means = sums//64
    dark_code = np.maximum(0, (means//8)*8 + 4 - 24)
    den = np.maximum(2*air, 4*air - 3*dark_code)
    gains = np.minimum(256, (512*air + den//2)//den)
    if dark_peak < 64 or np.count_nonzero(means <= 48) >= 4:
        gains.fill(128)
    if protect and (bright < 128 or (chromatic < 64 and highlights >= 16)):
        gains = 128 + (gains - 128 + 2)//4
    return air, gains


def restore(rgb, history):
    if history is None:
        return rgb.copy()
    height, width = rgb.shape[:2]
    air, grid = history
    def axis(size, units, tile):
        pos = np.arange(size)//units
        t = pos//tile
        sub = np.minimum(7, (pos%tile)//(tile//8))
        start = t-(sub<4)
        return np.clip(start,0,3),np.clip(start+1,0,3),(sub+4)%8
    left,right,fx = axis(width,4,width//16)
    top,bottom,fy = axis(height,1,height//4)
    a = grid[top[:,None],left]*(8-fx)+grid[top[:,None],right]*fx
    b = grid[bottom[:,None],left]*(8-fx)+grid[bottom[:,None],right]*fx
    gain = ((a*(8-fy[:,None])+b*fy[:,None]+32)//64)[...,None]
    i = rgb.astype(np.int32)
    radiance=air+((i-air)*gain+64)//128
    return np.clip(np.maximum(np.maximum(i//2,i-48),radiance),0,255).astype(np.uint8)
