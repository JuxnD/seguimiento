import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/domain/active_session.dart';

/// Plan 027, ronda 2. La operación crítica alrededor de una restauración no
/// puede absorber un fallo de escritura (el `save` ordinario sí es tolerante).
void main() {
  late Directory dir;
  late File file;
  late ActiveSessionStore store;
  final started = DateTime(2026, 10, 12, 9);

  GuidedSnapshot session({int planDayId = 7, DateTime? at, int index = 0, List<int> marks = const []}) => GuidedSnapshot(
        date: '2026-10-12',
        startedAt: at ?? started,
        planDayId: planDayId,
        phase: GuidedPhase.trabajo,
        index: index,
        roundMarks: marks,
        note: 'nota',
        done: const [DoneStep('Dominadas', 6, false, loadKg: 5)],
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_027_store_');
    file = File(p.join(dir.path, 'sesion.json'));
    store = ActiveSessionStore(file);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, Object?> disk() => jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

  test('tmp bloqueado: lanza, la restauración NO corre y el archivo queda byte a byte', () async {
    await store.save(session());
    final original = file.readAsBytesSync();
    Directory('${file.path}.tmp').createSync();
    var ran = false;
    await expectLater(store.protectedRestore(() async => ran = true), throwsA(isA<SessionProtectionException>()));
    expect(ran, isFalse);
    expect(file.readAsBytesSync(), original);
    expect(disk()['planDayId'], 7);
  });

  test('éxito: desvincula antes de restaurar y conserva los demás campos', () async {
    await store.save(session(index: 4, marks: const [180]));
    int? duringRestore;
    await store.protectedRestore(() async => duringRestore = disk()['planDayId'] as int);
    expect(duringRestore, -1, reason: 'ya persistido cuando la base se reemplaza');
    final now = disk();
    expect(jsonEncode([now['index'], now['roundMarks'], now['done']]),
        jsonEncode([4, [180], [{'e': 'Dominadas', 'r': 6, 'round': false, 'kg': 5.0}]]));
    expect(now['note'], 'nota. $recoveredPlanNote');
  });

  test('restauración fallida: devuelve el archivo original byte a byte y propaga el error', () async {
    await store.save(session());
    final original = file.readAsBytesSync();
    await expectLater(store.protectedRestore<void>(() async => throw StateError('rollback')), throwsStateError);
    expect(file.readAsBytesSync(), original);
  });

  test('restauración fallida y recuperación imposible: error claro', () async {
    await store.save(session());
    await expectLater(
        store.protectedRestore<void>(() async {
          Directory('${file.path}.tmp').createSync();
          throw StateError('rollback');
        }),
        throwsA(isA<SessionRecoveryException>()));
    expect(disk()['planDayId'], -1, reason: 'sigue desvinculado: nunca con el id viejo si no se pudo devolver el original');
  });

  test('guardado pendiente antes de proteger: se toma lo más reciente', () async {
    await store.save(session(index: 1));
    final pending = store.save(session(index: 9, marks: const [60, 125])); // sin await
    await store.protectedRestore(() async {});
    await pending;
    final now = disk();
    expect(jsonEncode([now['index'], now['roundMarks'], now['planDayId']]), jsonEncode([9, [60, 125], -1]));
  });

  test('callback viejo tras el éxito no repone el id; una sesión nueva conserva su vínculo', () async {
    await store.save(session());
    await store.protectedRestore(() async {});
    await store.save(session(index: 5)); // pantalla vieja, misma sesión
    expect((disk()['planDayId'], disk()['index']), (-1, 5));
    await store.save(session(at: started.add(const Duration(hours: 3)), planDayId: 7));
    expect(disk()['planDayId'], 7);
  });

  test('guardado ordinario sigue siendo tolerante', () async {
    Directory('${file.path}.tmp').createSync();
    await store.save(session()); // no lanza
    expect(file.existsSync(), isFalse);
  });

  test('sin sesión guiada vinculada no hay nada que escribir y la restauración corre', () async {
    var ran = false;
    await store.protectedRestore(() async => ran = true);
    expect(ran, isTrue);
    expect(file.existsSync(), isFalse);
  });
}
