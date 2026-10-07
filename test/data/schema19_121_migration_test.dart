import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';

import '../support/sqlite_host.dart';

const _fixture19Sha =
    '45cea7fcdb225e0d24671335d6932b0def99cf80a4e11bf66752e81965830d46';

void main() {
  setUpAll(() {
    useHostSqlite();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  final fixture = File('test/fixtures/schema19-synthetic.sqlite');
  final manifest = jsonDecode(
      File('test/fixtures/schema19-synthetic-manifest.json')
          .readAsStringSync()) as Map<String, dynamic>;

  Map<String, List<Map<String, Object?>>> normalizedLegacyRows() {
    final raw = sqlite3.open(fixture.path, mode: OpenMode.readOnly);
    try {
      final result = {
        for (final name in (manifest['table_inventory'] as List).cast<String>())
          name: raw
              .select('SELECT * FROM "$name" ORDER BY rowid')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
      };
      // Exactly one permitted difference: the legacy test's screen wall clock.
      // Every other original field, including regular-session times, is exact.
      final clock = result['sessions']!.singleWhere((row) => row['id'] == 903);
      expect(clock['mode'], 'test');
      expect(clock['total_sec'], 3600);
      clock['total_sec'] = 0;
      return result;
    } finally {
      raw.dispose();
    }
  }

  Future<void> verify(
      AppDatabase db, Map<String, List<Map<String, Object?>>> expected) async {
    for (final entry in expected.entries) {
      // Includes empty tables: get their original columns from frozen SQLite.
      final raw = sqlite3.open(fixture.path, mode: OpenMode.readOnly);
      late final String columns;
      try {
        columns = raw
            .select('PRAGMA table_info("${entry.key}")')
            .map((row) => '"${row['name']}"')
            .join(',');
      } finally {
        raw.dispose();
      }
      final actual = await db
          .customSelect('SELECT $columns FROM "${entry.key}" ORDER BY rowid')
          .get();
      if (jsonEncode(actual.map((row) => row.data).toList()) !=
          jsonEncode(entry.value)) {
        throw StateError('Preservation mismatch: ${entry.key}');
      }
    }
    final tests = await FitnessTestRepository(db).all();
    expect(tests, hasLength(3));
    expect(tests.singleWhere((r) => r.item == 'wall_handstand').clean, false);
    expect(tests.singleWhere((r) => r.item == 'one_arm_pushup').side, 'I');
    expect((await db.customSelect('PRAGMA foreign_key_check').get()), isEmpty);
    expect(
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .data
            .values
            .single,
        'ok');
  }

  test('genuine19 fixture freezes test, ladder, imports and wallclock', () {
    expect(sha256.convert(fixture.readAsBytesSync()).toString(), _fixture19Sha);
    expect(manifest['fixture_sha256'], _fixture19Sha);
    expect(
        manifest['source_commit'], 'afaaf86e1718d49acaa86e13a08515c7ea699421');
    expect(manifest['synthetic_only'], true);
    expect(manifest['sole_allowed_change'], {
      'table': 'sessions',
      'id': 903,
      'column': 'total_sec',
      'before': 3600,
      'after': 0,
    });
    final raw = sqlite3.open(fixture.path, mode: OpenMode.readOnly);
    try {
      expect(raw.select('PRAGMA user_version').single.values.single, 19);
      final expected = manifest['expected'] as Map<String, dynamic>;
      for (final entry in expected.entries) {
        final wanted = (entry.value as List).cast<Map<String, dynamic>>();
        final order = entry.key == 'ladder_states' ? 'ladder' : 'id';
        final rows = raw.select('SELECT * FROM "${entry.key}" ORDER BY $order');
        expect(rows, hasLength(wanted.length));
        for (var i = 0; i < rows.length; i++) {
          for (final field in wanted[i].entries) {
            expect(rows[i][field.key], field.value,
                reason: '${entry.key} $i ${field.key}');
          }
        }
      }
    } finally {
      raw.dispose();
    }
  });

  test(
      '19 to current normalizes only test clock and preserves original columns through ZIP',
      () async {
    final expected = normalizedLegacyRows();
    final root = Directory.systemTemp.createTempSync('seguimiento_121_from19_');
    final dirA = Directory('${root.path}/A')..createSync();
    final dirB = Directory('${root.path}/B')..createSync();
    final fileA = fixture.copySync('${dirA.path}/seguimiento.sqlite');
    final fileB = File('${dirB.path}/seguimiento.sqlite');
    DatabaseHost open(File file) =>
        DatabaseHost(file, (f) => AppDatabase(NativeDatabase(f)));
    var a = open(fileA);
    var b = open(fileB);
    try {
      await verify(a.db, expected);
      expect(
          (await a.db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          a.db.schemaVersion);
      await a.db.close();
      a = open(fileA);
      await verify(a.db, expected);
      final exported = await BackupArchive(host: a, documents: dirA)
          .exportTo('${root.path}/from19.zip');
      expect(exported.complete, true);
      await BackupArchive(host: b, documents: dirB).restoreFrom(exported.file);
      await verify(b.db, expected);
      await b.db.close();
      b = open(fileB);
      await verify(b.db, expected);

      // A loss in a new legacy table must be caught after successful restore.
      await b.db.customStatement('DELETE FROM fitness_tests WHERE id=3');
      await expectLater(
          verify(b.db, expected),
          throwsA(isA<StateError>().having((e) => e.message, 'exact table',
              'Preservation mismatch: fitness_tests')));
    } finally {
      await a.db.close();
      await b.db.close();
      root.deleteSync(recursive: true);
    }
  });

  test(
      'normalizing the clock cannot erase regular training time or ladder dates',
      () async {
    final expected = normalizedLegacyRows();
    final root =
        Directory.systemTemp.createTempSync('seguimiento_121_from19_mutants_');
    try {
      for (final mutation in ['regular_time', 'ladder_date']) {
        final file = fixture.copySync('${root.path}/$mutation.sqlite');
        final db = AppDatabase(NativeDatabase(file));
        try {
          await verify(db, expected);
          if (mutation == 'regular_time') {
            await db.customStatement(
                'UPDATE sessions SET total_sec=0 WHERE id=902');
          } else {
            await db.customStatement(
                "UPDATE ladder_states SET since='2026-10-01' WHERE ladder='dragon_flag'");
          }
          final table =
              mutation == 'regular_time' ? 'sessions' : 'ladder_states';
          await expectLater(
              verify(db, expected),
              throwsA(isA<StateError>().having((e) => e.message, 'exact table',
                  'Preservation mismatch: $table')));
        } finally {
          await db.close();
        }
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
