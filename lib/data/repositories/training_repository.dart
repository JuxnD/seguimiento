import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/session_math.dart';
import '../database.dart';
import 'exercise_repository.dart';

class SetDraft {
  SetDraft({
    required this.exercise,
    this.reps = 0,
    this.split = false,
    this.splitDetail,
    this.toFailure = false,
    this.loadKg,
  });

  String exercise;
  int reps;
  bool split;
  String? splitDetail;
  bool toFailure;

  /// Carga externa (mochila, garrafas). null = peso corporal.
  double? loadKg;
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
      sets: [
        for (final s in sets)
          SetDraft(
            exercise: names[s.exerciseId] ?? '?',
            reps: s.reps,
            split: s.split,
            splitDetail: s.splitDetail,
            toFailure: s.toFailure,
            loadKg: s.loadKg,
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
