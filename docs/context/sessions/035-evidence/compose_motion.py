"""Assemble unchanged production-rendered PNG frames; never redraw a figure."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('input', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--reuse-clip5-from', type=Path)
parser.add_argument('--camera-comparison', type=Path)
args = parser.parse_args()
manifest = []
for clip_index in range(1, 8):
    clip_root = args.reuse_clip5_from if clip_index == 5 and args.reuse_clip5_from else args.input
    item = json.loads((clip_root / f'manifest-{clip_index}.json').read_text(encoding='utf-8'))
    if clip_root != args.input:
        comparison = json.loads(args.camera_comparison.read_text(encoding='utf-8'))
        assert comparison['pullupWorldSamples'] == 252 and comparison['pullupPixelPairs'] >= 11
        assert item[0]['sourceCommit'] == comparison['oldSource']
        item[0]['reuseVerification'] = str(args.camera_comparison.resolve())
        item[0]['verifiedAgainstProduct'] = comparison['currentProduct']
    assert len(item) == 1 and item[0]['clip'] == clip_index
    manifest.extend(item)
assert [c['frames'] for c in manifest] == [384, 336, 252, 192, 252, 160, 500]
assert len({c['sourceCommit'] for c in manifest if not c.get('reuseVerification')}) == 1
(args.input / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
args.output.mkdir(parents=True, exist_ok=True)
receipts = []
for index, clip in enumerate(manifest, 1):
    source = (args.reuse_clip5_from if index == 5 and args.reuse_clip5_from else args.input) / str(index)
    paths = sorted(source.glob('*.png'))
    assert len(paths) == clip['frames'], (index, len(paths), clip['frames'])
    assert clip['fps'] == 20
    milliseconds = 1000 // clip['fps']
    palette = Image.open(paths[0]).convert('RGB').quantize(colors=256)
    frames = [Image.open(path).convert('RGB').quantize(palette=palette,
              dither=Image.Dither.NONE) for path in paths]
    target = args.output / f'{index}.gif'
    frames[0].save(target, save_all=True, append_images=frames[1:],
                   duration=milliseconds, loop=0, disposal=2, optimize=False)
    with Image.open(target) as result:
        duration = 0
        for frame in range(result.n_frames):
            result.seek(frame)
            duration += result.info['duration']
        assert duration == milliseconds * len(paths), (duration, milliseconds * len(paths))
        encoded_frames = result.n_frames
        size = result.size
    receipts.append({'file': str(target.resolve()), 'sourceCommit': clip['sourceCommit'],
        'reuseVerification': clip.get('reuseVerification'),
        'verifiedAgainstProduct': clip.get('verifiedAgainstProduct'),
        'names': clip['names'], 'fpsInput': clip['fps'], 'pngFrames': len(paths),
        'gifFrames': encoded_frames, 'durationMs': duration, 'size': size,
        'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
        'assembly': 'PNG order unchanged; shared256-color GIF palette/no dither;50ms per input; no redraw/time scaling',
        'pngHashes': [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]})
    for image in frames:
        image.close()
    palette.close()
(args.output / 'assembly-receipt.json').write_text(json.dumps(receipts, indent=2,
    ensure_ascii=False), encoding='utf-8')
print(json.dumps([{k:v for k,v in r.items() if k != 'pngHashes'} for r in receipts],
                 indent=2, ensure_ascii=False))

