"""036: filled geometry support must not change the existing stroke renderer."""
import hashlib
from pathlib import Path
import tempfile
import shutil
import unittest
from icon_vector import render
import icons
import icon_verify

ROOT=Path(__file__).resolve().parents[1]


class IconVectorTests(unittest.TestCase):
    def source(self, path):
        return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
                '<g id="background"><rect x="0" y="0" width="1024" height="1024" fill="#171A1B"/></g>'
                '<g id="symbol">'+path+'</g></svg>')

    def draw(self, path):
        with tempfile.TemporaryDirectory() as temp:
            file=Path(temp)/'input.svg'
            file.write_text(self.source(path),encoding='utf-8')
            return render(file,size=128,layers=('symbol',))

    def test_legacy_stroke_pixel_identity(self):
        image=render(ROOT/'test/fixtures/icon_8ef2df4.svg',size=128)
        self.assertEqual(hashlib.sha256(image.tobytes()).hexdigest(),
                         'a4564439a50b26db3c0a0d8f0d7fcded438d16936549d1ceee834b650a93e30a')

    def test_explicit_closed_fill_has_solid_center_and_transparent_outside(self):
        image=self.draw('<path d="M 256 256 L 768 256 L 768 768 L 256 768 Z" fill="#C1FF45"/>')
        self.assertEqual(image.getpixel((64,64)),(193,255,69,255))
        self.assertEqual(image.getpixel((0,0))[3],0)

    def test_unsupported_or_ambiguous_fill_fails_closed(self):
        paths=[
            '<path d="M 256 256 L 768 256 L 768 768" fill="#C1FF45"/>',
            '<path d="M 1 1 L 2 2 Z" fill="#C1FF45" transform="rotate(5)"/>',
            '<path d="M 1 1 L 2 2 Z" style="fill:red"/>',
            '<path d="M 1 1 L 2 2 Z M 3 3 L 4 4 Z" fill="#C1FF45"/>',
            '<path d="M 1 1 Q 2 2 3 3 Z" fill="#C1FF45"/>',
            '<path d="M 1 1 L 2 2 Z" fill="#C1FF45" stroke="#FFFFFF"/>',
        ]
        for path in paths:
            with self.subTest(path=path),self.assertRaises(ValueError):self.draw(path)

    def test_old_well_formed_symbol_cannot_pass_as_current_generated_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            for relative in ['assets/icon','android/app/src/main','lib/data','tool']:
                shutil.copytree(ROOT/relative,root/relative)
            icons.main(root,quiet=True)
            old=render(ROOT/'test/fixtures/icon_8ef2df4.svg')
            old.crop((112,112,912,912)).resize((512,512)).save(root/'assets/icon/playstore_512.png')
            original=icon_verify.ROOT
            try:
                icon_verify.ROOT=root
                with self.assertRaisesRegex(ValueError,'Generated pixels mismatch: assets/icon/playstore_512.png'):
                    icon_verify.verify()
            finally:
                icon_verify.ROOT=original


if __name__=='__main__':unittest.main()
