"""Source consumer mutations; temporary fixtures never touch APK/user data."""
import shutil
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET
from pathlib import Path

import android_policy_verify as policy


class AndroidPolicyTests(unittest.TestCase):
    def test_changed_generated_png_is_rejected(self):
        icons=policy.icon_verify.verify()
        path=next(p for p in icons if p.endswith('.png'))
        icons[path]['sha256']='0'*64
        with mock.patch.object(policy.icon_verify,'verify',return_value=icons):
            self.assertIn('BRAND_PNG_CHANGED',policy.verify()['violations'])

    def test_real_source_and_036_inputs(self):
        result = policy.verify()
        self.assertEqual(result['violations'], [])
        self.assertEqual(result['nativeValidation'], 'PENDING_MERGED_XML_APK_STARTUP_AND_TRANSPORT')
        legacy = ET.parse(policy.ROOT / 'android/app/src/main/res/xml/backup_rules.xml').getroot()
        self.assertEqual({e.get('domain') for e in legacy}, {
            'root', 'file', 'database', 'sharedpref', 'external',
            'device_root', 'device_file', 'device_database', 'device_sharedpref'})

    def mutate(self, path, change, expected):
        build = policy.ROOT / 'build'
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='016-mutant-', dir=build) as temp:
            root = Path(temp).resolve()
            self.assertTrue(root.is_relative_to(build.resolve()))
            shutil.copytree(policy.ROOT / 'android/app/src/main/res', root / 'android/app/src/main/res')
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            shutil.copyfile(policy.ROOT / 'android/app/src/main/AndroidManifest.xml', manifest)
            target = root / path
            tree = ET.parse(target)
            change(tree.getroot())
            tree.write(target, encoding='utf-8', xml_declaration=True)
            self.assertEqual(policy.verify(root, check_icons=False)['violations'], expected)

    def test_allow_backup_enabled(self):
        self.mutate('android/app/src/main/AndroidManifest.xml',
                    lambda r: r.find('application').set(policy.ANDROID + 'allowBackup', 'true'),
                    ['ALLOW_BACKUP_ENABLED'])

    def test_legacy_consumer_missing(self):
        self.mutate('android/app/src/main/AndroidManifest.xml',
                    lambda r: r.find('application').attrib.pop(policy.ANDROID + 'fullBackupContent'),
                    ['LEGACY_RULE_CONSUMER'])

    def test_modern_consumer_missing(self):
        self.mutate('android/app/src/main/AndroidManifest.xml',
                    lambda r: r.find('application').attrib.pop(policy.ANDROID + 'dataExtractionRules'),
                    ['MODERN_RULE_CONSUMER'])

    def test_d2d_missing(self):
        self.mutate('android/app/src/main/res/xml/data_extraction_rules.xml',
                    lambda r: r.remove(r.find('device-transfer')), ['MODERN_MODES', 'D2D_EXCLUSIONS'])

    def test_cloud_empty(self):
        self.mutate('android/app/src/main/res/xml/data_extraction_rules.xml',
                    lambda r: r.find('cloud-backup').clear(), ['CLOUD_EXCLUSIONS'])

    def test_each_mode_and_domain_omission(self):
        for mode in ('cloud-backup', 'device-transfer'):
            for domain in sorted(policy.DOMAINS):
                with self.subTest(mode=mode, domain=domain):
                    self.mutate('android/app/src/main/res/xml/data_extraction_rules.xml',
                                lambda r: r.find(mode).remove(r.find(mode).find("exclude[@domain='%s']" % domain)),
                                ['CLOUD_EXCLUSIONS' if mode == 'cloud-backup' else 'D2D_EXCLUSIONS'])

    def test_legacy_domain_omission(self):
        self.mutate('android/app/src/main/res/xml/backup_rules.xml',
                    lambda r: r.remove(r.find("exclude[@domain='root']")), ['LEGACY_EXCLUSIONS'])

    def test_background_white(self):
        self.mutate('android/app/src/main/res/values/colors.xml',
                    lambda r: setattr(r.find("color[@name='seguimiento_background']"), 'text', '#FFFFFF'),
                    ['BRAND_BACKGROUND'])

    def test_legacy_brand_reference_wrong(self):
        self.mutate('android/app/src/main/res/drawable/launch_background.xml',
                    lambda r: list(r)[1].set(policy.ANDROID + 'drawable', '@mipmap/ic_launcher'),
                    ['LAUNCH_GLYPH:drawable'])

    def test_modern_brand_reference_wrong(self):
        self.mutate('android/app/src/main/res/values-v31/styles.xml',
                    lambda r: setattr(r.find("style[@name='LaunchTheme']/item[@name='android:windowSplashScreenAnimatedIcon']"),
                                      'text', '@mipmap/ic_launcher'), ['SPLASH_GLYPH:values-v31'])

    def test_default_normal_theme(self):
        self.mutate('android/app/src/main/res/values-night/styles.xml',
                    lambda r: setattr(r.find("style[@name='NormalTheme']/item[@name='android:windowBackground']"),
                                      'text', '?android:colorBackground'), ['WINDOW_BACKGROUND:values-night:NormalTheme'])

    def test_unknown_domain_rejected(self):
        self.mutate('android/app/src/main/res/xml/backup_rules.xml',
                    lambda r: list(r)[0].set('domain', 'device_external'), ['LEGACY_EXCLUSIONS'])

    def test_inclusion_rejected(self):
        self.mutate('android/app/src/main/res/xml/data_extraction_rules.xml',
                    lambda r: setattr(list(r.find('device-transfer'))[0], 'tag', 'include'), ['D2D_EXCLUSIONS'])

    def test_parent_path_rejected(self):
        self.mutate('android/app/src/main/res/xml/backup_rules.xml',
                    lambda r: list(r)[0].set('path', '../'), ['LEGACY_EXCLUSIONS'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
