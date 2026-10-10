"""Compare authored concepts and native icon resources at real sizes/masks."""
import argparse
import hashlib
import io
import json
import math
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from icon_vector import render

ROOT = Path(__file__).resolve().parent.parent
SIZES = [16, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 96, 108, 128, 144, 160, 192, 256, 512]
ALTERNATIVE = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<g id="background"><rect x="0" y="0" width="1024" height="1024" fill="#0B0806"/></g>
<g id="symbol">
<path d="M 730 648 C 661 758 447 790 337 682 C 224 571 245 394 342 315 C 410 259 480 245 552 259" fill="none" stroke="#F08A34" stroke-width="64" stroke-linecap="round"/>
<circle cx="570" cy="344" r="48" fill="#FFF6EC"/>
<path d="M 532 433 L 489 536 L 588 604 L 565 694" fill="none" stroke="#FFF6EC" stroke-width="62" stroke-linecap="round"/>
<path d="M 532 434 L 618 452 L 656 414" fill="none" stroke="#FFF6EC" stroke-width="46" stroke-linecap="round"/>
<path d="M 527 433 L 450 417 L 420 470" fill="none" stroke="#FFF6EC" stroke-width="46" stroke-linecap="round"/>
<path d="M 489 536 L 405 623 L 350 625" fill="none" stroke="#FFF6EC" stroke-width="62" stroke-linecap="round"/>
</g></svg>'''


def font(size, bold=False):
    path = Path('C:/Windows/Fonts/segoeuib.ttf' if bold else 'C:/Windows/Fonts/segoeui.ttf')
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default(size=size)


def mask(size, style):
    high = size * 4
    alpha = Image.new('L', (high, high))
    draw = ImageDraw.Draw(alpha)
    if style in {'circle', 'mono'}:
        draw.ellipse((0, 0, high-1, high-1), fill=255)
    elif style == 'rounded':
        draw.rounded_rectangle((0, 0, high-1, high-1), radius=high*.22, fill=255)
    elif style == 'squircle':
        points = []
        for i in range(513):
            angle = 2 * math.pi * i / 512
            points.append(((high-1)/2 + (high-1)/2 * math.copysign(abs(math.cos(angle))**.5, math.cos(angle)),
                           (high-1)/2 + (high-1)/2 * math.copysign(abs(math.sin(angle))**.5, math.sin(angle))))
        draw.polygon(points, fill=255)
    else:
        raise ValueError('Unknown icon mask')
    return alpha.resize((size, size), Image.Resampling.LANCZOS)


def masked(icon, size, style):
    result = icon.resize((size, size), Image.Resampling.LANCZOS)
    result.putalpha(mask(size, style))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / 'build/mockups/logo')
    parser.add_argument('--baseline-ref', default='d2d3070d6934eef2f70512e9cdea0b588b9c66a3')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'assets/icon/seguimiento_icon.svg'
    alternate = args.out / 'athlete-comparison.svg'
    alternate.write_text(ALTERNATIVE.replace('stroke-linecap="round"','stroke-linecap="round" stroke-linejoin="round"'), encoding='utf-8')
    # Historical byte source remains in Git; no dependency on edited PNGs.
    previous = subprocess.check_output(['git', 'show', args.baseline_ref + ':assets/icon/icono_1024.png'], cwd=ROOT)
    old = Image.open(io.BytesIO(previous)).convert('RGBA')
    current = Image.open(ROOT / 'assets/icon/icono_1024.png').convert('RGBA')
    alternate_icon = render(alternate).crop((112,112,912,912)).resize((1024,1024), Image.Resampling.LANCZOS)
    old.save(args.out / 'previous.png')
    alternate_icon.save(args.out / 'athlete-comparison.png')
    current.save(args.out / 'proposal.png')
    # Adaptive composition uses actual generated108dp resources, not store artwork.
    fg = Image.open(ROOT / 'assets/icon/ic_launcher_foreground_432.png').convert('RGBA')
    bg = Image.open(ROOT / 'assets/icon/ic_launcher_background_432.png').convert('RGBA')
    adaptive = Image.alpha_composite(bg, fg).crop((72,72,360,360))
    mono = Image.open(ROOT / 'assets/icon/ic_launcher_monochrome_432.png').convert('RGBA').crop((72,72,360,360))
    themed = Image.new('RGBA', mono.size, '#35251A')
    themed.alpha_composite(mono)
    for size in SIZES:
        for style in ('circle','squircle','rounded','mono'):
            masked(themed if style == 'mono' else adaptive, size, style).save(args.out / f'{style}-{size}.png')
    sheet = Image.new('RGB', (1500,1120), '#150F0B')
    draw = ImageDraw.Draw(sheet)
    draw.text((60,45),'Seguimiento',font=font(44,True),fill='#FFF6EC')
    draw.text((60,103),'Propuesta de símbolo · todavía no instalada',font=font(24),fill='#C9B8A8')
    for x, image, title, detail in [(80,old,'Anterior','Anillo de diez segmentos y figura'),
                                   (540,current,'S en movimiento','Elegida: una ruta, una forma'),
                                   (1000,alternate_icon,'Atleta + arco','Comparación: más piezas pequeñas')]:
        sheet.paste(masked(image,220,'rounded'),(x+65,174),masked(image,220,'rounded'))
        draw.text((x,423),title,font=font(30,True),fill='#FFF6EC')
        draw.text((x,468),detail,font=font(19),fill='#C9B8A8')
        for j,size in enumerate((24,32,48,64)):
            glyph=masked(image,size,'circle')
            sheet.paste(glyph,(x+j*90+10,535+(64-size)//2),glyph)
            draw.text((x+j*90+6,614),str(size)+' px',font=font(16),fill='#C9B8A8')
    draw.line((60,671,1440,671),fill='#4A3526',width=1)
    draw.text((60,710),'Recursos Android generados',font=font(28,True),fill='#FFF6EC')
    for x,style,title in [(80,'circle','Circular'),(350,'squircle','Squircle'),(620,'rounded','Redondeado'),(890,'mono','Monocromo')]:
        image=Image.open(args.out/f'{style}-128.png')
        sheet.paste(image,(x+30,777),image)
        draw.text((x,934),title,font=font(23),fill='#FFF6EC')
    status = Image.open(ROOT/'android/app/src/main/res/drawable-mdpi/ic_stat_seguimiento.png')
    draw.text((1170,790),'Estado',font=font(22),fill='#FFF6EC')
    sheet.paste(status,(1215,839),status)
    draw.text((1170,889),'24 px reales',font=font(18),fill='#C9B8A8')
    draw.text((60,1030),'Silueta sin meta fija · negro cálido y naranja de la app · fuente SVG editable',font=font(23),fill='#C9B8A8')
    sheet.save(args.out/'comparison.png')
    sheet.save(args.out/'comparison.jpg',quality=95)
    phone=Image.new('RGB',(390,844),'#0B0806')
    pd=ImageDraw.Draw(phone)
    pd.text((24,30),'9:41',font=font(16,True),fill='#FFF6EC')
    pd.text((24,103),'Seguimiento',font=font(33,True),fill='#FFF6EC')
    pd.text((24,158),'Propuesta · no instalada',font=font(19),fill='#C9B8A8')
    icon=Image.open(args.out/'squircle-192.png')
    phone.paste(icon,(99,221),icon)
    pd.text((42,451),'Un símbolo para tu progreso.',font=font(21,True),fill='#FFF6EC')
    pd.text((42,498),'En el inicio del teléfono',font=font(20),fill='#C9B8A8')
    small=Image.open(args.out/'squircle-48.png')
    phone.paste(small,(55,552),small)
    pd.text((119,558),'Seguimiento',font=font(21),fill='#FFF6EC')
    pd.text((42,660),'En una notificación',font=font(20),fill='#C9B8A8')
    phone.paste(status,(55,712),status)
    pd.text((96,708),'Seguimiento',font=font(19),fill='#FFF6EC')
    phone.save(args.out/'phone.png')
    receipts={p.relative_to(args.out).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(args.out.glob('*.png'))}
    (args.out/'preview-hashes.json').write_text(json.dumps(receipts,indent=2),encoding='utf-8')
    print('Preview:',args.out,';20sizes ×4masks')


if __name__=='__main__':
    main()
