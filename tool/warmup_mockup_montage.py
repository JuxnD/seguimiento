"""Compose the actual Flutter captures, never synthesize or alter a pose."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', default='build/mockups/calentamiento')
    parser.add_argument('--output', default='docs/design/calentamiento-014')
    args = parser.parse_args()
    source, output = Path(args.source), Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    rows = [line.split('|') for line in (source/'catalog.tsv').read_text(encoding='utf-8').splitlines()]
    if len(rows) != 6:
        raise ValueError('Expected precisely the six warmup guides')
    summary = Image.new('RGB', (1080, 6*410), (11, 8, 6))
    for row, (slug, name, group, count) in enumerate(rows):
        count = int(count)
        files = [source/f'{slug}-{i}.png' for i in range(count)]
        files += [source/f'{slug}-intermedio-15.png', source/f'{slug}-intermedio-35.png']
        if name == 'Balanceos de pierna':
            files.append(source/f'{slug}-derecho-15.png')
        strip = Image.new('RGB', (270*len(files), 310), (11, 8, 6))
        for col, path in enumerate(files):
            image = Image.open(path).convert('RGB')
            image.thumbnail((270, 310))
            strip.paste(image, (col*270, 0))
        strip.save(output/f'{slug}-recorrido.jpg', quality=92)
        indices = [0, 3, 8, 'intermedio-15'] if name == 'Balanceos de pierna' else [0, (count-1)//2, count-1, 'intermedio-15']
        for col, index in enumerate(indices):
            image = Image.open(source/f'{slug}-{index}.png').convert('RGB')
            image.thumbnail((270, 410))
            summary.paste(image, (col*270, row*410))
    summary.save(output/'resumen.jpg', quality=92)
    for location in ['top', 'cues']:
        mobile = Image.new('RGB', (6*270, 600), (11, 8, 6))
        for index in range(6):
            image = Image.open(source/f'sheet-{index+1}-1.6-{location}.png').convert('RGB')
            image.thumbnail((270, 600))
            mobile.paste(image, (index*270, 0))
        mobile.save(output/f'hojas-texto-1-6-{location}.jpg', quality=92)
    hashes = {path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(source.glob('*.png'))}
    (output/'capturas-sha256.json').write_text(json.dumps(hashes, indent=2)+'\n', encoding='utf-8')
    print(f'{len(hashes)} Flutter captures;6 complete sequences and3 montages')


if __name__ == '__main__':
    main()
