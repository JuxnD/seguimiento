import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fuentes versionadas: misma métrica de texto en Windows y en CI Linux.
/// Si falta un fixture, la prueba falla; no usa Ahem ni fuentes del SDK.
Future<void> loadTestFonts(WidgetTester tester) async {
  const fonts = 'test/fixtures/fonts';
  const families = {
    'Roboto': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'],
    'FlutterTest': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'],
    'MaterialIcons': ['materialicons-regular.otf'],
  };
  final bytes = {
    for (final file in families.values.expand((files) => files).toSet())
      file: ByteData.sublistView(File('$fonts/$file').readAsBytesSync()),
  };
  await tester.runAsync(() async {
    for (final family in families.entries) {
      final loader = FontLoader(family.key);
      for (final file in family.value) {
        loader.addFont(Future.value(bytes[file]!));
      }
      await loader.load();
    }
  });
}
