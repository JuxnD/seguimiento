import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/custom_reminder_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/sleep_repository.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/domain/sleep_entry.dart';

import '../support/sqlite_host.dart';

/// 040 portable: el paquete ZIP real (BackupArchive, esquema 25) conserva la
/// noche completa, el origen de los recordatorios, la comparabilidad de los
/// pesajes, `kneeStairs`, los ids, lo de antes en null, los 14 recordatorios
/// con los tres defaults de 032 exactos y el flag del dispositivo. Se comprueba
/// al restaurar, al reabrir y en una segunda restauración, y un cambio
/// posterior se detecta. Mismo contrato que la revisión del root sobre
/// 44b832e, en un directorio temporal. Datos ficticios (marzo de 2030).
void main() {
  setUpAll(() {
    useHostSqlite();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test('ZIP 25: campos de 040, ids, defaults exactos y flag tras restaurar, reabrir y restaurar otra vez', () async {
    final root = Directory.systemTemp.createTempSync('seguimiento_zip_040_');
    final documents = Directory('${root.path}/documents')..createSync();
    final file = File('${documents.path}/seguimiento.sqlite');
    final flags = File('${documents.path}/flags.json')..writeAsStringSync('{"syntheticDeviceOnly":true}');
    final flagHash = sha256.convert(flags.readAsBytesSync()).toString();
    var host = DatabaseHost(file, (f) => AppDatabase(NativeDatabase(f)));
    const day = '2030-03-04';
    final date = DateTime(2030, 3, 4);

    /// Todas las columnas de las cinco tablas, en orden de rowid.
    Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
      final result = <String, List<Map<String, Object?>>>{};
      for (final table in ['sleep_logs', 'custom_reminders', 'football_games', 'reminders', 'morning_checks']) {
        final columns = await host.db.customSelect('PRAGMA table_info("$table")').get();
        final names = columns.map((r) => '"${r.data['name']}"').join(',');
        final rows = await host.db.customSelect('SELECT $names FROM "$table" ORDER BY rowid').get();
        result[table] = rows.map((r) => Map<String, Object?>.from(r.data)).toList();
      }
      return result;
    }

    Future<void> exactDefaults() async {
      final rows = await host.db.select(host.db.reminders).get();
      expect(rows.length, 14);
      final actual = {
        for (final r in rows.where((r) => [
              ReminderKind.recuperacionManana,
              ReminderKind.rutinaManana,
              ReminderKind.rutinaNoche,
            ].contains(r.kind)))
          r.kind.name: [r.enabled, r.hour, r.minute, r.threshold],
      };
      expect(actual, {
        'recuperacionManana': [true, 22, 0, null],
        'rutinaManana': [true, 7, 15, null],
        'rutinaNoche': [true, 21, 30, null],
      });
    }

    try {
      await host.db.customStatement(
          "UPDATE profiles SET profile_origin='legacyUnknown', setup_state='ready', setup_confirmed_at=NULL");
      await ReminderRepository(host.db).ensureDefaults();
      await exactDefaults();

      final window = sleepWindow(date, (23, 0), (7, 0));
      await SleepRepository(host.db).save(date,
          hours: 8, start: window.start, wake: window.wake, source: sleepSourceEditManual, note: 'synthetic corrected clock');
      await SleepRepository(host.db).save(DateTime(2030, 3, 3), hours: 0, source: sleepSourceManual, note: 'synthetic zero');
      await host.db.customStatement("INSERT INTO sleep_logs(date,hours) VALUES('2030-03-02',7.5)");

      final mine = await CustomReminderRepository(host.db)
          .save(title: 'Synthetic owner reminder', intervalDays: 1, hour: 9, minute: 0, startDate: DateTime(2030, 3, 1));
      await host.db.customStatement('INSERT INTO custom_reminders(title,interval_days,hour,minute,start_date,enabled) '
          "VALUES('Synthetic legacy reminder',1,8,0,'2030-03-01',1)");
      final oldReminder = (await host.db.select(host.db.customReminders).get()).singleWhere((r) => r.id != mine);
      await CustomReminderRepository(host.db).save(
          id: oldReminder.id,
          title: 'Synthetic legacy edited',
          intervalDays: 2,
          hour: 10,
          minute: 15,
          startDate: DateTime(2030, 3, 1));

      for (final (comparable, fluid) in <(bool?, int?)>[(true, 0), (false, 500), (null, null)]) {
        await host.db.into(host.db.footballGames).insert(FootballGamesCompanion.insert(
            date: day,
            minutes: 60,
            weightBeforeKg: const Value(80),
            weightAfterKg: const Value(79),
            fluidMl: Value(fluid),
            weightsComparable: Value(comparable)));
      }
      await host.db
          .into(host.db.morningChecks)
          .insert(MorningChecksCompanion.insert(date: day, kneeStairs: const Value(0)));

      final before = await snapshot();
      final encoded = jsonEncode(before);
      // Las cantidades y valores que el paquete tiene que devolver.
      expect({for (final e in before.entries) e.key: e.value.length},
          {'sleep_logs': 3, 'custom_reminders': 2, 'football_games': 3, 'reminders': 14, 'morning_checks': 1});
      expect([for (final r in before['custom_reminders']!) r['origin']], ['usuario', null],
          reason: 'lo de antes, aunque se edite, no gana un origen inventado');
      expect([for (final r in before['football_games']!) (r['weights_comparable'], r['fluid_ml'])],
          [(1, 0), (0, 500), (null, null)]);
      expect(before['morning_checks']!.single['knee_stairs'], 0);

      final archive = BackupArchive(host: host, documents: documents);
      final export = await archive.exportTo('${root.path}/r040.zip');
      final bytes = export.file.readAsBytesSync();
      expect(bytes.take(4).toList(), [0x50, 0x4b, 0x03, 0x04], reason: 'es un ZIP, no SQLite renombrado');
      final package = ZipDecoder().decodeBytes(bytes);
      final manifest = jsonDecode(utf8.decode(package.findFile(BackupArchive.manifestName)!.content as List<int>))
          as Map<String, dynamic>;
      expect(manifest['schemaVersion'], 26); // plan 052
      expect(package.findFile(BackupArchive.databaseName), isNotNull);

      // Después del respaldo se cambia lo que el paquete debe devolver.
      await SleepRepository(host.db).remove(date);
      await CustomReminderRepository(host.db).delete(mine);
      await host.db.customStatement('UPDATE football_games SET weights_comparable=NULL,fluid_ml=NULL');
      expect(jsonEncode(await snapshot()), isNot(encoded));

      await archive.restoreFrom(export.file);
      expect(jsonEncode(await snapshot()), encoded, reason: 'primera restauración');
      await exactDefaults();
      final detail = (await SleepRepository(host.db).detail(date))!;
      expect((detail.hours, detail.start, detail.wake, detail.source, detail.note),
          (8.0, window.start, window.wake, sleepSourceEditManual, 'synthetic corrected clock'));
      final legacy = (await SleepRepository(host.db).detail(DateTime(2030, 3, 2)))!;
      expect((legacy.hours, legacy.start, legacy.wake, legacy.source, legacy.note), (7.5, null, null, null, null));
      expect((await SleepRepository(host.db).detail(DateTime(2030, 3, 3)))!.hours, 0);

      // Reabrir la base desde el archivo.
      await host.db.close();
      host = DatabaseHost(file, (f) => AppDatabase(NativeDatabase(f)));
      expect(jsonEncode(await snapshot()), encoded, reason: 'tras reabrir');
      expect(sha256.convert(flags.readAsBytesSync()).toString(), flagHash, reason: 'el flag local no viaja ni se pisa');

      // Un cambio posterior en un campo entregado se detecta.
      await host.db.customStatement("UPDATE sleep_logs SET note='MUTANT' WHERE date='$day'");
      expect(jsonEncode(await snapshot()), isNot(encoded), reason: 'el oráculo rechaza un campo cambiado');

      // Segunda restauración del mismo paquete.
      await BackupArchive(host: host, documents: documents).restoreFrom(export.file);
      expect(jsonEncode(await snapshot()), encoded, reason: 'segunda restauración');
      await exactDefaults();
      expect(sha256.convert(flags.readAsBytesSync()).toString(), flagHash);
    } finally {
      await host.db.close();
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // En Windows el archivo puede seguir tomado.
      }
    }
  });
}
