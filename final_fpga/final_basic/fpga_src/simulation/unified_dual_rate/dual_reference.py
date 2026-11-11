"""Independent two-camera RAW10 fixture and unity-WB SDR ISP reference.

The CSI source uses these specified arithmetic patterns, never captured DUT
pixels. BLC50, RGGB reflect101 bilinear and the frozen gamma table are explicit.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3] / "verification_reference"
sys.path.insert(0, str(ROOT / "src_fpga/simulation"))
from shared_wide_isp_reference import GAMMA


def raw_sample(camera: int, x: int, y: int, pattern: str = 'dual_raw10_rggb_v1') -> int:
    if pattern == 'hashed_detail_v1':
        value = ((x//2*0x1f123bb5) ^ (y//2*0x5f356495) ^ ((camera+1)*0x9e3779b9)) & 0xffffffff
        for _ in range(2):
            value = ((value ^ (value >> 16))*0x45d9f3b) & 0xffffffff
        value ^= value >> 16
        return 64 + (value & 1023) % 896
    if pattern != 'dual_raw10_rggb_v1':
        raise ValueError('unknown physical RAW fixture pattern')
    if camera == 0:
        base = 100 + (x//16*3 + y//8*5) % 600
        return base + (180 if not (x % 2 or y % 2) else 20 if x % 2 and y % 2 else 90)
    if camera == 1:
        base = 80 + (x//8*7 + y//16*11) % 580
        return base + (20 if not (x % 2 or y % 2) else 160 if x % 2 and y % 2 else 110)
    raise ValueError("fixture camera must be 0 or 1")


def pixels(camera: int, width: int, height: int, pattern: str = 'dual_raw10_rggb_v1') -> list[tuple[int, int, int]]:
    if width < 2 or height < 2 or width % 4:
        raise ValueError("fixture geometry requires width multiple of four and height >= 2")
    def at(x, y):
        x = -x if x < 0 else 2*width-2-x if x >= width else x
        y = -y if y < 0 else 2*height-2-y if y >= height else y
        return max(0, raw_sample(camera, x, y, pattern)-50)
    image = []
    for y in range(height):
        for x in range(width):
            centre = at(x, y)
            cross = (at(x-1,y)+at(x+1,y)+at(x,y-1)+at(x,y+1)+2)//4
            diag = (at(x-1,y-1)+at(x+1,y-1)+at(x-1,y+1)+at(x+1,y+1)+2)//4
            horizontal = (at(x-1,y)+at(x+1,y)+1)//2
            vertical = (at(x,y-1)+at(x,y+1)+1)//2
            rgb = ((centre,cross,diag), (horizontal,centre,vertical),
                   (vertical,centre,horizontal), (diag,cross,centre))[(y % 2)*2+x % 2]
            image.append(tuple(GAMMA[value] for value in rgb))
    return image
