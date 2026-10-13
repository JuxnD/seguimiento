import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import 'package:seguimiento/domain/leg_chain.dart';
import 'package:seguimiento/domain/enums.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test('Tuesday week6 retains only planche inclinations and halves once',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final ex = ExerciseRepository(db),
        plan = PlanRepository(db, ExerciseRepository(db));
    final training = TrainingRepository(db, ex),
        start = DateTime(2030, 2, 4),
        date = DateTime(2030, 3, 12);
    await activatePlanV32(db, plan, start);
    final view = (await plan.dayFor(date))!;
    final effective = await training.withV31Blocks(
        view.day, date, await training.blockDay(view, date),
        planche: true);
    expect(
        effective.exercises.where((e) =>
            e.name == 'Flexión pseudo-planche' || e.name == 'Tuck planche'),
        isEmpty);
    expect(
        effective.exercises
            .singleWhere((e) => e.name == 'Inclinación de planche')
            .sets,
        2);
    expect(
        effective.exercises
            .singleWhere((e) => e.name == 'Support hold en paralelas')
            .sets,
        2);
  });
  for (final sample in [
    (known: true, value: 50.0, expected: 40),
    (known: false, value: 50.0, expected: null),
    (known: true, value: 10.0, expected: null)
  ]) {
    test('Tuesday hang has explicit comparable max minus10 or pending $sample',
        () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final ex = ExerciseRepository(db),
          plan = PlanRepository(db, ExerciseRepository(db));
      final training = TrainingRepository(db, ex),
          start = DateTime(2030, 2, 4),
          date = DateTime(2030, 2, 5);
      await activatePlanV32(db, plan, start);
      await FitnessTestRepository(db).save(
          date: start,
          round: 1,
          part: TestPart.torso,
          protocol: TestProtocolId.v32_13,
          scheme: 'v3.2',
          blockStart: start,
          totalSec: 0,
          results: [
            TestResult(round: 1, item: 'dead_hang', value: sample.value)
          ],
          conditions: sample.known
              ? {
                  'dead_hang': {'variant': 'pasivo', 'grip': 'prona'}
                }
              : {});
      final view = (await plan.dayFor(date))!;
      final effective = await training.withV31Blocks(
          view.day, date, await training.blockDay(view, date),
          planche: false);
      final rows = effective.exercises
          .where((e) => e.name == 'Colgarse de la barra')
          .toList();
      if (sample.expected == null) {
        expect(rows, isEmpty);
        expect(effective.notes, contains('Colgado pendiente'));
      } else {
        expect(rows.single.sets, 2);
        expect(rows.single.holdSecMin, sample.expected);
        expect(rows.single.holdSecMax, sample.expected);
      }
    });
  }
  test('explicit running1515 identifies legs while exclusions remain intact',
      () {
    final date = DateTime(2030, 2, 5);
    final session = ChainSession(
        date: date,
        type: SessionType.resistencia,
        mode: 'running1515',
        rpe: 6,
        workMinutes: 16);
    expect(classifySession(session)!.groups, {ChainGroup.legs});
    expect(classifySession(session)!.intensity, DayIntensity.moderate);
    expect(
        classifySession(ChainSession(
            date: date,
            type: SessionType.resistencia,
            mode: 'running1515',
            rpe: 5,
            workMinutes: 16)),
        isNull);
    expect(
        classifySession(ChainSession(
            date: date,
            type: SessionType.resistencia,
            mode: 'running1515',
            imported: true,
            rpe: 9,
            workMinutes: 16)),
        isNull);
  });
}
