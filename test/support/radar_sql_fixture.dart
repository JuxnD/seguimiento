import 'package:drift/drift.dart' show Value;
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/personal_radar_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/progress_metrics.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'radar_fixture.dart';

Future<void> seedRadarSql(AppDatabase db,
    {bool complete = true, bool references = true}) async {
  for (final r in radarTests()
      .where((r) => complete || ['pullup', 'pushup'].contains(r.item))) {
    await insertRadarTestSql(db, r);
  }
  if (complete) {
    await insertCindySql(db, radarCindy(day: 1, rounds: 6));
    await insertCindySql(db, radarCindy());
  }
  if (references) {
    final goals = GoalRepository(db);
    for (final e in radarReferences().entries) {
      await goals.setReference(radarMetric(e.key), e.value.value,
          now: e.value.from);
    }
  }
}

Future<void> insertRadarTestSql(AppDatabase db, TestResult r) async {
  if (r.attemptId != null) {
    final existing = await (db.select(db.fitnessTestAttempts)
          ..where((t) => t.id.equals(r.attemptId!)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.fitnessTestAttempts).insert(
          FitnessTestAttemptsCompanion.insert(
              id: Value(r.attemptId!),
              date: dayKey(r.date!),
              round: r.round,
              part: r.attemptId! >= 1000 ? 'piernas' : 'torso',
              protocolId: r.protocolId,
              scheme: 'v3.1'));
    }
  }
  await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
      round: r.round,
      item: r.item,
      value: r.value,
      date: dayKey(r.date!),
      side: Value(r.side),
      clean: Value(r.clean),
      attemptId: Value(r.attemptId),
      conditions: Value(r.conditions),
      baselineKey: Value(r.baselineKey)));
}

Future<int> insertCindySql(AppDatabase db, CindyObservation row,
    {String? rawDate}) async {
  final id = await db.into(db.sessions).insert(SessionsCompanion.insert(
      date: rawDate ?? dayKey(row.date!),
      type: row.type,
      mode: Value(row.mode),
      totalSec: Value(row.totalSec),
      warmupSec: Value(row.warmupSec),
      cooldownSec: Value(row.cooldownSec),
      roundsDone: Value(row.rounds),
      extraReps: Value(row.extraReps),
      imported: Value(row.imported),
      roundsEstimated: Value(row.estimated),
      incomplete: Value(row.incomplete),
      techniqueOk: Value(row.techniqueOk),
      fullRange: Value(row.fullRange)));
  final indices = <String, int>{};
  for (final set in row.sets) {
    final exercise = await (db.select(db.exercises)
          ..where((e) => e.name.equals(set.exercise)))
        .getSingleOrNull();
    final exerciseId = exercise?.id ??
        await db
            .into(db.exercises)
            .insert(ExercisesCompanion.insert(name: set.exercise));
    final index = (indices[set.exercise] ?? 0) + 1;
    indices[set.exercise] = index;
    await db.into(db.sessionSets).insert(SessionSetsCompanion.insert(
        sessionId: id,
        exerciseId: exerciseId,
        setIndex: index,
        reps: set.reps,
        split: Value(set.split),
        toFailure: Value(set.toFailure),
        variant: Value(set.variant),
        loadKg: Value(set.loadKg)));
  }
  return id;
}
