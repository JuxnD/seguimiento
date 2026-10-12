"""Real CLI negatives on temporary copies of the pinned bundle."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from gateway_contract_verify import BUNDLE, FILES, ROOT


class ContractTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='seguimiento-contract-')
        self.addCleanup(self.temp.cleanup)
        self.bundle = Path(self.temp.name) / 'bundle'
        shutil.copytree(BUNDLE, self.bundle)

    def cli(self):
        run = subprocess.run([sys.executable, '-B', str(ROOT / 'tool/gateway_contract_verify.py'),
                              '--bundle', str(self.bundle)], capture_output=True, text=True)
        return run.returncode, json.loads(run.stdout)

    def test_intact(self):
        self.assertEqual(self.cli(), (0, {'status': 'PASS', 'errors': []}))

    def test_changed_file(self):
        name = sorted(FILES)[0]
        with (self.bundle / name).open('ab') as out:
            out.write(b'\n// mutation\n')
        self.assertEqual(self.cli(), (1, {'status': 'FAIL', 'errors': ['HASH:' + name]}))

    def test_missing_file(self):
        name = sorted(FILES)[0]
        (self.bundle / name).unlink()
        self.assertEqual(self.cli(), (1, {'status': 'FAIL', 'errors': ['MISSING:' + name]}))

    def test_extra_file(self):
        (self.bundle / 'unexpected.txt').write_text('synthetic', encoding='utf-8')
        self.assertEqual(self.cli(), (1, {'status': 'FAIL', 'errors': ['EXTRA:unexpected.txt']}))

    def test_untrusted_manifest_path(self):
        path = self.bundle / 'manifest.json'
        data = json.loads(path.read_text(encoding='utf-8'))
        data['files']['../outside.php'] = '0' * 64
        path.write_text(json.dumps(data), encoding='utf-8')
        self.assertEqual(self.cli(), (1, {'status': 'FAIL', 'errors': ['MANIFEST_INVALID']}))


if __name__ == '__main__':
    unittest.main(verbosity=2)
