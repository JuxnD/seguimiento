import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  for (final attempt in [true, false]) {
    test(
        'pending profile rejects only a new ${attempt ? 'attempt' : 'benchmark'} row',
        () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      expect((await validateSetup(db)).pending, isTrue);
      expect(await personalTablesWithRows(db), isEmpty);
      if (attempt) {
        await db.into(db.fitnessTestAttempts).insert(
            FitnessTestAttemptsCompanion.insert(
                date: '2030-02-04',
                round: 1,
                part: 'torso',
                protocolId: 'v32_13',
                scheme: 'v3.2'));
      } else {
        await db.into(db.mobilityBenchmarks).insert(
            MobilityBenchmarksCompanion.insert(
                date: '2030-02-04', item: 'shoulder_wall'));
      }
      expect(await personalTablesWithRows(db),
          [attempt ? 'fitness_test_attempts' : 'mobility_benchmarks']);
      await expectLater(
          validateSetup(db), throwsA(isA<InvalidSetupException>()));
    });
  }
}
