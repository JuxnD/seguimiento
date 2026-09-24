import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/report/report_input.dart';
import '../../domain/session_math.dart';
import '../database.dart';
import 'exercise_repository.dart';
import 'nutrition_repository.dart';
import 'profile_repository.dart';
import 'training_repository.dart';

/// Arma el `ReportInput` desde la base. Toda la lógica de negocio vive en
/// `domain/report`; aquí solo se consulta y se mapea.
class ReportRepository {
  ReportRepository(this.db, this.nutrition);

  final AppDatabase db;
  final NutritionRepository nutrition;

  Future<ReportInput> load(DateTime from, DateTime to, {DateTime? today}) async {
    final f = dayKey(from), t = dayKey(to);
    final profile = await (db.select(db.profiles)..where((x) => x.id.equals(1))).getSingle();
    final start = profile.programStart;
    final names = {for (final e in await db.select(db.exercises).get()) e.id: e.name};

    // Plan: todas las versiones con su mapa de tipos por día. Dos consultas
    // en total, no una por versión.
    final versions = await (db.select(db.planVersions)..orderBy([(x) => OrderingTerm(expression: x.id)])).get();
    final daysByVersion = <int, List<PlanDayRow>>{};
    for (final d in await db.select(db.planDays).get()) {
      daysByVersion.putIfAbsent(d.planVersionId, () => []).add(d);
    }
    final planInfos = <PlanVersionInfo>[];
    for (var i = 0; i < versions.length; i++) {
      final v = versions[i];
      final days = daysByVersion[v.id] ?? const <PlanDayRow>[];
      planInfos.add(PlanVersionInfo(
        number: i + 1,
        validFrom: parseDay(v.validFrom),
        notes: v.notes,
        dayTypes: {for (final d in days) d.weekday: d.type},
      ));
    }

    // Sesiones, con sus series y vueltas en dos consultas (no dos por sesión).
    final sessionRows = await (db.select(db.sessions)..where((x) => x.date.isBetweenValues(f, t))).get();
    final ids = [for (final s in sessionRows) s.id];
    final setsBySession = <int, List<SessionSetRow>>{};
    final marksBySession = <int, List<int>>{};
    if (ids.isNotEmpty) {
      final allSets = await (db.select(db.sessionSets)
            ..where((x) => x.sessionId.isIn(ids))
            ..orderBy([(x) => OrderingTerm(expression: x.id)]))
          .get();
      for (final set in allSets) {
        setsBySession.putIfAbsent(set.sessionId, () => []).add(set);
      }
      final allRounds = await (db.select(db.sessionRounds)
            ..where((x) => x.sessionId.isIn(ids))
            ..orderBy([(x) => OrderingTerm(expression: x.roundIndex)]))
          .get();
      for (final r in allRounds) {
        marksBySession.putIfAbsent(r.sessionId, () => []).add(r.elapsedSec);
      }
    }
    final sessions = <SessionEntry>[];
    for (final s in sessionRows) {
      final sets = setsBySession[s.id] ?? const <SessionSetRow>[];
      final marks = marksBySession[s.id] ?? const <int>[];
      sessions.add(SessionEntry(
        date: parseDay(s.date),
        startTime: s.startTime,
        type: s.type,
        totalSec: s.totalSec,
        warmupSec: s.warmupSec,
        cooldownSec: s.cooldownSec,
        restSec: s.restSec,
        roundsDone: s.roundsDone,
        roundsEstimated: s.roundsEstimated,
        rpe: s.rpe,
        limitingExercise: s.limitingExerciseId == null ? null : names[s.limitingExerciseId],
        context: s.context,
        notes: s.notes,
        outOfPlan: s.outOfPlan,
        incomplete: s.incomplete,
        plannedRounds: s.plannedRounds,
        techniqueOk: s.techniqueOk,
        fullRange: s.fullRange,
        recoveryOk: s.recoveryOk,
        lapsSec: lapDurations(marks),
        sets: [
          for (final x in sets)
            SetEntry(
              exercise: names[x.exerciseId] ?? '?',
              setIndex: x.setIndex,
              reps: x.reps,
              split: x.split,
              splitDetail: x.splitDetail,
              toFailure: x.toFailure,
            ),
        ],
      ));
    }

    final maxBefore = db.sessions.roundsDone.max();
    final prevRecord = await (db.selectOnly(db.sessions)
          ..addColumns([maxBefore])
          ..where(db.sessions.date.isSmallerThanValue(f) & db.countedCircuitRounds))
        .map((r) => r.read(maxBefore))
        .getSingle();

    final roundsBefore = await TrainingRepository(db, ExerciseRepository(db)).lastRoundsBefore(from);

    final football = await (db.select(db.footballGames)..where((x) => x.date.isBetweenValues(f, t))).get();

    final meals = await nutrition.range(from, to);

    final weights = await (db.select(db.bodyWeights)..where((x) => x.date.isBetweenValues(f, t))).get();
    final baselineWeight = await (db.select(db.bodyWeights)
          ..orderBy([(x) => OrderingTerm(expression: x.date), (x) => OrderingTerm(expression: x.id)])
          ..limit(1))
        .getSingleOrNull();

    final measures = await (db.select(db.measurements)..where((x) => x.date.isBetweenValues(f, t))).get();
    // Línea base: la primera toma de cada sitio, en una sola consulta.
    final baseline = <MeasureSite, MeasurementEntry>{};
    for (final m in await (db.select(db.measurements)..orderBy([(x) => OrderingTerm(expression: x.date)])).get()) {
      baseline.putIfAbsent(m.site, () => _measure(m));
    }
    final datesBefore = await (db.selectOnly(db.measurements, distinct: true)
          ..addColumns([db.measurements.date])
          ..where(db.measurements.date.isSmallerThanValue(f)))
        .map((r) => parseDay(r.read(db.measurements.date)!))
        .get();

    // Notas: todas las semanas que tocan el rango.
    final wFrom = weekIndexFor(start, from), wTo = weekIndexFor(start, to);
    final notes = await (db.select(db.weekNotes)
          ..where((x) => x.weekIndex.isBetweenValues(wFrom, wTo))
          ..orderBy([(x) => OrderingTerm(expression: x.weekIndex)]))
        .get();

    return ReportInput(
      programStart: start,
      rangeStart: from,
      rangeEnd: to,
      today: today ?? DateTime.now(),
      targets: profile.targets,
      planVersions: planInfos,
      sessions: sessions,
      previousRoundsRecord: prevRecord,
      roundsBeforeRange: roundsBefore,
      football: [
        for (final g in football)
          FootballEntry(
            date: parseDay(g.date),
            format: g.format,
            minutes: g.minutes,
            steps: g.steps,
            intensity: g.intensity,
            fatigueAfter: g.fatigueAfter,
            notes: g.notes,
          ),
      ],
      meals: [
        for (final m in meals)
          MealEntry(
            date: parseDay(m.meal.date),
            slot: m.meal.slot,
            time: m.meal.time,
            notes: m.meal.notes,
            items: [
              for (final i in m.items)
                MealItemEntry(
                  label: i.label,
                  quantityLabel: MealItemDraft(
                    label: i.label,
                    quantity: i.quantity,
                    quantityUnit: i.quantityUnit,
                    macros: i.macros,
                  ).quantityLabel,
                  macros: i.macros,
                  sourceVerified: i.sourceVerified,
                ),
            ],
          ),
      ],
      weightsInRange: [for (final w in weights) WeightEntry(date: parseDay(w.date), kg: w.kg, fasted: w.fasted)],
      baselineWeight: baselineWeight == null
          ? null
          : WeightEntry(date: parseDay(baselineWeight.date), kg: baselineWeight.kg, fasted: baselineWeight.fasted),
      measurementsInRange: measures.map(_measure).toList(),
      baselineMeasurements: baseline,
      measurementDatesBefore: datesBefore,
      notes: notes.length <= 1
          ? notes.firstOrNull?.body
          : notes.map((n) => '**Semana ${n.weekIndex}:** ${n.body}').join('\n\n'),
    );
  }

  MeasurementEntry _measure(MeasurementRow r) =>
      MeasurementEntry(date: parseDay(r.date), site: r.site, valueCm: r.valueCm, fasted: r.fasted);
}
