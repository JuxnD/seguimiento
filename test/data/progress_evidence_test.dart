import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/progress.dart';
import 'package:seguimiento/domain/progress_evidence.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late TrainingRepository training;
  setUp(() {
    db = openInMemoryDatabase();
    training = TrainingRepository(db, ExerciseRepository(db));
  });
  tearDown(() => db.close());
  test('SQLite marcas→duraciones65 sin doble conversión, trabajo vs vueltas', () async {
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    final planId = (await plan.dayFor(DateTime(2026, 10, 1)))!.dayId;
    await training.save(SessionDraft(
        date: DateTime(2026, 10, 1),
        planDayId: planId,
        sets: [SetDraft(exercise: 'Flexiones', reps: 10)],
        totalSec: 195,
        roundsDone: 3,
        roundMarksSec: [60, 125, 195],
        roundRestSec: [0, 0, 0]));
    final previous = (await training.previousTiming(SessionType.circuito, DateTime(2026, 10, 2)))!;
    expect(previous.durationsSec, [60, 65, 70]);
    expect(previous.meanDurationSec, 65);
    expect(previous.basis, TimingBasis.work);
    final comparison = timedSessionComparison(
        current: RoundTimingEvidence(
            sessionId: null,
            date: DateTime(2026, 10, 8),
            type: SessionType.circuito,
            basis: TimingBasis.work,
            durationsSec: [50, 55, 60],
            planDayId: planId,
            exerciseProtocol: previous.exerciseProtocol),
        previous: previous);
    expect(comparison.previousMeanLapSec, 65,
        reason: 'Exact completion consumer, not a copied lap algorithm');
    await training.save(SessionDraft(
        date: DateTime(2026, 10, 2), totalSec: 195, roundsDone: 3, roundMarksSec: [60, 125, 195]));
    expect(
        (await training.previousTiming(SessionType.circuito, DateTime(2026, 10, 3)))!.basis, TimingBasis.lap);
  });
  test('SQLite flags→política no aumenta mochila con fallo/12+3', () async {
    await training.save(SessionDraft(date: DateTime(2026, 10, 5), type: SessionType.bloques, sets: [
      SetDraft(exercise: 'Flexiones', reps: 15, split: true, splitDetail: '12+3', toFailure: true)
    ]));
    final sets = await training.lastStrengthSets('Flexiones', DateTime(2026, 10, 12));
    expect((sets.single.split, sets.single.splitDetail, sets.single.toFailure), (true, '12+3', true));
    final evidence = await training.lastStrengthEvidence('Flexiones', DateTime(2026, 10, 12));
    expect(
        strengthProgressionHint(
            evidence: evidence,
            date: DateTime(2026, 10, 12),
            repsMin: 10,
            repsMax: 15,
            plannedSets: 1,
            tracksLoad: true),
        isNull);
    expect(await training.lastStrengthEvidence('Flexiones', DateTime(2026, 10, 5)), isNull);
  });
  test('fecha real releída, parcial bilateral y dudas no reemplazan referencia apta', () async {
    final repo = FitnessTestRepository(db);
    await repo
        .save(date: DateTime(2026, 10, 5), round: 2, part: TestPart.piernas, totalSec: 0, results: const [
      TestResult(round: 2, item: 'bulgarian_split_squat', side: 'I', value: 20),
      TestResult(round: 2, item: 'bulgarian_split_squat', side: 'D', value: 22)
    ]);
    await repo.save(
        date: DateTime(2026, 10, 7),
        round: 3,
        part: TestPart.piernas,
        totalSec: 0,
        results: const [TestResult(round: 3, item: 'bulgarian_split_squat', side: 'I', value: 25)]);
    final rows = await repo.all();
    expect(rows.first.date, DateTime(2026, 10, 5));
    expect(latestEligibleTestRound(rows, 'bulgarian_split_squat', asOf: DateTime(2026, 10, 9)), 2);
    expect(await repo.recordedDateFor(3, TestPart.piernas), DateTime(2026, 10, 7));
    expect(await repo.recordedDateFor(1, TestPart.torso), isNull);
  });
}
