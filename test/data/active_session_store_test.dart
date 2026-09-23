import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/domain/active_session.dart';

void main() {
  late Directory dir;
  late ActiveSessionStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_activa');
    store = ActiveSessionStore(File('${dir.path}/sesion.json'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  CounterSnapshot snap(int rounds) => CounterSnapshot(
        date: '2026-09-23',
        startedAt: DateTime(2026, 9, 23, 7),
        phase: CounterPhase.circuit,
        marks: [for (var i = 1; i <= rounds; i++) i * 150],
      );

  test('sin archivo no hay sesión', () async {
    expect(await store.load(), isNull);
  });

  test('muchas escrituras seguidas: queda la última', () async {
    for (var i = 1; i <= 20; i++) {
      // Sin await a propósito: así llegan desde el cronómetro.
      store.save(snap(i)).ignore();
    }
    await store.save(snap(21));
    final loaded = await ActiveSessionStore(store.file).load() as CounterSnapshot;
    expect(loaded.marks.length, 21);
  });

  test('clear después de save no deja nada', () async {
    store.save(snap(3)).ignore();
    await store.clear();
    expect(await store.load(), isNull);
    expect(store.file.existsSync(), isFalse);
  });

  test('un archivo dañado se ignora', () async {
    store.file.writeAsStringSync('{"kind": "guided", "roto"');
    expect(await store.load(), isNull);
  });
}
