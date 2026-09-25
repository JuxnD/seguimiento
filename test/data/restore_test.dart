import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/domain/reminders.dart';

import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);

  late Directory dir;
  late DatabaseHost host;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_restore');
    host = DatabaseHost(File('${dir.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
  });

  tearDown(() async {
    await host.db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows el archivo puede seguir tomado; no importa para la prueba.
    }
  });

  Future<File> exportBackup(String name) => host.exportTo('${dir.path}/$name');

  test('restaurar devuelve los datos del respaldo y descarta los posteriores', () async {
    await BodyRepository(host.db).addWeight(DateTime(2026, 9, 18), 71.4);
    final backup = await exportBackup('respaldo.sqlite');

    // Después del respaldo se registra otra cosa que debe desaparecer.
    await BodyRepository(host.db).addWeight(DateTime(2026, 9, 20), 70.9);
    expect((await BodyRepository(host.db).watchWeights().first).length, 2);

    await host.restoreFrom(backup);

    final weights = await BodyRepository(host.db).watchWeights().first;
    expect(weights.map((w) => w.kg), [71.4]);
    expect(File('${host.file.path}.pre-restore').existsSync(), isFalse);
  });

  test('un respaldo sin recordatorios queda con los de por defecto', () async {
    await host.db.delete(host.db.reminders).go();
    final backup = await exportBackup('sin-avisos.sqlite');

    await host.restoreFrom(backup);

    final kinds = (await host.db.select(host.db.reminders).get()).map((r) => r.kind).toSet();
    expect(kinds, ReminderKind.values.toSet());
  });

  test('el perfil restaurado es el del respaldo, no el actual', () async {
    final profile = ProfileRepository(host.db);
    await profile.saveWeekNote(4, 'nota original');
    final backup = await exportBackup('perfil.sqlite');

    await profile.saveWeekNote(4, 'nota posterior');
    await host.restoreFrom(backup);

    expect(await ProfileRepository(host.db).watchWeekNote(4).first, 'nota original');
  });

  test('un archivo que no es un respaldo se rechaza y no toca la base', () async {
    await BodyRepository(host.db).addWeight(DateTime(2026, 9, 18), 71.4);
    final basura = File('${dir.path}/basura.sqlite')..writeAsStringSync('esto no es sqlite' * 100);

    await expectLater(host.restoreFrom(basura), throwsA(isA<RestoreException>()));

    final weights = await BodyRepository(host.db).watchWeights().first;
    expect(weights.map((w) => w.kg), [71.4], reason: 'la base debe quedar intacta');
  });

  test('una base sqlite ajena se rechaza por no tener las tablas', () async {
    final otra = File('${dir.path}/otra.sqlite');
    final ajena = AppDatabase(NativeDatabase(otra));
    await ajena.customStatement('create table cosas (id integer primary key)');
    await ajena.close();
    // Se borra el esquema de Seguimiento para simular una base de otra app.
    final vacia = File('${dir.path}/ajena.sqlite');
    final raw = AppDatabase(NativeDatabase(vacia));
    await raw.customStatement('drop table if exists profiles');
    await raw.close();

    await expectLater(host.restoreFrom(vacia), throwsA(isA<RestoreException>()));
  });

  test('si la base restaurada no abre, vuelve la anterior con todo lo registrado', () async {
    await BodyRepository(host.db).addWeight(DateTime(2026, 9, 18), 71.4);
    final backup = await exportBackup('respaldo.sqlite');
    await BodyRepository(host.db).addWeight(DateTime(2026, 9, 20), 70.9);

    // La primera reapertura (la del respaldo) falla; la del rollback no.
    var fail = true;
    final failing = DatabaseHost(host.file, (f) {
      if (fail) {
        fail = false;
        throw StateError('no abre');
      }
      return AppDatabase(NativeDatabase(f));
    }, initial: host.db);

    await expectLater(failing.restoreFrom(backup), throwsA(isA<RestoreException>()));

    final weights = await BodyRepository(failing.db).watchWeights().first;
    expect(weights.map((w) => w.kg), [70.9, 71.4]);
    expect(File('${host.file.path}.pre-restore').existsSync(), isFalse);
    host = failing;
  });

  test('un archivo inexistente se rechaza con mensaje claro', () async {
    await expectLater(
      host.restoreFrom(File('${dir.path}/no-existe.sqlite')),
      throwsA(predicate((e) => e is RestoreException && e.message.contains('no existe'))),
    );
  });
}
