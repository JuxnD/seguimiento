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

  test('escrituras simultáneas conservan todas las claves al reabrir',
      () async {
    await flags.set('previa', 7);
    final other = LocalFlags(File(flags.file.absolute.path));
    await Future.wait([
      flags.set('asked', true),
      other.set('when', DateTime(2026, 10, 12)),
      flags.set('origin', 'reloj ficticio'),
    ]);
    final again = LocalFlags(flags.file);
    expect(again.get<int>('previa'), 7);
    expect(again.get<bool>('asked'), isTrue);
    expect(again.getDate('when'), DateTime(2026, 10, 12));
    expect(again.get<String>('origin'), 'reloj ficticio');
  });

  test('un fallo se propaga y no impide la siguiente escritura', () async {
    await flags.set('previa', 7);
    final blocked = Directory('${flags.file.path}.tmp')..createSync();
    await expectLater(
        flags.set('failed', true), throwsA(isA<FileSystemException>()));
    blocked.deleteSync();
    await flags.set('recovered', true);
    final again = LocalFlags(flags.file);
    expect(again.get<int>('previa'), 7);
    expect(again.get<bool>('failed'), isNull);
    expect(again.get<bool>('recovered'), isTrue);
  });
}
