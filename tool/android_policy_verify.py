"""Verify Android source policy/brand consumers; not merged XML, APK or OEM QA."""
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path

import icon_verify

ROOT = Path(__file__).resolve().parent.parent
ANDROID = '{http://schemas.android.com/apk/res/android}'
DOMAINS = frozenset(('root', 'file', 'database', 'sharedpref', 'external',
                     'device_root', 'device_file', 'device_database', 'device_sharedpref'))


def verify(root=ROOT, check_icons=True):
    root = Path(root)
    res = root / 'android/app/src/main/res'
    errors, hashes = [], {}

    def require(ok, code):
        if not ok:
            errors.append(code)

    def xml(path):
        try:
            hashes[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
            return ET.parse(path).getroot()
        except (OSError, ET.ParseError):
            errors.append('INVALID_XML:' + path.relative_to(root).as_posix())
            return None

    def exclusions(node, code):
        if node is None:
            errors.append(code)
            return
        # Every supported directory is excluded recursively. Empty/missing modes
        # enable data by default; an include or unknown domain is not equivalent.
        rules = [(e.tag, e.get('domain'), e.get('path')) for e in node]
        require(len(rules) == len(DOMAINS) and
                set(rules) == {('exclude', domain, '.') for domain in DOMAINS}, code)

    manifest = xml(root / 'android/app/src/main/AndroidManifest.xml')
    app = manifest.find('application') if manifest is not None else None
    if app is None:
        errors.append('APPLICATION_MISSING')
    else:
        require(app.get(ANDROID + 'allowBackup') == 'false', 'ALLOW_BACKUP_ENABLED')
        require(app.get(ANDROID + 'fullBackupContent') == '@xml/backup_rules', 'LEGACY_RULE_CONSUMER')
        require(app.get(ANDROID + 'dataExtractionRules') == '@xml/data_extraction_rules', 'MODERN_RULE_CONSUMER')
        activity = app.find("activity[@%sname='.MainActivity']" % ANDROID)
        require(activity is not None and activity.get(ANDROID + 'theme') == '@style/LaunchTheme',
                'LAUNCH_THEME_CONSUMER')
        if activity is not None:
            normal = activity.find("meta-data[@%sname='io.flutter.embedding.android.NormalTheme']" % ANDROID)
            require(normal is not None and normal.get(ANDROID + 'resource') == '@style/NormalTheme',
                    'NORMAL_THEME_CONSUMER')

    legacy = xml(res / 'xml/backup_rules.xml')
    if legacy is not None:
        require(legacy.tag == 'full-backup-content', 'LEGACY_RULE_FORMAT')
        exclusions(legacy, 'LEGACY_EXCLUSIONS')
    modern = xml(res / 'xml/data_extraction_rules.xml')
    if modern is not None:
        require(modern.tag == 'data-extraction-rules', 'MODERN_RULE_FORMAT')
        require([e.tag for e in modern] == ['cloud-backup', 'device-transfer'], 'MODERN_MODES')
        exclusions(modern.find('cloud-backup'), 'CLOUD_EXCLUSIONS')
        exclusions(modern.find('device-transfer'), 'D2D_EXCLUSIONS')

    colors = xml(res / 'values/colors.xml')
    if colors is not None:
        require({e.get('name'): e.text for e in colors}.get('seguimiento_background') == '#0B0806',
                'BRAND_BACKGROUND')
    for folder in ('drawable', 'drawable-v21'):
        launch = xml(res / folder / 'launch_background.xml')
        if launch is not None:
            items = list(launch)
            require(launch.tag == 'layer-list' and len(items) == 2 and
                    items[0].get(ANDROID + 'drawable') == '@color/seguimiento_background',
                    'LAUNCH_BACKGROUND:' + folder)
            require(len(items) == 2 and items[1].attrib == {
                ANDROID + 'drawable': '@mipmap/ic_launcher_foreground',
                ANDROID + 'width': '108dp', ANDROID + 'height': '108dp', ANDROID + 'gravity': 'center'},
                'LAUNCH_GLYPH:' + folder)

    for folder in ('values', 'values-night', 'values-v31', 'values-night-v31'):
        styles = xml(res / folder / 'styles.xml')
        if styles is None:
            continue
        for name in ('LaunchTheme', 'NormalTheme'):
            style = styles.find("style[@name='%s']" % name)
            values = {} if style is None else {e.get('name'): e.text for e in style}
            expected = '@drawable/launch_background' if name == 'LaunchTheme' else '@color/seguimiento_background'
            require(values.get('android:windowBackground') == expected,
                    'WINDOW_BACKGROUND:' + folder + ':' + name)
            if folder.endswith('v31') and name == 'LaunchTheme':
                require(values.get('android:windowSplashScreenBackground') == '@color/seguimiento_background',
                        'SPLASH_BACKGROUND:' + folder)
                require(values.get('android:windowSplashScreenAnimatedIcon') == '@mipmap/ic_launcher_foreground',
                        'SPLASH_GLYPH:' + folder)
                require('android:windowSplashScreenAnimationDuration' not in values,
                        'NO_ARTIFICIAL_DURATION:' + folder)

    if check_icons:
        previous = icon_verify.ROOT
        try:
            icon_verify.ROOT = root
            icons = icon_verify.verify()
            approved = json.loads((root / 'docs/context/sessions/2026-10-09-013-logo-resources.json').read_text())
            pngs = {p: v['sha256'] for p, v in icons.items() if p.endswith('.png')}
            require(len(pngs) == 30 and all(approved[p]['sha256'] == sha for p, sha in pngs.items()),
                    '013_PNG_CHANGED')
        except (OSError, ValueError, KeyError, ET.ParseError) as error:
            errors.append('013_RESOURCES:' + str(error))
        finally:
            icon_verify.ROOT = previous
    return {'status': 'VALIDATED_SOURCE_POLICY' if not errors else 'INVALID_SOURCE_POLICY',
            'violations': errors, 'sourceSha256': hashes,
            'nativeValidation': 'PENDING_MERGED_XML_APK_STARTUP_AND_TRANSPORT'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt', type=Path, default=ROOT / 'build/016-policy-receipt.json')
    args = parser.parse_args()
    result = verify()
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'VALIDATED_SOURCE_POLICY' else 1


if __name__ == '__main__':
    raise SystemExit(main())
