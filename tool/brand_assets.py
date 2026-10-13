"""My Prime derived brand files. The launcher SVG remains the sole icon master.

Wordmark uses authored polygons, not a font or raster. Preview is a resource
proof sheet, never evidence of Android installation or native splash rendering.
"""
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw
from icon_vector import render

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'assets/icon'
OUT=ROOT/'build/mockups/my-prime'
NS='{http://www.w3.org/2000/svg}'


def variant(name, background, symbol):
    tree=ET.parse(SRC/'seguimiento_icon.svg')
    for group in tree.getroot().findall(NS+'g'):
        colour=background if group.get('id')=='background' else symbol
        for element in group: element.set('fill',colour)
    target=SRC/name
    tree.write(target,encoding='unicode',xml_declaration=False)
    return target


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    variants=[SRC/'seguimiento_icon.svg',
              variant('my_prime_inverse.svg','#C1FF45','#171A1B'),
              variant('my_prime_one_ink_dark.svg','#F8F7F0','#171A1B'),
              variant('my_prime_one_ink_light.svg','#171A1B','#F8F7F0')]
    sheet=Image.new('RGB',(1200,760),'#F8F7F0')
    draw=ImageDraw.Draw(sheet)
    draw.text((24,20),'MY PRIME / RECURSOS GENERADOS / NO ES UNA CAPTURA ANDROID',fill='#171A1B')
    for i,path in enumerate(variants):
        img=render(path,512).crop((56,56,456,456)).resize((220,220),Image.Resampling.LANCZOS)
        sheet.paste(img,(24+i*290,60),img)
        img.save(OUT/(path.stem+'.png'))
        draw.text((24+i*290,288),path.stem,fill='#171A1B')
    icon=Image.open(SRC/'icono_1024.png').convert('RGBA')
    for i,size in enumerate((24,48,96,192,512)):
        scaled=icon.resize((size,size),Image.Resampling.LANCZOS)
        scaled.save(SRC/f'my_prime_{size}.png')
        if size<=192:
            sheet.paste(scaled,(24+i*150,330),scaled)
            draw.text((24+i*150,530),str(size)+'px real',fill='#171A1B')
    for i,style in enumerate(('round','squircle')):
        scaled=icon.resize((192,192),Image.Resampling.LANCZOS)
        mask=Image.new('L',(192,192),0);pen=ImageDraw.Draw(mask)
        if style=='round':pen.ellipse((0,0,191,191),fill=255)
        else:pen.rounded_rectangle((0,0,191,191),radius=45,fill=255)
        scaled.putalpha(mask);sheet.paste(scaled,(670+i*230,330),scaled)
        scaled.save(OUT/(style+'.png'));draw.text((670+i*230,530),style,fill='#171A1B')
    mark=render(SRC / 'my_prime_wordmark.svg',1024).crop((0,410,1024,530)).resize((650,76),Image.Resampling.LANCZOS)
    sheet.paste(mark,(24,585),mark)
    status=Image.open(ROOT/'android/app/src/main/res/drawable-mdpi/ic_stat_seguimiento.png')
    draw.rectangle((740,585,840,640),fill='#171A1B')
    sheet.paste(status,(760,610),status)
    draw.text((760,650),'Status24 alpha real',fill='#171A1B')
    sheet.save(OUT/'proof-sheet.png')
    print(OUT/'proof-sheet.png')


if __name__=='__main__':main()
