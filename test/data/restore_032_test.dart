import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';
import '../support/derived_historical_037.dart';

/// Respaldo y restauración con el esquema 24 (plan 032): un respaldo 23 real
/// migra al abrir y los avisos nuevos se completan; uno con un tipo de aviso
/// que esta versión no conoce se rechaza sin tocar la base actual.
void main() {
  setUpAll(useHostSqlite);

  late Directory dir;
  late DatabaseHost host;
  final day = DateTime(2030, 3, 4);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('seguimiento_restore_032');
    host = DatabaseHost(File('${dir.path}/seguimiento.sqlite'),
        (f) => AppDatabase(NativeDatabase(f)));
    await asExistingUser(host.db, goals: false);
    await ReminderRepository(host.db).ensureDefaults();
  });

  tearDown(() async {
    await host.db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows el archivo puede seguir tomado.
    }
  });

  test('un respaldo 24 conserva dolor, enfermo y los avisos nuevos', () async {
    await RecoveryRepository(host.db).setRestingHr(day, 58);
    await RecoveryRepository(host.db)
        .setReadinessAnswers(day, muscleSoreness: 6, ill: false);
    await ReminderRepository(host.db)
        .save(ReminderKind.rutinaNoche, hour: 22, minute: 15);
    final backup = await host.exportTo('${dir.path}/v24.sqlite');
    await RecoveryRepository(host.db)
        .setReadinessAnswers(day, muscleSoreness: 1, ill: true);

    await host.restoreFrom(backup);

    final row = await RecoveryRepository(host.db).morningOn(day);
    expect((row!.restingHr, row.muscleSoreness, row.ill), (58, 6, false));
    final settings = await ReminderRepository(host.db).settings();
    expect(settings[ReminderKind.rutinaNoche]!.timeLabel, '22:15');
    expect(settings.keys.toSet(),
        ReminderKind.values.toSet()..remove(ReminderKind.personalizado));
  });

  test(
      'un respaldo derivado de esquema histórico23 se restaura, migra al 25 y completa los avisos nuevos',
      () async {
    final backup = File('${dir.path}/derived23.sqlite');
    copyHistorical037(23, backup);
    await BodyRepository(host.db).addWeight(DateTime(2030, 3, 5), 80.1);

    await host.restoreFrom(backup);

    expect(
        (await host.db.customSelect('pragma user_version').getSingle())
            .data
            .values
            .single,
        27);
    final row = await RecoveryRepository(host.db).morningOn(day);
    expect((
      row!.restingHr,
      row.feeling,
      row.muscleSoreness,
      row.ill
    ), (
      57,
      2,
      null,
      null
    ), reason: 'lo anterior queda sin responder, no "sin dolor"');
    expect(
        await BodyRepository(host.db).weightsOn(DateTime(2030, 3, 5)), isEmpty,
        reason: 'lo posterior al respaldo se descarta');
    final kinds = (await ReminderRepository(host.db).settings()).keys.toSet();
    expect(
        kinds,
        containsAll([
          ReminderKind.recuperacionManana,
          ReminderKind.rutinaManana,
          ReminderKind.rutinaNoche
        ]));
  });

  test('un tipo de aviso desconocido se rechaza y conserva la base actual',
      () async {
    await BodyRepository(host.db).addWeight(DateTime(2030, 3, 1), 81.0);
    final backup = await host.exportTo('${dir.path}/futuro.sqlite');
    final raw = sqlite.sqlite3.open(backup.path);
    raw.execute(
        "insert into reminders (kind, enabled, minute) values ('avisoDelFuturo', 1, 0)");
    raw.dispose();
    await BodyRepository(host.db).addWeight(DateTime(2030, 3, 2), 80.8);

    await expectLater(
        host.restoreFrom(backup), throwsA(isA<RestoreException>()));

    final weights = await BodyRepository(host.db).watchWeights().first;
    expect(weights.map((w) => w.kg).toSet(), {81.0, 80.8},
        reason: 'nada se perdió ni se mezcló');
    expect((await ReminderRepository(host.db).settings()).keys,
        isNot(contains(null)));
    expect(File('${host.file.path}.pre-restore').existsSync(), isFalse);
  });
}
