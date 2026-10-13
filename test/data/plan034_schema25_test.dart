import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:seguimiento/data/database.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test('schema25 declared target and nullable unknowns, zero remains distinct', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect((await db.customSelect('PRAGMA user_version').getSingle()).data.values.single, 25);
    await db.customStatement("INSERT INTO morning_checks(date,knee_stairs) VALUES('2030-02-04',0),('2030-02-05',NULL)");
    expect((await db.select(db.morningChecks).get()).map((r) => r.kneeStairs).toList(), [0, null]);
    for (final (table, columns) in [
      ('plan_exercises', ['purpose','physical_variant_key']),
      ('sleep_logs', ['sleep_start','wake_at','source','note']),
      ('football_games', ['weights_comparable']),
      ('fitness_tests', ['attempt_id','conditions','baseline_key']),
      ('custom_reminders', ['origin']),
      ('fitness_test_attempts', ['protocol_id','session_id','block_start']),
      ('mobility_benchmarks', ['value','touches','conditions']),
    ]) {
      final fields = (await db.customSelect('PRAGMA table_info($table)').get()).map((r) => r.read<String>('name')).toSet();
      expect(fields.containsAll(columns), isTrue, reason: '$table columns');
    }
  });
}
