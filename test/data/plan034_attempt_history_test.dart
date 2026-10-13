import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test('034 saving a second real attempt preserves first results and session',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FitnessTestRepository(db);
    final day = DateTime(2030, 2, 4);
    for (final value in [5.0, 8.0]) {
      await repo.save(
          date: day,
          round: 1,
          part: TestPart.torso,
          results: [TestResult(round: 1, item: 'pullup', value: value)],
          totalSec: 0);
    }
    expect(
        (await db.select(db.fitnessTests).get()).map((r) => r.value).toList(),
        [5.0, 8.0]);
    final sessions = await db.select(db.sessions).get();
    expect(sessions, hasLength(2));
    expect(sessions.first.context, contains('5 reps'));
    expect(sessions.last.context, contains('8 reps'));
    expect(sessions.every((s) => s.totalSec == 0), isTrue);
  });
}
