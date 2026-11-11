"""Compare full-resolution steady-state output with source and paired photographs."""
from pathlib import Path
import argparse, csv, hashlib, json, math
import cv2
import numpy as np
from PIL import Image, ImageOps
from reference import estimate,luma,restore


def raster(path):
    with Image.open(path) as image:
        return np.asarray(ImageOps.fit(ImageOps.exif_transpose(image).convert('RGB'), (1920,1080),
                                       method=Image.Resampling.BILINEAR))


def quality(a, b):
    diff=a.astype(np.float32)-b
    return round(10*math.log10(255**2 / float(np.mean(diff**2))),3)


def evaluate(source, out):
    out.mkdir(parents=True, exist_ok=True)
    inputs=['FD085.png','LH005.jpg','LH034.jpg','NIGHT.jpg','USER.png','O-HAZE-03-03_outdoor_hazy.JPG',
            'O-HAZE-09-09_outdoor_hazy.jpg','Dense-Haze-03-03_hazy.png',
            'NH-HAZE-03-03_hazy.png','I-HAZE-03-03_indoor_hazy.jpg']
    table=[]
    for filename in inputs:
        p=source/filename
        a=raster(p); hist=estimate(a); b=restore(a,hist)
        y0,y1=luma(a),luma(b)
        raw_strength=restore(a,estimate(a,protect=False))
        guard_off_delta=round(float((luma(raw_strength)-y0).mean()),3)
        measure=lambda im: cv2.magnitude(cv2.Sobel(im.astype('float32'),cv2.CV_32F,1,0),
                                          cv2.Sobel(im.astype('float32'),cv2.CV_32F,0,1))
        h,w=y0.shape
        roi=(slice(h//4,3*h//4),slice(w//4,3*w//4))
        row=dict(input=filename,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),air=hist[0],
                 gain_range=[int(hist[1].min()),int(hist[1].max())],
                 center_edge_ratio=round(float(measure(y1)[roi].mean()/max(0.001,measure(y0)[roi].mean())),3),
                 mean_Y_change_without_lowlight_protection=guard_off_delta,
                 added_highlight_clip_pct=round(100*float(((a.max(axis=2)<250)&(b.max(axis=2)>=250)).mean()),3),
                 mean_Y_change=round(float((y1-y0).mean()),3), dark_clipped_pct=round(100*float(((y0>=32)&(y1<=20)).mean()),3),
                 identity_fraction=round(float(np.all(a==b,axis=2).mean()),3))
        if '_hazy' in filename:
            gt_path=source/filename.replace('_hazy','_GT')
            if not gt_path.exists():gt_path=next(source.glob(gt_path.stem+'.*'))
            gt=raster(gt_path)
            row.update(gt=gt_path.name,GT_sha256=hashlib.sha256(gt_path.read_bytes()).hexdigest(),
                       PSNR_input=quality(a,gt),PSNR_output=quality(b,gt))
        table.append(row)
        if filename in ['FD085.png','LH005.jpg','LH034.jpg','NIGHT.jpg','O-HAZE-03-03_outdoor_hazy.JPG','USER.png']:
            items=[a,b]+([gt] if '_hazy' in filename else [])
            panel=Image.new('RGB',(480*len(items),270))
            for ix,item in enumerate(items):panel.paste(Image.fromarray(item).resize((480,270), Image.Resampling.LANCZOS),(ix*480,0))
            panel.save(out/(p.stem+'_comparison.jpg'),quality=90)
    (out/'quality.json').write_text(json.dumps({'method':'steady-state same image as previous qualified frame; no scene-specific tuning; PSNR on center-fitted RGB8; panels left=input,middle=output,right=GT when present','images':table},indent=2)+'\n',encoding='utf8')
    for r in table: print(r['input'],r['center_edge_ratio'],r['mean_Y_change'],r.get('PSNR_input'),r.get('PSNR_output'))


if __name__=='__main__':
    cli=argparse.ArgumentParser();cli.add_argument('--inputs',required=True,type=Path);cli.add_argument('--out',required=True,type=Path)
    args=cli.parse_args();evaluate(args.inputs,args.out)
