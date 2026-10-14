import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Synthetic rows in historical additive schemas, not published old binaries.
void copyHistorical037(int version, File destination) {
  final root = Directory('test/fixtures/derived_historical_037');
  final manifestFile = File('${root.path}/manifest.json');
  expect(sha256.convert(manifestFile.readAsBytesSync()).toString(),
      '4ed88a7da0cb512f525f4fa2077ab1ae0f5d9dcf5b017775828071e33e5601dd');
  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
  expect(manifest['source22'], 'bf40054c89835c6dd54db9a6b99775b645987247');
  expect(manifest['source23'], '8872ae2b235d46dbc9b81f43f39af8f0c2827372');
  expect(manifest['syntheticOnly'], true);
  final name = 'schema$version.sqlite';
  final entry = (manifest['files'] as Map)[name] as Map;
  final bytes = File('${root.path}/$name').readAsBytesSync();
  expect(sha256.convert(bytes).toString(), entry['sha256']);
  destination.writeAsBytesSync(bytes);
  final db = sqlite.sqlite3.open(destination.path);
  try {
    expect(db.select('PRAGMA user_version').single.values.single, version);
    final tables = entry['tables'] as Map;
    expect(
        db
            .select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            .map((r) => r['name'])
            .toSet(),
        tables.keys.toSet());
    for (final item in tables.entries) {
      final name = item.key as String;
      final expected = item.value as Map;
      expect(
          db
              .select('PRAGMA table_info("$name")')
              .map((r) => r.values.toList())
              .toList(),
          expected['columns'],
          reason: name);
      expect(
          db
              .select('PRAGMA foreign_key_list("$name")')
              .map((r) => r.values.toList())
              .toList(),
          expected['foreignKeys'],
          reason: name);
      expect(
          db.select('SELECT sql FROM sqlite_master WHERE name=?',
              [name]).single['sql'],
          expected['ddl'],
          reason: name);
      final indexes = [
        for (final row in db.select('PRAGMA index_list("$name")'))
          {
            'row': row.values.toList(),
            'details': db
                .select('PRAGMA index_xinfo("${row['name']}")')
                .map((r) => r.values.toList())
                .toList()
          }
      ];
      expect(indexes, expected['indexes'], reason: name);
    }
    expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
  } finally {
    db.dispose();
  }
}
