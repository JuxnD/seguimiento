import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/sqlite_host.dart';

const _capsuleSha =
    '91a181cb55d9d33a77f15f737d29641d31f45d0203aec89f037939998ac8f6a6';
const _manifestSha =
    '45903ced50f4991599dc9e0cb3d114410b869e8d659f2156f4c19d836b3a035c';
String _quote(String s) => '"${s.replaceAll('"', '""')}"';

Map<String, int> _multiplicity(Iterable<List<Object?>> rows) {
  final result = <String, int>{};
  for (final row in rows) {
    result.update(jsonEncode(row), (n) => n + 1, ifAbsent: () => 1);
  }
  return result;
}

// Declared destination for this candidate; never read back from the migrated DB.
const _targetSchema = 27; // plan 058
const _restoredReminderRows = [
  ['recuperacionManana', 1, 22, 0, null],
  ['rutinaManana', 1, 7, 15, null],
  ['rutinaNoche', 1, 21, 30, null],
  // Plan 055: la víspera de un test.
  ['visperaTest', 1, 20, 0, null],
];

void main() {
  setUpAll(useHostSqlite);
  test(
      'genuine public20 capsule →25 preserves all legacy rows/columns, files, ZIP and reopen',
      () async {
    final capsule = File('test/fixtures/public20/baseline-offline-public20.zip')
        .readAsBytesSync();
    expect(sha256.convert(capsule).toString(), _capsuleSha);
    final archive = ZipDecoder().decodeBytes(capsule, verify: true);
    final entries = {
      for (final item in archive.files) item.name: item.content as List<int>
    };
    final manifestBytes = entries['manifest.json']!;
    expect(sha256.convert(manifestBytes).toString(), _manifestSha);
    final manifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>;
    expect(manifest['sourceSha'], 'e3141519ffcb6037de3ec2d5018a2fbee6a82d07');
    expect(manifest['syntheticOnly'], true);
    final baseline = manifest['database']! as Map<String, Object?>;
    expect(baseline['schema'], 20);
    final tables = baseline['tables']! as Map<String, Object?>;
    expect(tables, hasLength(32));
    expect(tables.keys, isNot(contains('goal_versions')));
    expect(tables.keys, isNot(contains('catalog_patches')));
    final files =
        (manifest['files']! as Map<String, Object?>).cast<String, String>();
    expect(entries.keys.toSet(),
        {'manifest.json', ...files.keys.map((p) => 'data/$p')});
    for (final item in files.entries) {
      expect(
          sha256.convert(entries['data/${item.key}']!).toString(), item.value,
          reason: item.key);
    }
    final root =
        await Directory.systemTemp.createTemp('seguimiento-public20-24-');
    final documents = Directory('${root.path}/documents')..createSync();
    for (final path in files.keys) {
      final file = File('${documents.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entries['data/$path']!);
    }
    // Synthetic external sentinel. No real license/Keystore is read or changed.
    final external = File('${root.path}/external-credential-sentinel.txt')
      ..writeAsStringSync('FICTICIO-QA-EXTERNAL');
    final externalBytes = external.readAsBytesSync();
    final sqliteFile = File('${documents.path}/seguimiento.sqlite');
    final raw =
        sqlite.sqlite3.open(sqliteFile.path, mode: sqlite.OpenMode.readOnly);
    try {
      expect(raw.select('PRAGMA user_version').single.values.single, 20);
      for (final entry in tables.entries) {
        final table = entry.value! as Map<String, Object?>;
        final columns = (table['columns']! as List<Object?>).cast<String>();
        expect(
            raw
                .select('PRAGMA table_info(${_quote(entry.key)})')
                .map((r) => r.values.toList())
                .toList(),
            table['columnInfo']);
        expect(
            _multiplicity(raw
                .select(
                    'SELECT ${columns.map(_quote).join(',')} FROM ${_quote(entry.key)}')
                .map((r) => columns.map((c) => r[c]).toList())),
            _multiplicity(
                (table['rows']! as List<Object?>).cast<List<Object?>>()));
      }
    } finally {
      raw.dispose();
    }

    Future<void> preserved(AppDatabase db, {bool afterRestore = false}) async {
      expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          _targetSchema);
      for (final entry in tables.entries) {
        final table = entry.value! as Map<String, Object?>;
        final columns = (table['columns']! as List<Object?>).cast<String>();
        final info = (await db
                .customSelect('PRAGMA table_info(${_quote(entry.key)})')
                .get())
            .map((r) => r.data.values.toList())
            .where((r) => columns.contains(r[1]))
            .toList();
        expect(info, table['columnInfo'],
            reason: '${entry.key} all legacy columns');
        final rows = (await db
                .customSelect(
                    'SELECT ${columns.map(_quote).join(',')} FROM ${_quote(entry.key)}')
                .get())
            .map((r) => columns.map((c) => r.data[c]).toList());
        final actual = _multiplicity(rows);
        final expected = _multiplicity([
          ...(table['rows']! as List<Object?>).cast<List<Object?>>(),
          if (afterRestore && entry.key == 'reminders')
            ..._restoredReminderRows,
        ]);
        for (final oldRow in expected.entries) {
          expect(actual[oldRow.key], oldRow.value,
              reason: '${entry.key} legacy row multiplicity');
        }
        // Catalog upgrades may add seed references/templates; all old values
        // and duplicate counts still must survive. Personal tables are exact.
        if (!{'foods', 'meal_templates', 'meal_template_items'}
            .contains(entry.key)) {
          expect(actual, expected, reason: '${entry.key} no new personal rows');
        }
      }
      expect(
          (await db
                  .customSelect(
                      'SELECT profile_origin,setup_state,setup_confirmed_at,handoff_consent_at FROM profiles')
                  .getSingle())
              .data,
          {
            'profile_origin': 'legacyUnknown',
            'setup_state': 'ready',
            'setup_confirmed_at': null,
            'handoff_consent_at': null
          });
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
          (await db.customSelect('PRAGMA integrity_check').getSingle())
              .data
              .values
              .single,
          'ok');
      expect(
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM goal_versions')
                  .getSingle())
              .data['n'],
          12);
    }

    void unchangedDeviceFiles() {
      for (final path in files.keys.where((p) =>
          p.startsWith('fotos/') ||
          p == 'flags.json' ||
          p == 'sesion-en-curso.json')) {
        expect(
            sha256
                .convert(File('${documents.path}/$path').readAsBytesSync())
                .toString(),
            files[path],
            reason: path);
      }
      expect(external.readAsBytesSync(), externalBytes);
      final flags = LocalFlags(File('${documents.path}/flags.json'));
      expect(flags.get<bool>('healthConnectEnabled'), false);
      expect(flags.get<bool>('notificationsAsked'), true);
    }

    AppDatabase? db;
    DatabaseHost? recipient;
    try {
      db = AppDatabase(NativeDatabase(sqliteFile));
      await preserved(db);
      unchangedDeviceFiles();
      await db.close();
      db = AppDatabase(NativeDatabase(sqliteFile));
      await preserved(db);
      final snapshot = await ActiveSessionStore(
              File('${documents.path}/sesion-en-curso.json'))
          .load();
      expect(snapshot, isA<GuidedSnapshot>());
      final guided = snapshot! as GuidedSnapshot;
      expect(guided.phase, GuidedPhase.trabajo);
      expect(guided.restAccumSec, 91);
      expect(guided.done.single.exercise, 'Dominadas QA');
      expect(guided.done.single.reps, 8);
      expect(guided.done.single.loadKg, 4.5);
      expect(guided.done.single.rir, 2);
      unchangedDeviceFiles();
      final host = DatabaseHost(
          sqliteFile, (f) => AppDatabase(NativeDatabase(f)),
          initial: db);
      final exported = await BackupArchive(host: host, documents: documents)
          .exportTo('${root.path}/current24.zip');
      final zipped = ZipDecoder()
          .decodeBytes(exported.file.readAsBytesSync())
          .files
          .map((f) => f.name)
          .toSet();
      expect(
          zipped.any((p) =>
              p.contains('flags') ||
              p.contains('sesion-en-curso') ||
              p.contains('credential')),
          false);
      final recipientDir = Directory('${root.path}/recipient')..createSync();
      recipient = DatabaseHost(File('${recipientDir.path}/seguimiento.sqlite'),
          (f) => AppDatabase(NativeDatabase(f)));
      await BackupArchive(host: recipient, documents: recipientDir)
          .restoreFrom(exported.file);
      await preserved(recipient.db, afterRestore: true);
      await recipient.db.close();
      recipient =
          DatabaseHost(recipient.file, (f) => AppDatabase(NativeDatabase(f)));
      await preserved(recipient.db, afterRestore: true);
      await BackupArchive(host: recipient, documents: recipientDir)
          .restoreFrom(exported.file);
      await preserved(recipient.db, afterRestore: true);
      for (final path in files.keys.where((p) => p.startsWith('fotos/'))) {
        expect(
            sha256
                .convert(File('${recipientDir.path}/$path').readAsBytesSync())
                .toString(),
            files[path]);
      }
      unchangedDeviceFiles();
    } finally {
      await db?.close();
      await recipient?.db.close();
      // All files here were created by this test under its createTemp result.
      await root.delete(recursive: true);
    }
  });
}
