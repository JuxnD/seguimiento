import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/domain/active_session.dart';

void main() {
  late Directory dir;
  late ActiveSessionStore store;
  GuidedSnapshot original({int minute = 0, int index = 0}) => GuidedSnapshot(
    date: '2026-10-12', startedAt: DateTime(2026, 10, 12, 12, minute),
    planDayId: 7, phase: GuidedPhase.trabajo, index: index,
  );
  setUp(() {
    dir = Directory.systemTemp.createTempSync('review027_queue_');
    store = ActiveSessionStore(File('${dir.path}/session.json'));
  });
  tearDown(() {
    if (!p.isWithin(Directory.systemTemp.absolute.path, dir.absolute.path) ||
        !p.basename(dir.path).startsWith('review027_queue_')) {
      throw StateError('Temporal de revisión fuera de alcance');
    }
    dir.deleteSync(recursive: true);
  });
  test('save inmediato al encolar restore no reintroduce ID ni pierde campos', () async {
    await store.save(original());
    final entered = Completer<void>();
    final finish = Completer<void>();
    final restoring = store.protectedRestore(() async {
      entered.complete();
      await finish.future;
    });
    final saving = store.save(original(index: 27));
    await entered.future;
    finish.complete();
    await Future.wait([restoring, saving]);
    final loaded = await store.load() as GuidedSnapshot;
    expect(loaded.planDayId, -1);
    expect(loaded.index, 27);
  });
  test('segunda restore fallida conserva protección de restore previa', () async {
    await store.save(original());
    await store.protectedRestore(() async {});
    await expectLater(store.protectedRestore<void>(() async {
      throw StateError('fallo de segunda restauración');
    }), throwsA(isA<StateError>()));
    await store.save(original(index: 28));
    final loaded = await store.load() as GuidedSnapshot;
    expect(loaded.planDayId, -1);
    expect(loaded.index, 28);
  });
  test('callback retirado no sobrescribe sesión nueva tras clear', () async {
    await store.save(original());
    await store.protectedRestore(() async {});
    await store.clear();
    await store.save(original(minute: 1, index: 30));
    await store.save(original(index: 29));
    final loaded = await store.load() as GuidedSnapshot;
    expect(loaded.startedAt, DateTime(2026, 10, 12, 12, 1));
    expect(loaded.planDayId, 7);
    expect(loaded.index, 30);
  });
  test('restauración retiene la cola completa hasta terminar callback', () async {
    await store.save(original());
    final entered = Completer<void>();
    final finish = Completer<void>();
    final restoring = store.protectedRestore(() async {
      entered.complete();
      await finish.future;
    });
    await entered.future;
    var completed = false;
    final saving = store.save(original(index: 40)).then((_) => completed = true);
    // Lectura filesystem real drena tareas I/O: no sólo chequear un Future.
    final during = await store.load() as GuidedSnapshot;
    expect(during.planDayId, -1);
    expect(during.index, 0);
    expect(completed, isFalse);
    finish.complete();
    await Future.wait([restoring, saving]);
    final after = await store.load() as GuidedSnapshot;
    expect((after.planDayId, after.index), (-1, 40));
  });
  test('lectura crítica I/O fallida no reemplaza DB y la cola se recupera', () async {
    Directory(store.file.path).createSync();
    var ran = false;
    await expectLater(store.protectedRestore(() async => ran = true),
        throwsA(isA<SessionProtectionException>()));
    expect(ran, isFalse);
    expect(Directory(store.file.path).existsSync(), isTrue);
    Directory(store.file.path).deleteSync();
    await store.save(original(index: 41));
    await store.protectedRestore(() async => ran = true);
    expect(ran, isTrue);
    expect((await store.load() as GuidedSnapshot).index, 41);
  });
  test('archivo no interpretable bloquea restore y conserva bytes', () async {
    const bytes = [123, 110, 111, 32, 106, 115, 111, 110];
    store.file.writeAsBytesSync(bytes);
    expect(await store.load(), isNull, reason: 'lectura ordinaria sigue tolerante');
    var ran = false;
    await expectLater(store.protectedRestore(() async => ran = true),
        throwsA(isA<SessionProtectionException>()));
    expect(ran, isFalse);
    expect(store.file.readAsBytesSync(), bytes);
  });
  test('clear sin restauración permite guardar la misma sesión ordinaria', () async {
    await store.save(original());
    await store.clear();
    await store.save(original(index: 42));
    final after = await store.load() as GuidedSnapshot;
    expect((after.planDayId, after.index), (7, 42));
  });
}
