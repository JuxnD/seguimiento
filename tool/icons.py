"""Genera los íconos de Android desde assets/icon/ (ver assets/icon/LEEME.md).

    python tool/icons.py

- mipmap-*/ic_launcher.png: ícono clásico (Android < 8).
- mipmap-*/ic_launcher_foreground.png y _background.png + mipmap-anydpi-v26:
  ícono adaptable, con capa monocroma para los íconos temáticos de Android 13.
- drawable-*/ic_stat_seguimiento.png: ícono de la barra de estado. Android lo
  pinta con su color usando solo la transparencia, así que va en blanco y sin
  los segmentos apagados del anillo (se verían encendidos).

Se hace con Pillow en vez de flutter_launcher_icons para no sumar una
dependencia a un proyecto fijado en Flutter 3.22.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'assets' / 'icon'
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def save(img: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)


def main() -> None:
    legacy = Image.open(SRC / 'icono_1024.png').convert('RGBA')
    fg = Image.open(SRC / 'ic_launcher_foreground_432.png').convert('RGBA')
    bg = Image.open(SRC / 'ic_launcher_background_432.png').convert('RGBA')

    for name, f in DENSITIES.items():
        save(legacy, RES / f'mipmap-{name}' / 'ic_launcher.png', round(48 * f))
        save(fg, RES / f'mipmap-{name}' / 'ic_launcher_foreground.png', round(108 * f))
        save(bg, RES / f'mipmap-{name}' / 'ic_launcher_background.png', round(108 * f))

    adaptive = RES / 'mipmap-anydpi-v26' / 'ic_launcher.xml'
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    adaptive.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n',
        encoding='utf-8',
    )

    # Barra de estado: la zona segura del adaptable (72 de 108 dp) en blanco,
    # solo lo claro (figura y segmentos encendidos).
    side = fg.width * 72 // 108
    off = (fg.width - side) // 2
    crop = fg.crop((off, off, off + side, off + side))
    status = Image.new('RGBA', crop.size, (255, 255, 255, 0))
    px, out = crop.load(), status.load()
    for y in range(crop.height):
        for x in range(crop.width):
            r, g, b, a = px[x, y]
            luminance = 0.299 * r + 0.587 * g + 0.114 * b
            if a > 0 and luminance > 90:
                out[x, y] = (255, 255, 255, a)
    for name, f in DENSITIES.items():
        save(status, RES / f'drawable-{name}' / 'ic_stat_seguimiento.png', round(24 * f))
    print('íconos generados')


if __name__ == '__main__':
    main()
