import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/nutrition.dart';
import '../../domain/progress.dart';
import '../../domain/steps.dart';
import '../database.dart';
import 'nutrition_repository.dart';
import 'plan_repository.dart';
import 'profile_repository.dart';

/// Todo lo que la pantalla Hoy necesita, resuelto de una vez.
class TodayDashboard {
  const TodayDashboard({
    required this.date,
    required this.weekIndex,
    required this.dayType,
    required this.planVersion,
    required this.planSummary,
    required this.mainExercises,
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
    required this.measurement,
  });

  final DateTime date;
  final int weekIndex;
  final DayType dayType;
  final int? planVersion;

  /// "6 rondas · Dominadas 5 · Flexiones 10 · Sentadillas 15".
  final String? planSummary;
  final List<String> mainExercises;
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

  /// Cuándo toca medir. null = sin línea base ni fecha acordada.
  final MeasurementDue? measurement;

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
      targetRounds: view?.day.targetRounds,
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
