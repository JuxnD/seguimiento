import 'package:drift/drift.dart';

import '../../domain/core_ladders.dart';
import '../../domain/fitness_test.dart';
import '../../domain/test_protocol.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/report/report_input.dart';
import '../../domain/session_math.dart';
import '../../domain/session_script.dart' show tabataBlock;
import '../database.dart';
import '../history_import.dart' show firstDataDay;
import 'exercise_repository.dart';
import 'fitness_test_repository.dart';
import 'mobility_benchmark_repository.dart';
import 'plan_repository.dart';
import 'nutrition_repository.dart';
import 'leg_chain_repository.dart';
import 'profile_repository.dart';
import 'readiness_repository.dart';
import 'supplement_repository.dart';
import 'training_repository.dart';
import 'goal_repository.dart';

/// Arma el `ReportInput` desde la base. Toda la lógica de negocio vive en
/// `domain/report`; aquí solo se consulta y se mapea.
class ReportRepository {
  ReportRepository(this.db, this.nutrition);

  final AppDatabase db;
  final NutritionRepository nutrition;

  /// Carga el rango y, si `withPrevious`, también el rango anterior del mismo
  /// largo (la semana pasada) para las comparaciones.
  Future<ReportInput> load(DateTime from, DateTime to,
      {DateTime? today, bool withPrevious = true}) async {
    final f = dayKey(from), t = dayKey(to);
    final profile = await (db.select(db.profiles)..where((x) => x.id.equals(1)))
        .getSingle();
    final start = profile.programStart;
    final names = {
      for (final e in await db.select(db.exercises).get()) e.id: e.name
    };

    // Plan: todas las versiones con su mapa de tipos por día. Dos consultas
    // en total, no una por versión.
    final versions = await (db.select(db.planVersions)
          ..orderBy([(x) => OrderingTerm(expression: x.id)]))
        .get();
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
        scheme: v.scheme,
        dayTypes: {for (final d in days) d.weekday: d.type},
      ));
    }

    // Sesiones, con sus series y vueltas en dos consultas (no dos por sesión).
    final allSessions = await (db.select(db.sessions)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();
    final sessionRows = [
      for (final s in allSessions)
        if (s.type.isTraining) s
    ];
    final beforeRows = <SessionRow>[];
    for (final type in SessionType.values.where((x) => x.isCircuit)) {
      // Igual que lastOfType/Hoy: última fecha anterior, luego último ID;
      // no saltar una sesión sin rondas para rescatar evidencia más antigua.
      final row = await (db.select(db.sessions)
            ..where(
                (x) => x.date.isSmallerThanValue(f) & x.type.equalsValue(type))
            ..orderBy([
              (x) => OrderingTerm(expression: x.date, mode: OrderingMode.desc),
              (x) => OrderingTerm(expression: x.id, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();
      if (row != null) beforeRows.add(row);
    }
    final evidenceRows = [...sessionRows, ...beforeRows];
    final mobility = [
      for (final s in allSessions)
        if (!s.type.isTraining)
          MobilityEntry(date: parseDay(s.date), totalSec: s.totalSec),
    ];
    final ids = [for (final s in evidenceRows) s.id];
    final setsBySession = <int, List<SessionSetRow>>{};
    final roundsBySession = <int, List<SessionRoundRow>>{};
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
        roundsBySession.putIfAbsent(r.sessionId, () => []).add(r);
      }
    }
    final sessions = <SessionEntry>[];
    final sessionsBefore = <SessionType, SessionEntry>{};
    for (final s in evidenceRows) {
      final sets = setsBySession[s.id] ?? const <SessionSetRow>[];
      final rounds = roundsBySession[s.id] ?? const <SessionRoundRow>[];
      final measured = rounds.isNotEmpty &&
          rounds.every((r) => r.workSec != null && r.restSec != null);
      final entry = SessionEntry(
        id: s.id,
        date: parseDay(s.date),
        startTime: s.startTime,
        type: s.type,
        totalSec: s.totalSec,
        warmupSec: s.warmupSec,
        cooldownSec: s.cooldownSec,
        restSec: s.restSec,
        roundsDone: s.roundsDone,
        roundsEstimated: s.roundsEstimated,
        imported: s.imported,
        rpe: s.rpe,
        limitingExercise:
            s.limitingExerciseId == null ? null : names[s.limitingExerciseId],
        context: s.context,
        notes: s.notes,
        outOfPlan: s.outOfPlan,
        incomplete: s.incomplete,
        plannedRounds: s.plannedRounds,
        pendingReview: s.pendingReview,
        mode: s.mode,
        extraReps: s.extraReps,
        techniqueOk: s.techniqueOk,
        fullRange: s.fullRange,
        recoveryOk: s.recoveryOk,
        lapsSec: lapDurations(rounds.map((r) => r.elapsedSec).toList()),
        roundWorkSec:
            measured ? rounds.map((r) => r.workSec!).toList() : const [],
        roundRestSec:
            measured ? rounds.map((r) => r.restSec!).toList() : const [],
        sets: [
          for (final x in sets)
            SetEntry(
              exercise: names[x.exerciseId] ?? '?',
              setIndex: x.setIndex,
              reps: x.reps,
              split: x.split,
              splitDetail: x.splitDetail,
              toFailure: x.toFailure,
              loadKg: x.loadKg,
              variant: x.variant,
              rir: x.rir,
            ),
        ],
      );
      if (s.date.compareTo(f) < 0) {
        sessionsBefore[s.type] = entry;
      } else {
        sessions.add(entry);
      }
    }

    final maxBefore = db.sessions.roundsDone.max();
    final prevRecord = await (db.selectOnly(db.sessions)
          ..addColumns([maxBefore])
          ..where(
              db.sessions.date.isSmallerThanValue(f) & db.countedCircuitRounds))
        .map((r) => r.read(maxBefore))
        .getSingle();

    final roundsBefore = await TrainingRepository(db, ExerciseRepository(db))
        .lastRoundsBefore(from);

    final football = await (db.select(db.footballGames)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();
    final steps = await (db.select(db.dailySteps)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();
    final sleep = await (db.select(db.sleepLogs)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();
    final knees = await (db.select(db.morningChecks)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();
    final benchmarks = await (db.select(db.mobilityBenchmarks)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();

    final meals = await nutrition.range(from, to);

    final weights = await (db.select(db.bodyWeights)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();
    final baselineWeight = await (db.select(db.bodyWeights)
          ..where((x) => x.date.isSmallerOrEqualValue(t))
          ..orderBy([
            (x) => OrderingTerm(expression: x.date),
            (x) => OrderingTerm(expression: x.id)
          ])
          ..limit(1))
        .getSingleOrNull();

    final measures = await (db.select(db.measurements)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();
    // Línea base: la primera toma de cada sitio, en una sola consulta.
    final baseline = <MeasureSite, MeasurementEntry>{};
    // La línea base es la primera toma **en ayunas** de cada sitio (§16.10):
    // una tomada después de cenar no es comparable. Sin ninguna en ayunas,
    // la primera que haya.
    final allMeasures = await (db.select(db.measurements)
          ..where((x) => x.date.isSmallerOrEqualValue(t))
          ..orderBy([
            (x) => OrderingTerm(expression: x.date),
            (x) => OrderingTerm(expression: x.id)
          ]))
        .get();
    for (final m in allMeasures.where((m) => m.fasted)) {
      baseline.putIfAbsent(m.site, () => _measure(m));
    }
    for (final m in allMeasures) {
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

    final closed = await (db.select(db.closedDays)
          ..where((x) => x.date.isBetweenValues(f, t)))
        .get();

    final span = daysBetween(from, to) + 1;
    final previous = withPrevious
        ? await load(addDays(from, -span), addDays(from, -1),
            today: today, withPrevious: false)
        : null;

    // Recuperación activa (§19.17): solo en el informe de la semana; cada día
    // relee la carga, así que no se calcula para rangos largos.
    final recovery = withPrevious && span <= 14
        ? await ReadinessRepository(db).week(from, to)
        : null;

    // Misma cadena que el Plan B de Hoy, al cierre del periodo (plan 039).
    final legChains = withPrevious ? await LegChainRepository(db).chains(to) : null;
    // Sólo el rango pedido; la semana anterior no los muestra.
    final tests = withPrevious
        ? await _tests(from, to, span, today ?? DateTime.now())
        : _noTests;

    return ReportInput(
      kneeStairs: {for (final row in knees) parseDay(row.date): row.kneeStairs},
      testAgenda: tests.agenda,
      testAttempts: tests.attempts,
      testResults: tests.results,
      benchmarkSchedule: tests.benchmarks,
      mobilityBenchmarks: [
        for (final row in benchmarks)
          '${row.date} · ${row.item}${row.side == null ? '' : ' (${row.side})'}: '
              '${row.value ?? (row.touches == null ? 'sin dato' : row.touches! ? 'sí' : 'no')} '
              '· condiciones: ${row.conditions ?? 'desconocidas'}'
      ],
      recovery: recovery,
      legChains: legChains,
      programStart: start,
      rangeStart: from,
      rangeEnd: to,
      today: today ?? DateTime.now(),
      targets: profile.targets,
      planVersions: planInfos,
      sessions: sessions,
      previousRoundsRecord: prevRecord,
      roundsBeforeRange: roundsBefore,
      sessionsBeforeRange: sessionsBefore,
      football: [
        for (final g in football)
          FootballEntry(
            date: parseDay(g.date),
            format: g.format,
            minutes: g.minutes,
            steps: g.steps,
            intensity: g.intensity,
            fatigueAfter: g.fatigueAfter,
            knock: g.knock,
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
      weightsInRange: [
        for (final w in weights)
          WeightEntry(date: parseDay(w.date), kg: w.kg, fasted: w.fasted)
      ],
      baselineWeight: baselineWeight == null
          ? null
          : WeightEntry(
              date: parseDay(baselineWeight.date),
              kg: baselineWeight.kg,
              fasted: baselineWeight.fasted),
      measurementsInRange: measures.map(_measure).toList(),
      baselineMeasurements: baseline,
      measurementDatesBefore: datesBefore,
      closedDays: {for (final c in closed) c.date},
      steps: {for (final s in steps) parseDay(s.date): s.steps},
      sleep: {for (final s in sleep) parseDay(s.date): s.hours},
      mobility: mobility,
      holdExercises: {
        // El Tabata (flexiones, sentadillas… 8 × 20 s) va por tiempo en el
        // plan, pero se anotan repeticiones: no son aguantes.
        for (final pe in await (db.select(db.planExercises)
              ..where((x) =>
                  x.holdSecMin.isNotNull() &
                  (x.block.isNull() | x.block.equals(tabataBlock).not())))
            .get())
          if (names[pe.exerciseId] case final name?) name,
        // Las escaleras de core (§19.10) no están en el plan guardado.
        hollowHold,
        for (final l in allLadders)
          for (final s in l.steps)
            if (s.holdMin != null) s.exercise,
      },
      dataStart: await firstDataDay(db),
      goals: await GoalRepository(db).history(),
      perSideExercises: {
        for (final pe in await (db.select(db.planExercises)
              ..where((x) => x.perSide.equals(true)))
            .get())
          if (names[pe.exerciseId] case final name?) name,
        for (final l in allLadders)
          for (final s in l.steps)
            if (s.perSide) s.exercise,
      },
      previous: previous,
      supplements: await SupplementRepository(db).entries(),
      notes: notes.length <= 1
          ? notes.firstOrNull?.body
          : notes
              .map((n) => '**Semana ${n.weekIndex}:** ${n.body}')
              .join('\n\n'),
    );
  }

  static const _noTests = (
    agenda: <TestAgendaEntry>[],
    attempts: <TestAttemptEntry>[],
    results: <TestResult>[],
    benchmarks: <BenchmarkScheduleEntry>[],
  );

  /// Tests y benchmarks del bloque v3.1/v3.2 que toca el rango (§19.11,
  /// §19.13): la misma agenda efectiva que Hoy y los avisos, los intentos con
  /// su sesión y todos los resultados hasta el final del rango para comparar
  /// cada intento con su línea base. Rangos de más de 9 semanas no leen la
  /// agenda día a día.
  Future<
      ({
        List<TestAgendaEntry> agenda,
        List<TestAttemptEntry> attempts,
        List<TestResult> results,
        List<BenchmarkScheduleEntry> benchmarks,
      })> _tests(DateTime from, DateTime to, int span, DateTime today) async {
    final f = dateOnly(from), t = dateOnly(to);
    bool inRange(DateTime d) => !d.isBefore(f) && !d.isAfter(t);
    final agenda = <TestAgendaEntry>[];
    final benchmarks = <BenchmarkScheduleEntry>[];
    if (span <= 63) {
      final exercises = ExerciseRepository(db);
      final plan = PlanRepository(db, exercises);
      final training = TrainingRepository(db, exercises);
      final blocks = <String, (String, DateTime, TestProtocolId)>{};
      for (var d = f; !d.isAfter(t); d = addDays(d, 1)) {
        final v3 = await training.blockDay(await plan.dayFor(d), d);
        if (v3 == null || !v3.isV31) continue;
        final start = addDays(d, -(d.weekday - 1) - (v3.week - 1) * 7);
        blocks['${v3.scheme}|${dayKey(start)}'] = (
          v3.scheme,
          start,
          v3.isV32 ? TestProtocolId.v32_13 : TestProtocolId.v31_12
        );
      }
      for (final (scheme, start, protocol) in blocks.values) {
        for (final e in await ReadinessRepository(db)
            .testAgenda(scheme: scheme, blockStart: start, protocol: protocol)) {
          if (!inRange(e.planned) &&
              !inRange(e.date) &&
              !(e.kneePushedFrom != null && inRange(e.kneePushedFrom!))) {
            continue;
          }
          final gate = e.gate!;
          final pushed = e.kneePushedFrom;
          agenda.add(TestAgendaEntry(
            round: e.round,
            part: e.part,
            planned: e.planned,
            date: e.date,
            moves: e.moves,
            maxMoves: maxTestMoves,
            condition: pushed != null
                ? 'escaleras ${e.kneeStairsThen}/10 el ${weekdayShort(pushed.weekday).toLowerCase()} ${formatShort(pushed)}: pasó a la siguiente sesión de piernas'
                : !inRange(e.date)
                ? null
                : gate.status == TestDayStatus.stairsUnknown &&
                        e.date.isBefore(dateOnly(today))
                    ? 'escaleras sin anotar ese día'
                    : gate.label,
          ));
        }
        if (protocol != TestProtocolId.v32_13) continue;
        for (final m in await MobilityBenchmarkRepository(db).schedule(
            scheme: scheme,
            blockStart: start,
            protocol: protocol,
            from: f,
            to: t,
            // Lo medido después del rango o de hoy no completa una toma.
            asOf: t.isAfter(dateOnly(today)) ? dateOnly(today) : t)) {
          benchmarks.add(BenchmarkScheduleEntry(
            planned: m.planned,
            date: m.date,
            withMovedLegTest: m.withMovedLegTest,
            missing: m.missing,
            total: mobilityBenchmarkItems.length + 1,
          ));
        }
      }
    }
    final sessions = {
      for (final r in await (db.selectOnly(db.sessions)
            ..addColumns([db.sessions.id]))
          .get())
        r.read(db.sessions.id)!
    };
    final attempts = [
      for (final a in await (db.select(db.fitnessTestAttempts)
            ..where((x) => x.date.isBetweenValues(dayKey(f), dayKey(t)))
            ..orderBy([
              (x) => OrderingTerm(expression: x.date),
              (x) => OrderingTerm(expression: x.id)
            ]))
          .get())
        if (TestPart.values.where((p) => p.name == a.part).firstOrNull
            case final part?)
          TestAttemptEntry(
            id: a.id,
            date: parseDay(a.date),
            round: a.round,
            part: part,
            protocolId: a.protocolId,
            sessionLinked: a.sessionId != null && sessions.contains(a.sessionId),
          ),
    ];
    final results = [
      for (final r in await FitnessTestRepository(db).all())
        if (r.date == null || !dateOnly(r.date!).isAfter(t)) r
    ];
    return (
      agenda: agenda,
      attempts: attempts,
      results: results,
      benchmarks: benchmarks
    );
  }

  MeasurementEntry _measure(MeasurementRow r) => MeasurementEntry(
      date: parseDay(r.date),
      site: r.site,
      valueCm: r.valueCm,
      fasted: r.fasted);
}
