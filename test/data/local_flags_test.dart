import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/local_flags.dart';

void main() {
  late Directory dir;
  late LocalFlags flags;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_flags');
    flags = LocalFlags(File('${dir.path}/sub/flags.json'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('sin archivo, todo es null', () {
    expect(flags.get<bool>('x'), isNull);
    expect(flags.getDate('y'), isNull);
  });

  test('guarda y lee valores y fechas', () async {
    await flags.set('asked', true);
    await flags.set('when', DateTime(2026, 9, 23, 8, 30));
    final again = LocalFlags(flags.file);
    expect(again.get<bool>('asked'), isTrue);
    expect(again.getDate('when'), DateTime(2026, 9, 23, 8, 30));
  });

  test('un tipo distinto al pedido devuelve null, no revienta', () async {
    await flags.set('asked', 'sí');
    expect(flags.get<bool>('asked'), isNull);
  });

  test('un archivo dañado se trata como vacío', () async {
    flags.file.parent.createSync(recursive: true);
    flags.file.writeAsStringSync('{no es json');
    expect(flags.get<bool>('asked'), isNull);
    await flags.set('asked', true);
    expect(flags.get<bool>('asked'), isTrue);
  });
}
