import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/plan_v3.dart';
import '../../domain/progress.dart';
import '../../domain/session_math.dart';
import '../database.dart';
import 'exercise_repository.dart';
import 'plan_repository.dart';

class SetDraft {
  SetDraft({
    required this.exercise,
    this.reps = 0,
    this.split = false,
    this.splitDetail,
    this.toFailure = false,
    this.loadKg,
    this.variant,
    this.rir,
  });

  String exercise;
  int reps;
  bool split;
  String? splitDetail;
  bool toFailure;

  /// Carga externa (mochila, garrafas). null = peso corporal.
  double? loadKg;

  /// Variante de la progresión ("arquero", "pies elevados"). null = la del plan.
  String? variant;

  /// Repeticiones en reserva (0–5). null = no se anotó.
  int? rir;
}

class SessionDraft {
  SessionDraft({
    this.id,
    required this.date,
    this.startTime,
    this.type = SessionType.circuito,
    this.planDayId,
    this.totalSec = 0,
    this.warmupSec = 0,
    this.cooldownSec = 0,
    this.restSec = 0,
    this.roundsDone,
    this.roundsEstimated = false,
    this.rpe,
    this.limitingExercise,
    this.context,
    this.notes,
    this.techniqueOk,
    this.fullRange,
    this.recoveryOk,
    this.outOfPlan = false,
    this.incomplete = false,
    this.plannedRounds,
    this.pendingReview = false,
    this.mode,
    this.extraReps,
    List<SetDraft>? sets,
    List<int>? roundMarksSec,
    List<int>? roundRestSec,
  })  : sets = sets ?? [],
        roundMarksSec = roundMarksSec ?? [],
        roundRestSec = roundRestSec ?? [];

  int? id;
  DateTime date;
  String? startTime;
  SessionType type;
  int? planDayId;
  int totalSec;
  int warmupSec;
  int cooldownSec;

  /// Descansos sumados: van aparte del trabajo neto.
  int restSec;
  int? roundsDone;
  bool roundsEstimated;
  int? rpe;
  String? limitingExercise;
  String? context;
  String? notes;

  /// El tipo registrado no coincide con el plan de ese día.
  bool outOfPlan;

  /// Se cerró antes de completar el plan.
  bool incomplete;
  int? plannedRounds;

  // Condiciones de la regla de progresión (null = sin registrar).
  bool? techniqueOk;
  bool? fullRange;
  bool? recoveryOk;

  /// Guardada sola al terminar el cronómetro; falta revisarla (RPE).
  bool pendingReview;

  /// Resistencia v3: 'cindy', 'tabata' o 'porTiempo'.
  String? mode;

  /// AMRAP: repeticiones de la ronda que quedó a medias.
  int? extraReps;

  /// En orden de ejecución; el índice de serie se calcula por ejercicio.
  final List<SetDraft> sets;

  /// Marcas acumuladas del contador (s desde el inicio del circuito).
  final List<int> roundMarksSec;

  /// Descanso después de cada ronda, en paralelo a `roundMarksSec`. Vacío si
  /// no se midió (contador libre, sesiones anteriores al esquema 8).
  final List<int> roundRestSec;

  /// Trabajo de cada ronda, sin descansos. null si no hay descansos medidos.
  List<int>? get roundWorkSec => roundWork(roundMarksSec, roundRestSec);

  /// Trabajo neto: sin calentamiento, enfriamiento ni descansos.
  int get netSec =>
      circuitNetSec(totalSec: totalSec, warmupSec: warmupSec, cooldownSec: cooldownSec, restSec: restSec);

  /// Tiempo de circuito con descansos: sobre esto se miden las vueltas.
  int get spanSec => circuitSpanSec(totalSec: totalSec, warmupSec: warmupSec, cooldownSec: cooldownSec);
}

/// Fila de lista: sesión con conteos para mostrar sin abrirla.
class SessionSummary {
  SessionSummary(this.row, this.splitSets);

  final SessionRow row;
  final int splitSets;
}

class TrainingRepository {
  TrainingRepository(this.db, this.exercises);

  final AppDatabase db;
  final ExerciseRepository exercises;

  // ---------- Sesiones ----------

  Stream<List<SessionSummary>> watchRecent({int limit = 60}) {
    final splitCount = db.sessionSets.id.count(filter: db.sessionSets.split.equals(true));
    final q = db.select(db.sessions).join([
      leftOuterJoin(db.sessionSets, db.sessionSets.sessionId.equalsExp(db.sessions.id)),
    ])
      ..addColumns([splitCount])
      ..groupBy([db.sessions.id])
      ..orderBy([
        OrderingTerm(expression: db.sessions.date, mode: OrderingMode.desc),
        OrderingTerm(expression: db.sessions.startTime, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) =>
        rows.map((r) => SessionSummary(r.readTable(db.sessions), r.read(splitCount) ?? 0)).toList());
  }

  Future<int> save(SessionDraft d) => db.transaction(() async {
        final limitingId = (d.limitingExercise == null || d.limitingExercise!.trim().isEmpty)
            ? null
            : await exercises.getOrCreate(d.limitingExercise!);
        final data = SessionsCompanion(
          date: Value(dayKey(d.date)),
          startTime: Value(d.startTime),
          type: Value(d.type),
          planDayId: Value(d.planDayId),
          totalSec: Value(d.totalSec),
          warmupSec: Value(d.warmupSec),
          cooldownSec: Value(d.cooldownSec),
          restSec: Value(d.restSec),
          roundsDone: Value(d.roundsDone),
          roundsEstimated: Value(d.roundsEstimated),
          rpe: Value(d.rpe),
          limitingExerciseId: Value(limitingId),
          context: Value(_blankToNull(d.context)),
          notes: Value(_blankToNull(d.notes)),
          outOfPlan: Value(d.outOfPlan),
          incomplete: Value(d.incomplete),
          plannedRounds: Value(d.plannedRounds),
          techniqueOk: Value(d.techniqueOk),
          fullRange: Value(d.fullRange),
          recoveryOk: Value(d.recoveryOk),
          pendingReview: Value(d.pendingReview),
          mode: Value(d.mode),
          extraReps: Value(d.extraReps),
        );
        final int id;
        if (d.id == null) {
          id = await db.into(db.sessions).insert(data);
        } else {
          id = d.id!;
          await (db.update(db.sessions)..where((t) => t.id.equals(id))).write(data);
          await (db.delete(db.sessionSets)..where((t) => t.sessionId.equals(id))).go();
          await (db.delete(db.sessionRounds)..where((t) => t.sessionId.equals(id))).go();
        }

        final perExercise = <int, int>{};
        for (final s in d.sets.where((s) => s.exercise.trim().isNotEmpty)) {
          final exId = await exercises.getOrCreate(s.exercise);
          final idx = perExercise[exId] = (perExercise[exId] ?? 0) + 1;
          await db.into(db.sessionSets).insert(SessionSetsCompanion.insert(
                sessionId: id,
                exerciseId: exId,
                setIndex: idx,
                reps: s.reps,
                split: Value(s.split),
                splitDetail: Value(s.split ? _blankToNull(s.splitDetail) : null),
                toFailure: Value(s.toFailure),
                loadKg: Value(s.loadKg),
                variant: Value(_blankToNull(s.variant)),
                rir: Value(s.rir),
              ));
        }
        final work = d.roundWorkSec;
        for (var i = 0; i < d.roundMarksSec.length; i++) {
          await db.into(db.sessionRounds).insert(SessionRoundsCompanion.insert(
                sessionId: id,
                roundIndex: i + 1,
                elapsedSec: d.roundMarksSec[i],
                workSec: Value(work?[i]),
                restSec: Value(work == null ? null : d.roundRestSec[i]),
              ));
        }
        d.id = id;
        return id;
      });

  Future<SessionDraft> load(int id) async {
    final r = await (db.select(db.sessions)..where((t) => t.id.equals(id))).getSingle();
    final names = await exercises.namesById();
    final sets = await (db.select(db.sessionSets)
          ..where((t) => t.sessionId.equals(id))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    final rounds = await (db.select(db.sessionRounds)
          ..where((t) => t.sessionId.equals(id))
          ..orderBy([(t) => OrderingTerm(expression: t.roundIndex)]))
        .get();
    return SessionDraft(
      id: r.id,
      date: parseDay(r.date),
      startTime: r.startTime,
      type: r.type,
      planDayId: r.planDayId,
      totalSec: r.totalSec,
      warmupSec: r.warmupSec,
      cooldownSec: r.cooldownSec,
      restSec: r.restSec,
      roundsDone: r.roundsDone,
      roundsEstimated: r.roundsEstimated,
      rpe: r.rpe,
      limitingExercise: r.limitingExerciseId == null ? null : names[r.limitingExerciseId],
      context: r.context,
      notes: r.notes,
      outOfPlan: r.outOfPlan,
      incomplete: r.incomplete,
      plannedRounds: r.plannedRounds,
      techniqueOk: r.techniqueOk,
      fullRange: r.fullRange,
      recoveryOk: r.recoveryOk,
      pendingReview: r.pendingReview,
      mode: r.mode,
      extraReps: r.extraReps,
      sets: [
        for (final s in sets)
          SetDraft(
            exercise: names[s.exerciseId] ?? '?',
            reps: s.reps,
            split: s.split,
            splitDetail: s.splitDetail,
            toFailure: s.toFailure,
            loadKg: s.loadKg,
            variant: s.variant,
            rir: s.rir,
          ),
      ],
      roundMarksSec: rounds.map((x) => x.elapsedSec).toList(),
      roundRestSec: rounds.every((x) => x.restSec != null) ? rounds.map((x) => x.restSec!).toList() : null,
    );
  }

  /// Mejor marca de rondas en circuito, sin contar una sesión concreta
  /// (la recién guardada, para saber si acaba de romper el récord).
  Future<int?> bestRounds({int? excludeSessionId}) async {
    final best = db.sessions.roundsDone.max();
    final query = db.selectOnly(db.sessions)..addColumns([best]);
    query.where(excludeSessionId == null
        ? db.countedCircuitRounds
        : db.countedCircuitRounds & db.sessions.id.equals(excludeSessionId).not());
    return query.map((r) => r.read(best)).getSingle();
  }

  /// La sesión anterior del mismo tipo (antes de `date`), con el trabajo de
  /// cada ronda (o sus vueltas, si es anterior al esquema 8), para comparar al
  /// cerrar. null si es la primera.
  Future<(DateTime, int?, List<int>)?> previousOfType(SessionType type, DateTime date) async {
    final row = await (db.select(db.sessions)
          ..where((t) => t.type.equalsValue(type) & t.date.isSmallerThanValue(dayKey(date)))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    final rounds = await (db.select(db.sessionRounds)
          ..where((t) => t.sessionId.equals(row.id))
          ..orderBy([(t) => OrderingTerm(expression: t.roundIndex)]))
        .get();
    final work = rounds.every((r) => r.workSec != null)
        ? rounds.map((r) => r.workSec!).toList()
        : lapDurations(rounds.map((r) => r.elapsedSec).toList());
    return (parseDay(row.date), row.roundsDone, work);
  }

  /// Últimas rondas hechas antes de una fecha, por tipo de circuito.
  Future<Map<SessionType, int>> lastRoundsBefore(DateTime date) async {
    final out = <SessionType, int>{};
    for (final type in SessionType.values.where((t) => t.isCircuit)) {
      final row = await (db.select(db.sessions)
            ..where((t) => t.date.isSmallerThanValue(dayKey(date)) & t.type.equalsValue(type))
            ..where((t) => t.roundsDone.isNotNull())
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();
      if (row?.roundsDone != null) out[type] = row!.roundsDone!;
    }
    return out;
  }

  /// Última sesión de un tipo antes de `date`, completa (con series).
  Future<SessionDraft?> lastOfType(SessionType type, DateTime date) async {
    final row = await (db.select(db.sessions)
          ..where((t) => t.type.equalsValue(type) & t.date.isSmallerThanValue(dayKey(date)))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : load(row.id);
  }

  /// Propuesta de la regla de progresión para el intento de `date`, a partir
  /// de la última sesión de progresión anterior. Hoy y el cronómetro leen de
  /// aquí para que la meta sea la misma en las dos pantallas.
  Future<ProgressionProposal?> progressionProposal(DateTime date) async {
    final last = await lastOfType(SessionType.progresion, date);
    if (last == null) return null;
    return proposeProgression(
      lastRounds: last.roundsDone,
      lastPlanned: last.plannedRounds,
      lastDate: last.date,
      sessionId: last.id,
      anySplit: last.sets.any((s) => s.split),
      anyFailure: last.sets.any((s) => s.toFailure),
      techniqueOk: last.techniqueOk,
      fullRange: last.fullRange,
      recoveryOk: last.recoveryOk,
      incomplete: last.incomplete,
    );
  }

  /// Fecha de la primera progresión de 10 rondas o más que cumplió la regla
  /// de calidad, antes de `before`. Desde el viernes siguiente, el viernes del
  /// v3.1 deja el circuito y alterna Cindy y Tabata (§19.1).
  Future<DateTime?> firstCleanTen({DateTime? before}) async {
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.type.equalsValue(SessionType.progresion) &
              t.roundsDone.isBiggerOrEqualValue(10) &
              (before == null ? const Constant(true) : t.date.isSmallerThanValue(dayKey(before))))
          ..orderBy([(t) => OrderingTerm(expression: t.date)]))
        .get();
    for (final r in rows) {
      final s = await load(r.id);
      final p = proposeProgression(
        lastRounds: s.roundsDone,
        lastPlanned: s.plannedRounds,
        anySplit: s.sets.any((x) => x.split),
        anyFailure: s.sets.any((x) => x.toFailure),
        techniqueOk: s.techniqueOk,
        fullRange: s.fullRange,
        recoveryOk: s.recoveryOk,
        incomplete: s.incomplete,
      );
      if (p != null && p.canProgress) return s.date;
    }
    return null;
  }

  /// Día del bloque (v3 o v3.1) para el día del plan `view`. El viernes del
  /// v3.1 depende de si ya salieron 10 rondas limpias. null fuera del bloque.
  Future<V3Day?> blockDay(PlanDayView? view, DateTime date) async {
    if (view == null || !isBlockScheme(view.scheme) || view.validFrom == null) return null;
    final cleanTen =
        view.scheme == v31Scheme && date.weekday == DateTime.friday ? await firstCleanTen(before: date) : null;
    return v3Day(view.validFrom!, date, scheme: view.scheme!, cleanTen: cleanTen);
  }

  /// Series del ejercicio en la última sesión de fuerza del mismo día de la
  /// semana antes de `date` (el lunes se compara con el lunes: las dominadas
  /// del lunes van con mochila y las del jueves son supinas). Vacío si no hay.
  Future<List<SetDraft>> lastStrengthSets(String exercise, DateTime date) async {
    final exId = await exercises.idOf(exercise);
    if (exId == null) return const [];
    final circuit = SessionType.values.where((t) => t.isCircuit || t == SessionType.resistencia).map((t) => t.name);
    final rows = await (db.select(db.sessions)
          ..where((t) => t.date.isSmallerThanValue(dayKey(date)) & t.type.isNotIn(circuit))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(40))
        .get();
    for (final r in rows.where((r) => parseDay(r.date).weekday == date.weekday)) {
      final sets = await (db.select(db.sessionSets)
            ..where((t) => t.sessionId.equals(r.id) & t.exerciseId.equals(exId))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      if (sets.isEmpty) continue;
      return [
        for (final s in sets) SetDraft(exercise: exercise, reps: s.reps, loadKg: s.loadKg, variant: s.variant, rir: s.rir),
      ];
    }
    return const [];
  }

  /// Sesiones que se guardaron solas al terminar el cronómetro y aún no se
  /// revisan (falta el RPE). Las más recientes primero.
  Stream<List<SessionRow>> watchPendingReview() => (db.select(db.sessions)
        ..where((t) => t.pendingReview.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
      .watch();

  /// La sesión de ese tipo en ese día (la última si hay varias), o null.
  Future<int?> sessionsOn(DateTime date, SessionType type) async {
    final row = await (db.select(db.sessions)
          ..where((t) => t.date.equals(dayKey(date)) & t.type.equalsValue(type))
          ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.id;
  }

  /// Anota los tres criterios de calidad de una sesión ya guardada.
  Future<void> setProgressionCriteria(int id, {bool? techniqueOk, bool? fullRange, bool? recoveryOk}) =>
      (db.update(db.sessions)..where((t) => t.id.equals(id))).write(SessionsCompanion(
        techniqueOk: Value(techniqueOk),
        fullRange: Value(fullRange),
        recoveryOk: Value(recoveryOk),
      ));

  /// Última variante usada en un ejercicio, para proponerla de nuevo.
  Future<String?> lastVariant(String exercise) async {
    final exId = await exercises.idOf(exercise);
    if (exId == null) return null;
    final row = await (db.select(db.sessionSets)
          ..where((t) => t.exerciseId.equals(exId) & t.variant.isNotNull())
          ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.variant;
  }

  /// Última carga externa usada en un ejercicio, para proponerla de nuevo.
  Future<double?> lastLoad(String exercise) async {
    final exId = await exercises.idOf(exercise);
    if (exId == null) return null;
    final row = await (db.select(db.sessionSets)
          ..where((t) => t.exerciseId.equals(exId) & t.loadKg.isNotNull())
          ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.loadKg;
  }

  Future<void> delete(int id) => (db.delete(db.sessions)..where((t) => t.id.equals(id))).go();

  /// Duración media por ronda (incluye transición) en las últimas sesiones
  /// con contador. Base para estimar rondas cuando se pierde la cuenta.
  Future<int?> historicalMeanRoundSec({int lastSessions = 5}) async {
    final ids = await (db.selectOnly(db.sessionRounds, distinct: true)
          ..addColumns([db.sessionRounds.sessionId])
          ..orderBy([OrderingTerm(expression: db.sessionRounds.sessionId, mode: OrderingMode.desc)])
          ..limit(lastSessions))
        .map((r) => r.read(db.sessionRounds.sessionId)!)
        .get();
    if (ids.isEmpty) return null;
    final laps = <int>[];
    for (final id in ids) {
      final marks = await (db.select(db.sessionRounds)
            ..where((t) => t.sessionId.equals(id))
            ..orderBy([(t) => OrderingTerm(expression: t.roundIndex)]))
          .map((r) => r.elapsedSec)
          .get();
      laps.addAll(lapDurations(marks));
    }
    return meanSec(laps);
  }

  // ---------- Fútbol ----------

  Stream<List<FootballGameRow>> watchFootball({int limit = 60}) => (db.select(db.footballGames)
        ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)])
        ..limit(limit))
      .watch();

  Future<int> saveFootball(FootballGamesCompanion data) async {
    if (data.id.present) {
      await (db.update(db.footballGames)..where((t) => t.id.equals(data.id.value))).write(data);
      return data.id.value;
    }
    return db.into(db.footballGames).insert(data);
  }

  Future<void> deleteFootball(int id) => (db.delete(db.footballGames)..where((t) => t.id.equals(id))).go();
}

String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
