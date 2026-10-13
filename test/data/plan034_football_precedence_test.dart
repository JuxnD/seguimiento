import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  for (final sample in [
    (stairs: 0, minutes: 60, rpe: 7, imported: false, eighty: true),
    (stairs: 2, minutes: 45, rpe: 6, imported: false, eighty: true),
    (stairs: 0, minutes: 20, rpe: 9, imported: false, eighty: false),
    (stairs: 0, minutes: 60, rpe: 5, imported: false, eighty: false),
    (stairs: 0, minutes: 60, rpe: 9, imported: true, eighty: false),
    (stairs: null, minutes: 60, rpe: 9, imported: false, eighty: false),
  ]) {
    test('Wednesday exception uses shared intensity and known stairs $sample',
        () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final exercises = ExerciseRepository(db);
      final plan = PlanRepository(db, exercises);
      final training = TrainingRepository(db, exercises);
      final today = DateTime(2030, 2, 6);
      await activatePlanV32(db, plan, DateTime(2030, 2, 4));
      await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(
          date: '2030-02-06', kneeStairs: Value(sample.stairs)));
      await db.into(db.footballGames).insert(FootballGamesCompanion.insert(
          date: '2030-02-05',
          minutes: sample.minutes,
          intensity: Value(sample.rpe),
          imported: Value(sample.imported)));
      final view = (await plan.dayFor(today))!;
      final day = await training.withV31Blocks(
          view.day, today, await training.blockDay(view, today),
          planche: false);
      expect(day.type, isNot(DayType.descanso));
      final acceleration =
          day.exercises.singleWhere((e) => e.name == 'Aceleración 10–20 m');
      expect(acceleration.notes?.contains('80%') ?? false, sample.eighty);
      expect(
          day.exercises.any((e) => e.name == 'Sprint lanzado'), !sample.eighty);
    });
  }
  for (final stairs in [3, 4]) {
    test('stairs $stairs suppress acceleration and explains postponement',
        () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final exercises = ExerciseRepository(db),
          plan = PlanRepository(db, ExerciseRepository(db));
      final training = TrainingRepository(db, exercises),
          today = DateTime(2030, 2, 6);
      await activatePlanV32(db, plan, DateTime(2030, 2, 4));
      await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(
          date: '2030-02-06', kneeStairs: Value(stairs)));
      await db.into(db.footballGames).insert(FootballGamesCompanion.insert(
          date: '2030-02-05', minutes: 60, intensity: const Value(9)));
      final view = (await plan.dayFor(today))!;
      final day = await training.withV31Blocks(
          view.day, today, await training.blockDay(view, today),
          planche: false);
      expect(
          day.exercises.any((e) => [
                'Aceleración 10–20 m',
                'Sprint lanzado',
                'Aterrizaje clavado'
              ].contains(e.name)),
          isFalse);
      expect(day.notes, contains('aplazados'));
      expect(day.notes, isNot(contains('80%')));
    });
  }
}
