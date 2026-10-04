import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/nutrition.dart';
import '../../domain/plan_v3.dart';
import '../../domain/progress.dart';
import '../../domain/steps.dart';
import '../database.dart';
import 'exercise_repository.dart';
import 'nutrition_repository.dart';
import 'plan_repository.dart';
import 'profile_repository.dart';
import 'training_repository.dart';

/// Todo lo que la pantalla Hoy necesita, resuelto de una vez.
class TodayDashboard {
  const TodayDashboard({
    required this.date,
    required this.weekIndex,
    required this.dayType,
    required this.planVersion,
    required this.planSummary,
    required this.mainExercises,
    this.blockExercises = const [],
    required this.targetRounds,
    required this.roundsDone,
    required this.sessionsToday,
    this.footballToday,
    this.hardFootballYesterday,
    required this.streak,
    required this.macros,
    required this.proteinMin,
    required this.proteinMax,
    required this.kcalTarget,
    this.stepsToday,
    this.stepsGoal,
    required this.roundsRecord,
    this.recordSuspect,
    this.recordDate,
    this.v3,
    this.v3Suggestion,
    required this.measurement,
    this.proposal,
  });

  final DateTime date;
  final int weekIndex;
  final DayType dayType;
  final int? planVersion;

  /// "6 rondas · Dominadas 5 · Flexiones 10 · Sentadillas 15".
  final String? planSummary;
  final List<String> mainExercises;

  /// Bloques extra del día (core, hombro…), una línea por variante:
  /// "Core A: Elevación de piernas colgado 3×8–12 · Hollow body hold 2×20–40 s".
  final List<String> blockExercises;
  final int? targetRounds;

  /// Rondas de la sesión de hoy, si ya se registró.
  final int? roundsDone;
  final int sessionsToday;

  /// Partido registrado hoy. Va aparte de las sesiones (`FootballGames`), pero
  /// para Hoy y la racha cuenta igual que entrenar.
  final FootballGameRow? footballToday;

  /// Partido de ayer si fue intenso (≥ 8) o hubo golpe: hoy se baja la carga.
  final FootballGameRow? hardFootballYesterday;
  final int streak;
  final Macros macros;
  final int proteinMin;
  final int proteinMax;
  final int kcalTarget;

  /// Pasos anotados hoy; null si aún no.
  final int? stepsToday;

  /// Meta de pasos de hoy; null el fin de semana.
  final int? stepsGoal;

  /// Mejor marca de rondas hasta hoy.
  final int? roundsRecord;

  /// Sesión que da el récord pero cayó en un día que el plan no marca como
  /// circuito: casi siempre un día de bloques guardado como circuito.
  final RecordSuspect? recordSuspect;

  /// Primer día en que se hizo el récord vigente: si es reciente, Hoy lo
  /// celebra (§16.9).
  final DateTime? recordDate;

  bool get recentRecord => recordDate != null && daysBetween(recordDate!, date) <= 6;

  /// Día dentro del Plan v3 (semana, fase, descarga). null fuera del v3.
  final V3Day? v3;

  /// Lunes desde el que conviene activar el v3: la última progresión fue de
  /// 10 rondas limpias y todavía no hay v3 (§18). null si no toca.
  final DateTime? v3Suggestion;

  /// Cuándo toca medir. null = sin línea base ni fecha acordada.
  final MeasurementDue? measurement;

  /// Día de progresión: lo que propone la regla. La meta del viernes sale de
  /// aquí y no del plan, que tiene un número fijo y no avanzaba (§16.9).
  final ProgressionProposal? proposal;

  /// Lo del día está hecho. Un partido lo cumple en días de fútbol o descanso;
  /// en un día de entrenamiento no reemplaza la sesión del plan (la racha sí
  /// lo cuenta).
  bool get trained => sessionsToday > 0 || (footballToday != null && !dayType.isTraining);
  double get proteinProgress => goalProgress(macros.protein, proteinMin);
  double get kcalProgress => goalProgress(macros.kcal, kcalTarget);
  double get stepsProgress => stepsGoal == null ? ((stepsToday ?? 0) > 0 ? 1 : 0) : goalProgress(stepsToday ?? 0, stepsGoal!);
  double get roundsProgress => goalProgress(roundsDone ?? 0, targetRounds ?? 0);
}

class RecordSuspect {
  const RecordSuspect({required this.sessionId, required this.date, required this.plannedType});

  final int sessionId;
  final DateTime date;
  final DayType plannedType;
}

class DashboardRepository {
  DashboardRepository(this.db, this.plan, this.nutrition, this.profile);

  final AppDatabase db;
  final PlanRepository plan;
  final NutritionRepository nutrition;
  final ProfileRepository profile;

  Future<TodayDashboard> today({DateTime? now}) async {
    final date = dateOnly(now ?? DateTime.now());
    final p = await profile.get();
    final view = await plan.dayFor(date);
    final type = view?.day.type ?? DayType.descanso;
    final v3 = view != null && view.scheme == v3Scheme && view.validFrom != null ? v3Day(view.validFrom!, date) : null;
    final proposal = type == DayType.progresion
        ? await TrainingRepository(db, ExerciseRepository(db)).progressionProposal(date)
        : null;

    final sessions = await (db.select(db.sessions)
          ..where((t) => t.date.equals(dayKey(date)) & db.trainingSessions))
        .get();
    final meals = await nutrition.range(date, date);
    final football = await _lastGame(date);
    final yesterday = await _lastGame(addDays(date, -1));

    final maxRounds = db.sessions.roundsDone.max();
    final record = await (db.selectOnly(db.sessions)
          ..addColumns([maxRounds])
          ..where(db.countedCircuitRounds))
        .map((r) => r.read(maxRounds))
        .getSingle();

    final lastMeasurement = await (db.select(db.measurements)
          ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();

    return TodayDashboard(
      date: date,
      weekIndex: weekIndexFor(p.programStart, date),
      dayType: type,
      planVersion: view?.versionNumber,
      planSummary: view == null ? null : _summary(view.day),
      mainExercises: view == null
          ? const []
          : view.day.main.map((e) => '${e.name} ${e.targetLabel}'.trim()).toList(),
      blockExercises: view == null ? const [] : blockLines(view.day),
      targetRounds: proposal?.rounds ?? view?.day.targetRounds,
      proposal: proposal,
      roundsDone: sessions.map((s) => s.roundsDone).whereType<int>().firstOrNull,
      sessionsToday: sessions.length,
      footballToday: football,
      hardFootballYesterday: yesterday != null && isHardGame(yesterday) ? yesterday : null,
      streak: await _streak(date),
      macros: Macros.sum(meals.map((m) => m.macros)),
      proteinMin: p.proteinMin,
      proteinMax: p.proteinMax,
      kcalTarget: p.kcalTarget,
      stepsToday: (await (db.select(db.dailySteps)..where((t) => t.date.equals(dayKey(date)))).getSingleOrNull())?.steps,
      stepsGoal: stepsGoalFor(date, p.stepsTarget),
      roundsRecord: record,
      recordSuspect: record == null ? null : await _recordSuspect(record),
      recordDate: record == null ? null : await _recordDate(record),
      v3: v3,
      v3Suggestion: v3 == null ? await _v3Suggestion(date) : null,
      measurement: measurementDue(
        today: date,
        lastMeasurement: lastMeasurement == null ? null : parseDay(lastMeasurement.date),
        agreed: p.nextMeasurementDate == null ? null : parseDay(p.nextMeasurementDate!),
        minDays: p.measureIntervalDays,
        maxDays: p.measureIntervalMaxDays,
      ),
    );
  }

  /// La sesión del récord, si el plan de ese día no era de circuito.
  /// 10 rondas limpias en la última progresión y sin v3 todavía: se propone
  /// el lunes siguiente a esa sesión (o el próximo, si ya pasó).
  Future<DateTime?> _v3Suggestion(DateTime today) async {
    if (await plan.hasScheme(v3Scheme)) return null;
    final p = await TrainingRepository(db, ExerciseRepository(db)).progressionProposal(addDays(today, 1));
    if (p == null || !p.canProgress || p.lastRounds < 10 || p.lastDate == null) return null;
    final afterSession = nextMonday(addDays(p.lastDate!, 1));
    final upcoming = nextMonday(today);
    return afterSession.isBefore(upcoming) ? upcoming : afterSession;
  }

  Future<DateTime?> _recordDate(int record) async {
    final row = await (db.select(db.sessions)
          ..where((t) => db.countedCircuitRounds & t.roundsDone.equals(record))
          ..orderBy([(t) => OrderingTerm(expression: t.date)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : parseDay(row.date);
  }

  Future<RecordSuspect?> _recordSuspect(int record) async {
    final rows = await (db.select(db.sessions)
          ..where((t) => db.countedCircuitRounds & t.roundsDone.equals(record))
          ..orderBy([(t) => OrderingTerm(expression: t.date)]))
        .get();
    for (final s in rows) {
      final date = parseDay(s.date);
      final planned = (await plan.dayFor(date))?.day.type;
      if (planned != null && !planned.isCircuit) {
        return RecordSuspect(sessionId: s.id, date: date, plannedType: planned);
      }
    }
    return null;
  }

  /// Si el día anterior a `day` hubo un partido intenso o con golpe.
  Future<bool> hardGameBefore(DateTime day) async {
    final game = await _lastGame(addDays(dateOnly(day), -1));
    return game != null && isHardGame(game);
  }

  Future<FootballGameRow?> _lastGame(DateTime day) => (db.select(db.footballGames)
        ..where((t) => t.date.equals(dayKey(day)))
        ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])
        ..limit(1))
      .getSingleOrNull();

  String _summary(PlanDayDraft day) {
    final rounds = day.targetRounds == null ? null : '${day.targetRounds} rondas';
    final exercises = day.main.map((e) => '${e.name} ${e.targetLabel}'.trim()).join(' · ');
    return [if (rounds != null) rounds, if (exercises.isNotEmpty) exercises].join(' · ');
  }

  /// Días seguidos entrenando, sin que el descanso planificado los rompa. Un
  /// partido de fútbol cuenta como día entrenado.
  Future<int> _streak(DateTime today) async {
    final rows = await (db.select(db.sessions)..where((_) => db.trainingSessions)).get();
    final games = await db.select(db.footballGames).get();
    final dates = {...rows.map((s) => s.date), ...games.map((g) => g.date)};
    final versions = await plan.versions();
    if (versions.isEmpty) return dates.contains(dayKey(today)) ? 1 : 0;

    // Mapa weekday → tipo por versión, para no recargar el plan por día.
    final byVersion = <int, Map<int, DayType>>{};
    for (final v in versions) {
      final days = await (db.select(db.planDays)..where((t) => t.planVersionId.equals(v.id))).get();
      byVersion[v.id] = {for (final d in days) d.weekday: d.type};
    }
    DayType typeFor(DateTime day) {
      PlanVersionRow? active;
      for (final v in versions) {
        if (!parseDay(v.validFrom).isAfter(day)) active = v;
      }
      if (active == null) return DayType.descanso;
      return byVersion[active.id]?[day.weekday] ?? DayType.descanso;
    }

    return currentStreak(
      today: today,
      trainingDates: dates,
      isRestDay: (d) => !typeFor(d).isTraining,
    );
  }
}

/// Un partido que pide bajar la sesión del día siguiente: intensidad 8 o más,
/// o terminó con golpe o molestia.
bool isHardGame(FootballGameRow game) => (game.intensity ?? 0) >= 8 || game.knock == true;

/// Una línea por bloque y variante: "Core A: Elevación de piernas colgado
/// 3×8–12 · Hollow body hold 2×20–40 s".
List<String> blockLines(PlanDayDraft day) {
  final groups = <String, List<PlanExerciseDraft>>{};
  for (final e in day.exercises.where((e) => e.block != null)) {
    final block = e.block![0].toUpperCase() + e.block!.substring(1);
    groups.putIfAbsent(e.variant == null ? block : '$block ${e.variant}', () => []).add(e);
  }
  return [
    for (final g in groups.entries) '${g.key}: ${g.value.map((e) => '${e.name} ${e.targetLabel}'.trim()).join(' · ')}',
  ];
}
