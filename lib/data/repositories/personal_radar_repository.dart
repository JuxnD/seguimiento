import 'package:drift/drift.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart';
import '../../domain/goal_history.dart';
import '../../domain/chart_evidence.dart';
import '../../domain/progress_metrics.dart';
import '../database.dart';
import 'fitness_test_repository.dart';

GoalMetric radarMetric(RadarAxis axis) => switch (axis) {
      RadarAxis.pull => GoalMetric.refDominadas,
      RadarAxis.push => GoalMetric.refFlexiones,
      RadarAxis.core => GoalMetric.refHollow,
      RadarAxis.legs => GoalMetric.refBulgara,
      RadarAxis.jump => GoalMetric.refSaltoLargo,
      RadarAxis.circuit => GoalMetric.refCindy,
    };

String _referenceSource(GoalVersion version) => switch (version.origin) {
  GoalOrigin.inicio => 'Referencia personal inicial',
  GoalOrigin.perfil => 'Referencia personal aceptada',
  GoalOrigin.plan => 'Referencia documentada en el plan',
  GoalOrigin.propuesta => 'Referencia de una propuesta aceptada',
  GoalOrigin.legado => 'Referencia procedente del historial legado',
  _ => 'Referencia registrada con origen no reconocido',
};

/// Open validity is retained: a query end is not the end of a decision.
DateTime? goalUntil(GoalHistory history, GoalMetric metric, DateTime day) {
  final future =
      history.of(metric).where((v) => v.effectiveFrom != null && dateOnly(v.effectiveFrom!).isAfter(dateOnly(day)));
  return future.isEmpty ? null : addDays(future.first.effectiveFrom!, -1);
}

DatedChartGoal? historicalChartGoal(GoalHistory history, DateTime day, String metric) {
  final m = switch (metric) {
    'proteinMin' => GoalMetric.proteinaMin,
    'steps' => GoalMetric.pasos,
    _ => null,
  };
  if (m == null || (m == GoalMetric.pasos && day.weekday >= DateTime.saturday)) {
    return null;
  }
  final at = history.on(m, day), version = history.current(m, day);
  if (at == null ||
      !at.known ||
      at.value == null ||
      !at.value!.isFinite ||
      at.value! <= 0 ||
      version?.effectiveFrom == null) return null;
  return DatedChartGoal(
      from: version!.effectiveFrom!,
      to: goalUntil(history, m, day),
      value: at.value!,
      unit: m.unit,
      source: 'Referencia personal registrada');
}

/// Read-only. Buffers batches of 128 sessions; retains O(observations + sets)
/// for the existing pure core, rather than silently truncating the baseline.
class PersonalRadarRepository {
  PersonalRadarRepository(this.db);
  final AppDatabase db;
  static const batchSize = 128;

  Future<PersonalRadar> load({required DateTime end, required DateTime today, required GoalHistory history}) async {
    final cutoff = dateOnly(end.isAfter(today) ? today : end);
    final tests =
        (await FitnessTestRepository(db).all()).where((r) => r.date == null || !r.date!.isAfter(cutoff)).toList();
    final observations = <CindyObservation>[];
    var cursor = 0;
    while (true) {
      final sessions = await (db.select(db.sessions)
            ..where((s) =>
                s.id.isBiggerThanValue(cursor) & (s.type.equalsValue(SessionType.resistencia) | s.mode.equals('cindy')))
            ..orderBy([(s) => OrderingTerm.asc(s.id)])
            ..limit(batchSize))
          .get();
      if (sessions.isEmpty) break;
      cursor = sessions.last.id;
      final relevant = sessions.where((s) {
        final date = recordedTestDate(s.date);
        return date == null || !date.isAfter(cutoff);
      }).toList();
      final sets = <int, List<CindySet>>{};
      if (relevant.isNotEmpty) {
        final joined = await (db
                .select(db.sessionSets)
                .join([innerJoin(db.exercises, db.exercises.id.equalsExp(db.sessionSets.exerciseId))])
              ..where(db.sessionSets.sessionId.isIn(relevant.map((s) => s.id)))
              // setIndex is PER EXERCISE. Insertion order is the recorded recipe.
              ..orderBy([OrderingTerm.asc(db.sessionSets.sessionId), OrderingTerm.asc(db.sessionSets.id)]))
            .get();
        for (final row in joined) {
          final s = row.readTable(db.sessionSets);
          sets.putIfAbsent(s.sessionId, () => []).add(CindySet(
              exercise: row.readTable(db.exercises).name,
              reps: s.reps,
              variant: s.variant,
              loadKg: s.loadKg,
              split: s.split,
              toFailure: s.toFailure));
        }
      }
      for (final s in relevant) {
        observations.add(CindyObservation(
            id: '${s.id}',
            date: recordedTestDate(s.date),
            type: s.type,
            mode: s.mode,
            totalSec: s.totalSec,
            warmupSec: s.warmupSec,
            cooldownSec: s.cooldownSec,
            rounds: s.roundsDone,
            extraReps: s.extraReps,
            sets: sets[s.id] ?? const [],
            imported: s.imported,
            estimated: s.roundsEstimated,
            incomplete: s.incomplete,
            techniqueOk: s.techniqueOk,
            fullRange: s.fullRange));
      }
    }
    final refs = <RadarAxis, RadarReference>{};
    for (final axis in RadarAxis.values) {
      final metric = radarMetric(axis), at = history.on(radarMetric(axis), cutoff);
      final version = history.current(metric, cutoff);
      if (at?.known == true &&
          at?.value != null &&
          at!.value!.isFinite &&
          at.value! > 0 &&
          version?.effectiveFrom != null) {
        refs[axis] = RadarReference(
            id: 'goal:${version!.id}',
            axis: axis,
            value: at.value!,
            unit: metric.unit,
            from: version.effectiveFrom!,
            until: goalUntil(history, metric, cutoff),
            source: _referenceSource(version),
            protocol: axis.protocol);
      }
    }
    return buildPersonalRadar(tests: tests, cindy: observations, references: refs, asOf: cutoff);
  }
}
