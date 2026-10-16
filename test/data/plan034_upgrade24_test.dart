import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  final fixture = Directory('test/fixtures/schema24_034_ready');
  setUp(() {
    expect(sha256.convert(File('${fixture.path}/manifest24.json').readAsBytesSync()).toString(),
      '8279216d74527852dce64a317f088fb176bffe262aff2806b735f56fe223a747');
  });
  Future<bool> legacyPreserved(AppDatabase db, Map<String, dynamic> manifest) async {
    for (final entry in (manifest['tables'] as Map<String, dynamic>).entries) {
      final specification = (entry.value as Map).cast<String, Object?>();
      final columns = (specification['columns'] as List).cast<String>();
      final select = columns.map((c) => '"$c"').join(',');
      var actual = (await db.customSelect('SELECT $select FROM "${entry.key}" ORDER BY rowid').get())
        .map((r) => [for (final c in columns) r.data[c]]).toList();
      // Plan 055: un tipo nuevo de recordatorio (la víspera de un test) se
      // agrega al final; lo de antes se conserva igual.
      if (entry.key == 'reminders') {
        actual = actual.take((specification['rows'] as List).length).toList();
      }
      if (jsonEncode(actual) != jsonEncode(specification['rows'])) return false;
    }
    return true;
  }
  Future<void> assert25(AppDatabase db, Map<String, dynamic> manifest) async {
    // Plan 052: el destino es 26; lo de 25 y 26 llega vacío o en null.
    expect(db.schemaVersion, 27); // plan 058
    expect((await db.customSelect('PRAGMA user_version').getSingle()).data.values.single, 27);
    expect((await db.select(db.footballGames).get()).every((r) => r.startTime == null), isTrue);
    expect((await db.select(db.fitnessTests).get()).every((r) => r.limitedBy == null), isTrue);
    for (final t in ['fitness_test_pending', 'equipment_items', 'supplements', 'supplement_logs']) {
      expect((await db.customSelect('SELECT count(*) AS n FROM $t').getSingle()).read<int>('n'), 0, reason: t);
    }
    expect(await legacyPreserved(db, manifest), isTrue);
    expect((await db.select(db.morningChecks).get()).every((r) => r.kneeStairs == null), isTrue);
    expect((await db.select(db.sleepLogs).get()).every((r) => r.sleepStart == null && r.wakeAt == null && r.source == null && r.note == null), isTrue);
    expect((await db.select(db.footballGames).get()).every((r) => r.weightsComparable == null), isTrue);
    expect((await db.select(db.customReminders).get()).every((r) => r.origin == null), isTrue);
    expect((await db.select(db.planExercises).get()).every((r) => r.purpose == null && r.physicalVariantKey == null), isTrue);
    expect((await db.select(db.fitnessTests).get()).every((r) => r.attemptId == null && r.conditions == null && r.baselineKey == null), isTrue);
    expect(await db.select(db.fitnessTestAttempts).get(), isEmpty);
    expect(await db.select(db.mobilityBenchmarks).get(), isEmpty);
  }
  test('genuine24→25 upgrade preserves every original column and row; negative mutation is detected', () async {
    final manifest = jsonDecode(File('${fixture.path}/manifest24.json').readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['source'], 'c47a94af149dd8b6fcaf6860ccd73c6e6b0233ec');
    expect(sha256.convert(File('${fixture.path}/documents/seguimiento.sqlite').readAsBytesSync()).toString(), manifest['databaseSha256']);
    final directory = Directory.systemTemp.createTempSync('my-prime-034-upgrade-');
    final file = File('${directory.path}/seguimiento.sqlite');
    await File('${fixture.path}/documents/seguimiento.sqlite').copy(file.path);
    var db = AppDatabase(NativeDatabase(file));
    try {
      await assert25(db, manifest);
      await db.close(); db = AppDatabase(NativeDatabase(file));
      await assert25(db, manifest);
      await db.customStatement("UPDATE custom_reminders SET title='Mutante' WHERE id=801");
      expect(await legacyPreserved(db, manifest), false, reason: 'The preservation oracle rejects changed original data');
    } finally {await db.close(); await directory.delete(recursive: true);}
  });
  test('genuineZIP24→25→reopen→second restore preserves original data and local device flags', () async {
    final manifest = jsonDecode(File('${fixture.path}/manifest24.json').readAsStringSync()) as Map<String, dynamic>;
    final zip = File('${fixture.path}/capsule24.zip');
    expect(sha256.convert(zip.readAsBytesSync()).toString(), manifest['zipSha256']);
    final directory = Directory.systemTemp.createTempSync('my-prime-034-zip-');
    final file = File('${directory.path}/seguimiento.sqlite');
    final flags = File('${directory.path}/flags.json')..writeAsStringSync('{"syntheticDevice":true}');
    final hash = sha256.convert(flags.readAsBytesSync()).toString();
    var host = DatabaseHost(file, (f) => AppDatabase(NativeDatabase(f)));
    try {
      await BackupArchive(host: host, documents: directory).restoreFrom(zip);
      await assert25(host.db, manifest);
      await host.db.close(); host = DatabaseHost(file, (f) => AppDatabase(NativeDatabase(f)));
      await assert25(host.db, manifest);
      await BackupArchive(host: host, documents: directory).restoreFrom(zip);
      await assert25(host.db, manifest);
      expect(sha256.convert(flags.readAsBytesSync()).toString(), hash);
    } finally {await host.db.close(); await directory.delete(recursive: true);}
  });
}
