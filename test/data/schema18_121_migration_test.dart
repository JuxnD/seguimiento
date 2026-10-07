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
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';

import '../support/sqlite_host.dart';

const _fixtureSha =
    '6bfe3abcf1295bbc109ee597c61ca39a7262f394163e8347d8cfa4b56279827a';
const _sourceCommit = '410da05d341d8ea88915fe8a197d3df6eee54283';

class _LegacyTable {
  const _LegacyTable(this.columns, this.rows);
  final List<String> columns;
  final List<Map<String, Object?>> rows;
}

void main() {
  setUpAll(() {
    useHostSqlite();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  final fixture = File('test/fixtures/schema18-synthetic.sqlite');
  final manifest = jsonDecode(
      File('test/fixtures/schema18-synthetic-manifest.json')
          .readAsStringSync()) as Map<String, dynamic>;

  Map<String, _LegacyTable> legacyRows() {
    final raw = sqlite3.open(fixture.path, mode: OpenMode.readOnly);
    try {
      return {
        for (final name in (manifest['table_inventory'] as List).cast<String>())
          name: _LegacyTable(
            raw
                .select('PRAGMA table_info("$name")')
                .map((row) => row['name'] as String)
                .toList(),
            raw
                .select('SELECT * FROM "$name" ORDER BY rowid')
                .map((row) => Map<String, Object?>.from(row))
                .toList(),
          ),
      };
    } finally {
      raw.dispose();
    }
  }

  Future<void> verifyPreservation(
      AppDatabase db, Map<String, _LegacyTable> before) async {
    for (final entry in before.entries) {
      final columns = entry.value.columns.map((name) => '"$name"').join(',');
      final actual = await db
          .customSelect('SELECT $columns FROM "${entry.key}" ORDER BY rowid')
          .get();
      if (jsonEncode(actual.map((row) => row.data).toList()) !=
          jsonEncode(entry.value.rows)) {
        throw StateError('Preservation mismatch: ${entry.key}');
      }
    }
  }

  Future<void> verifyLiteralOracle(AppDatabase db) async {
    final setting = await db
        .customSelect("SELECT * FROM reminders WHERE kind='sesion'")
        .getSingle();
    expect(setting.data, manifest['reminder_setting']);
    expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM reminders')
                .getSingle())
            .data['n'],
        11);
    final expected = manifest['expected'] as Map<String, dynamic>;
    for (final entry in expected.entries) {
      final wanted = (entry.value as List).cast<Map<String, dynamic>>();
      final actual = await db
          .customSelect('SELECT * FROM "${entry.key}" ORDER BY id')
          .get();
      expect(actual, hasLength(wanted.length), reason: entry.key);
      for (var index = 0; index < wanted.length; index++) {
        for (final field in wanted[index].entries) {
          expect(actual[index].data[field.key], field.value,
              reason: '${entry.key} row $index ${field.key}');
        }
      }
    }
    final repository = AiConversationRepository(db);
    final report = (await repository.read(1))!;
    final guide = (await repository.read(2))!;
    expect(await repository.count(), 2);
    expect(report.turns, hasLength(4));
    expect(report.turns.last.citations.single.quote,
        'No permite concluir una tendencia.');
    expect(guide.turns, hasLength(2));
    expect(guide.snapshot.guideContext!.exercise, 'Dominadas');
    expect(guide.snapshot.guideContext!.grip, 'prona');
    expect(guide.snapshot.guideContext!.loaded, true);
    expect(guide.snapshot.guideContext!.cues, ['Escápulas activas']);
    expect(guide.turns.last.citations.single.quote,
        'Dominadas con carga y agarre prona.');
    expect((await db.customSelect('PRAGMA foreign_key_check').get()), isEmpty);
    expect(
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .data
            .values
            .single,
        'ok');
  }

  test('fixture is genuinely frozen schema18, pinned and independently checked',
      () async {
    expect(sha256.convert(fixture.readAsBytesSync()).toString(), _fixtureSha);
    expect(manifest['fixture_sha256'], _fixtureSha);
    expect(manifest['source_commit'], _sourceCommit);
    expect(manifest['synthetic_only'], true);
    final raw = sqlite3.open(fixture.path, mode: OpenMode.readOnly);
    try {
      expect(raw.select('PRAGMA user_version').single.values.single, 18);
      expect(
          raw
              .select(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
              .map((row) => row['name']),
          manifest['table_inventory']);
      expect(
          raw.select(
              "SELECT name FROM sqlite_master WHERE name IN ('fitness_tests','ladder_states')"),
          isEmpty);
      expect(
          raw.select('SELECT COUNT(*) AS n FROM ai_conversations').single['n'],
          2);
      expect(
          raw.select('SELECT COUNT(*) AS n FROM ai_messages').single['n'], 6);
    } finally {
      raw.dispose();
    }
  });

  test(
      '18 to current: reopen, ZIP, restore, reopen preserves all old rows and AI',
      () async {
    final root =
        Directory.systemTemp.createTempSync('seguimiento_121_migration_');
    final before = legacyRows();
    final dirA = Directory('${root.path}/A')..createSync();
    final dirB = Directory('${root.path}/B')..createSync();
    final fileA = fixture.copySync('${dirA.path}/seguimiento.sqlite');
    final fileB = File('${dirB.path}/seguimiento.sqlite');
    DatabaseHost open(File file) =>
        DatabaseHost(file, (f) => AppDatabase(NativeDatabase(f)));
    var a = open(fileA);
    var b = open(fileB);
    try {
      expect(a.db.schemaVersion, greaterThanOrEqualTo(19));
      await a.db.customStatement('SELECT 1'); // Actual migration, not metadata.
      expect(
          (await a.db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          a.db.schemaVersion);
      await verifyPreservation(a.db, before);
      await verifyLiteralOracle(a.db);
      await a.db.close();
      a = open(fileA);
      await verifyPreservation(a.db, before);
      await verifyLiteralOracle(a.db);

      // Recipient has distinct data; restoration must actually replace it.
      await BodyRepository(b.db).addWeight(DateTime(2026, 10, 7), 99);
      final exported = await BackupArchive(host: a, documents: dirA)
          .exportTo('${root.path}/portable.zip');
      expect(exported.file.readAsBytesSync().take(4), [80, 75, 3, 4]);
      expect(exported.complete, true);
      await BackupArchive(host: b, documents: dirB).restoreFrom(exported.file);
      await verifyPreservation(b.db, before);
      await verifyLiteralOracle(b.db);
      await b.db.close();
      b = open(fileB);
      await verifyPreservation(b.db, before);
      await verifyLiteralOracle(b.db);
      expect(
          (await BodyRepository(b.db).watchWeights().first)
              .map((row) => row.kg),
          [72.5]);
    } finally {
      await a.db.close();
      await b.db.close();
      root.deleteSync(recursive: true);
    }
  });

  test('negative controls reject changed source, removed citation and lost row',
      () async {
    final root =
        Directory.systemTemp.createTempSync('seguimiento_121_mutants_');
    final before = legacyRows();
    try {
      for (final mutation in ['source', 'citation', 'row']) {
        final file = fixture.copySync('${root.path}/$mutation.sqlite');
        final db = AppDatabase(NativeDatabase(file));
        try {
          await verifyPreservation(db, before); // Same baseline green first.
          if (mutation == 'source') {
            await db.customStatement(
                "UPDATE ai_conversations SET sources_json='[]' WHERE id=1");
            await expectLater(
                AiConversationRepository(db).read(1), throwsFormatException);
            await expectLater(
                verifyPreservation(db, before),
                throwsA(isA<StateError>().having((e) => e.message,
                    'exact table', 'Preservation mismatch: ai_conversations')));
          } else if (mutation == 'citation') {
            await db.customStatement(
                "UPDATE ai_messages SET citations_json='[]' WHERE id=2");
            await expectLater(
                AiConversationRepository(db).read(1), throwsFormatException);
            await expectLater(
                verifyPreservation(db, before),
                throwsA(isA<StateError>().having((e) => e.message,
                    'exact table', 'Preservation mismatch: ai_messages')));
          } else {
            await db.customStatement('DELETE FROM ai_messages WHERE id=2');
            await expectLater(
                verifyPreservation(db, before),
                throwsA(isA<StateError>().having((e) => e.message,
                    'exact table', 'Preservation mismatch: ai_messages')));
          }
        } finally {
          await db.close();
        }
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
