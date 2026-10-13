import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/custom_reminder_repository.dart';
import 'package:seguimiento/data/repositories/sleep_repository.dart';
import 'package:seguimiento/domain/sleep_entry.dart';

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 040: un respaldo 25 conserva la noche completa, el origen de los
/// recordatorios y si los pesajes del partido eran comparables; lo de antes
/// vuelve en null, sin inventar nada.
void main() {
  setUpAll(useHostSqlite);

  late Directory dir;
  late DatabaseHost host;
  final mon = DateTime(2030, 3, 4);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('seguimiento_restore_040');
    host = DatabaseHost(File('${dir.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
    await asExistingUser(host.db, goals: false);
  });

  tearDown(() async {
    await host.db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows el archivo puede seguir tomado.
    }
  });

  test('campos nuevos y nulls de antes vuelven tal cual', () async {
    final db = host.db;
    final w = sleepWindow(mon, (23, 38), (11, 0));
    await SleepRepository(db)
        .save(mon, hours: hoursBetween(w.start, w.wake)!, start: w.start, wake: w.wake, source: sleepSourceEditManual, note: 'reloj descargado');
    await db.customStatement("insert into sleep_logs (date, hours) values ('2030-03-03', 7)");
    final mine = await CustomReminderRepository(db)
        .save(title: 'Estirar', intervalDays: 1, hour: 9, minute: 0, startDate: DateTime(2030, 3, 1));
    await db.customStatement('insert into custom_reminders (title, interval_days, hour, minute, start_date, enabled) '
        "values ('De antes', 1, 8, 0, '2030-03-01', 1)");
    for (final (minutes, comparable) in [(90, true), (60, false), (45, null)]) {
      await db.into(db.footballGames).insert(FootballGamesCompanion.insert(
          date: '2030-03-02',
          minutes: minutes,
          weightBeforeKg: const Value(80),
          weightAfterKg: const Value(79),
          fluidMl: const Value(500),
          weightsComparable: Value(comparable)));
    }
    final backup = await host.exportTo('${dir.path}/r040.sqlite');
    // Lo posterior al respaldo desaparece.
    await SleepRepository(db).remove(mon);
    await CustomReminderRepository(db).delete(mine);

    await host.restoreFrom(backup);

    final sleep = (await SleepRepository(host.db).detail(mon))!;
    expect((sleep.start, sleep.wake, sleep.source, sleep.note), (w.start, w.wake, sleepSourceEditManual, 'reloj descargado'));
    final old = (await SleepRepository(host.db).detail(DateTime(2030, 3, 3)))!;
    expect((old.hours, old.start, old.source), (7.0, null, null));
    final reminders = await CustomReminderRepository(host.db).all();
    expect({for (final r in reminders) r.title: r.origin}, {'Estirar': 'usuario', 'De antes': null});
    final games = await (host.db.select(host.db.footballGames)).get();
    expect({for (final g in games) g.minutes: g.weightsComparable}, {90: true, 60: false, 45: null});
  });
}
