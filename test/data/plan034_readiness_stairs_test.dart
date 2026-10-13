import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/domain/readiness.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test('explicit stairs zero is known independently of generic knee soreness',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(
        date: '2030-02-04', kneeStairs: const Value(0)));
    final advice =
        await ReadinessRepository(db).readinessOn(DateTime(2030, 2, 4));
    expect(advice.missing, isNot(contains('Escaleras: sin dato')));
  });
  test(
      'generic knee pain preserves severity with own source; it never fills stairs',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(
        date: '2030-02-04', kneeStairs: const Value(0)));
    await db.into(db.sorenessLogs).insert(SorenessLogsCompanion.insert(
        date: '2030-02-04', zone: 'Rodilla', level: 5));
    final advice =
        await ReadinessRepository(db).readinessOn(DateTime(2030, 2, 4));
    expect(advice.action, SuggestedAction.restOnly);
    expect(advice.reasons, contains('Dolor anotado en Rodilla 5/10'));
    expect(advice.reasons.any((r) => r.contains('escaleras 5')), isFalse);
  });
  test(
      'missing stairs remains unknown even when generic knee pain was recorded',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    await db.into(db.sorenessLogs).insert(SorenessLogsCompanion.insert(
        date: '2030-02-04', zone: 'Rodilla', level: 2));
    final advice =
        await ReadinessRepository(db).readinessOn(DateTime(2030, 2, 4));
    expect(advice.missing, contains('Escaleras: sin dato'));
  });
}
