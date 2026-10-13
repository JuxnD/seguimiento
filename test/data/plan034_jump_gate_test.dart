import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  for (final sample in [
    (stairs: 0, ill: false, blocked: false),
    (stairs: 2, ill: false, blocked: false),
    (stairs: null, ill: false, blocked: false),
    (stairs: 3, ill: false, blocked: true),
    (stairs: 4, ill: false, blocked: true),
    (stairs: 5, ill: false, blocked: true),
    (stairs: 0, ill: true, blocked: true)
  ]) {
    test(
        'real new jump respects stairs/rest and never manufactures result $sample',
        () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final repo = FitnessTestRepository(db);
      await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(
          date: '2030-02-06',
          kneeStairs: Value(sample.stairs),
          ill: Value(sample.ill)));
      final save = repo.save(
          date: DateTime(2030, 2, 6),
          round: 1,
          part: TestPart.piernas,
          totalSec: 0,
          results: const [
            TestResult(round: 1, item: 'broad_jump', value: 160, clean: true)
          ]);
      if (sample.blocked) {
        await expectLater(save, throwsFormatException);
        expect(await repo.all(), isEmpty);
        expect(await db.select(db.fitnessTestAttempts).get(), isEmpty);
        expect(await db.select(db.sessions).get(), isEmpty);
      } else {
        await save;
        expect((await repo.all()).single.value, 160);
      }
    });
  }
}
