"""Validate generated Android icon artifacts, alpha and adaptive safe zone.

Not a clinical/brand/user-acceptance test. Reads real packaged resource inputs.
"""
import argparse
import hashlib
import json
import math
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DENSITIES = {'mdpi':1,'hdpi':1.5,'xhdpi':2,'xxhdpi':3,'xxxhdpi':4}


def check(condition, message):
    if not condition:
        raise ValueError(message)


def verify():
    src, res = ROOT/'assets/icon', ROOT/'android/app/src/main/res'
    manifest=ET.parse(ROOT/'android/app/src/main/AndroidManifest.xml').getroot()
    application=manifest.find('application')
    check(application.get('{http://schemas.android.com/apk/res/android}icon')=='@mipmap/ic_launcher','Launcher consumer changed')
    check('@drawable/ic_stat_seguimiento' in (ROOT/'lib/data/notification_service.dart').read_text(encoding='utf-8'),'Status consumer changed')
    adaptive=ET.parse(res/'mipmap-anydpi-v26/ic_launcher.xml').getroot()
    check(adaptive.tag=='adaptive-icon','Invalid adaptive descriptor')
    check({e.tag:e.get('{http://schemas.android.com/apk/res/android}drawable') for e in adaptive}=={
        'background':'@mipmap/ic_launcher_background','foreground':'@mipmap/ic_launcher_foreground',
        'monochrome':'@mipmap/ic_launcher_monochrome'},'Adaptive resource name mismatch')
    files={src/'icono_1024.png':1024,src/'playstore_512.png':512,
           src/'ic_launcher_foreground_432.png':432,src/'ic_launcher_background_432.png':432,
           src/'ic_launcher_monochrome_432.png':432}
    for name, factor in DENSITIES.items():
        files[res/f'mipmap-{name}/ic_launcher.png']=round(48*factor)
        for layer in ('foreground','background','monochrome'):
            files[res/f'mipmap-{name}/ic_launcher_{layer}.png']=round(108*factor)
        files[res/f'drawable-{name}/ic_stat_seguimiento.png']=round(24*factor)
    result={}
    for path,size in files.items():
        image=Image.open(path).convert('RGBA')
        check(image.size==(size,size),str(path)+' dimensions')
        alpha=image.getchannel('A')
        check(alpha.getbbox(),str(path)+' empty')
        is_glyph='foreground' in path.name or 'monochrome' in path.name or 'ic_stat_' in path.name
        white='monochrome' in path.name or 'ic_stat_' in path.name
        if is_glyph:
            check(alpha.getextrema()[0]==0,str(path)+' requires transparent background')
            check(alpha.getpixel((0,0))==0 and alpha.getpixel((size-1,size-1))==0,str(path)+' opaque corners')
            if 'ic_stat_' not in path.name:
                radius=size*72/108/2
                farthest=max(math.hypot(x+.5-size/2,y+.5-size/2) for y in range(size) for x in range(size)
                             if image.getpixel((x,y))[3]>8)
                check(farthest<=radius+.75,str(path)+' outside adaptive safe circle')
            if white:
                check(all(image.getpixel((x,y))[:3]==(255,255,255) for y in range(size) for x in range(size)
                           if alpha.getpixel((x,y))>0),str(path)+' nonwhite status/mono')
        else:
            check(alpha.getextrema()==(255,255),str(path)+' background not opaque')
        result[path.relative_to(ROOT).as_posix()]={'size':size,'alphaBounds':alpha.getbbox(),
                                                 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    source=src/'seguimiento_icon.svg'
    # Source and pipeline hashes bind the artifact set; no promise of APK identity.
    result['sources']={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in (source,ROOT/'tool/icon_vector.py',ROOT/'tool/icons.py')}
    result['status']='VALIDATED_RESOURCE_INPUTS'
    result['nativePngs']=25
    result['sourcePngs']=5
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt',type=Path,default=ROOT/'build/mockups/logo/resource-receipt.json')
    args=parser.parse_args()
    result=verify()
    args.receipt.parent.mkdir(parents=True,exist_ok=True)
    args.receipt.write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    print(result['status'],':25nativePNGs,5sourcePNGs;alpha,safezone,resource names OK')


if __name__=='__main__':
    main()
