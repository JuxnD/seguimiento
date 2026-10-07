import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart';
import '../../domain/nutrition.dart';
import '../../domain/plan_v3.dart';
import '../../domain/progress.dart';
import '../../domain/recovery.dart';
import '../../domain/session_script.dart' show preBlocks, tabataBlock, warmupBlock;
import '../../domain/steps.dart';
import '../database.dart';
import 'exercise_repository.dart';
import 'fitness_test_repository.dart';
import 'nutrition_repository.dart';
import 'plan_repository.dart';
import 'profile_repository.dart';
import 'recovery_repository.dart';
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
    this.midweekGame = false,
    this.load = const LoadReading(todayLoad: 0, todayCount: 0, intenseStreak: 0),
    this.restingHrWarning,
    this.soreZones = const [],
    this.planB = false,
    this.fitnessTest,
  });

  /// Test de condición de hoy (§19.11): el lunes sustituye el tirón; el
  /// miércoles va antes de la sesión de piernas. null si hoy no toca.
  final ({int round, TestPart part, bool done})? fitnessTest;

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

  /// Lunes desde el que conviene activar el v3.1 (§19): el próximo, mientras
  /// no haya v3.1. null si no toca.
  final DateTime? v3Suggestion;

  /// Viernes metabólico del v3.1 con un partido entre semana: el partido lo
  /// reemplaza (§19.1).
  final bool midweekGame;

  /// Carga de hoy y días intensos seguidos (§16.15).
  final LoadReading load;

  /// Pulso en reposo alto 3 días seguidos (§19.6).
  final String? restingHrWarning;

  /// Zonas con una molestia que no baja en 3 días o sube (§16.15).
  final List<String> soreZones;

  /// Hoy conviene el plan B de solo torso: 3 días intensos seguidos o
  /// molestia en la pierna, y el día trae pierna (§16.15).
  final bool planB;

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

  /// `planche`: llegaron las mini paralelas (§19.7).
  Future<TodayDashboard> today({DateTime? now, bool planche = false}) async {
    final date = dateOnly(now ?? DateTime.now());
    final p = await profile.get();
    final view = await plan.dayFor(date);
    final training = TrainingRepository(db, ExerciseRepository(db));
    final v3 = await training.blockDay(view, date);
    // El viernes del v3.1 deja de ser circuito cuando ya salieron 10 limpias.
    final type = v3 != null && v3.isV31 && v3.resistance != null
        ? DayType.resistencia
        : view?.day.type ?? DayType.descanso;
    final proposal = type == DayType.progresion ? await training.progressionProposal(date) : null;

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

    // Carga de la última semana: sesiones (RPE × min) y partidos.
    final weekAgo = dayKey(addDays(date, -7));
    final recentSessions = await (db.select(db.sessions)
          ..where((t) => t.date.isBiggerOrEqualValue(weekAgo) & db.trainingSessions))
        .get();
    final recentGames = await (db.select(db.footballGames)..where((t) => t.date.isBiggerOrEqualValue(weekAgo))).get();
    final load = loadReading([
      for (final s in recentSessions)
        LoadItem(date: parseDay(s.date), minutes: (s.totalSec - s.warmupSec - s.cooldownSec) ~/ 60, effort: s.rpe),
      for (final g in recentGames) LoadItem(date: parseDay(g.date), minutes: g.minutes, effort: g.intensity, isFootball: true),
    ], date);
    final recovery = RecoveryRepository(db);
    final soreness = await recovery.sorenessRange(date);
    final dayHasLegs = view != null &&
        (view.day.type == DayType.piernas || view.day.exercises.any((e) => legExercises.contains(e.name)));

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
      mainExercises: view == null ? const [] : _mainLines(view.day, v3),
      blockExercises: view == null || view.day.type == DayType.resistencia
          ? const []
          : blockLines(await training.withV31Blocks(view.day, date, v3, planche: planche)),
      midweekGame: type == DayType.resistencia && (v3?.isV31 ?? false) && await _gameThisWeekBefore(date),
      load: load,
      restingHrWarning: restingHrWarning(await recovery.restingHrRange(date), date),
      soreZones: persistentSoreness(soreness, date),
      planB: sessions.isEmpty && suggestPlanB(dayHasLegs: dayHasLegs, load: load, soreness: soreness, today: date),
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
      kcalTarget: dailyKcalTarget(day: date, weekdayTarget: p.kcalTarget, footballTarget: p.kcalTargetFootball),
      stepsToday: (await (db.select(db.dailySteps)..where((t) => t.date.equals(dayKey(date)))).getSingleOrNull())?.steps,
      stepsGoal: stepsGoalFor(date, p.stepsTarget),
      roundsRecord: record,
      recordSuspect: record == null ? null : await _recordSuspect(record),
      recordDate: record == null ? null : await _recordDate(record),
      v3: v3,
      v3Suggestion: v3 == null || !v3.isV31 ? await _v3Suggestion(date) : null,
      fitnessTest: await _fitnessTest(date, v3),
      measurement: measurementDue(
        today: date,
        lastMeasurement: lastMeasurement == null ? null : parseDay(lastMeasurement.date),
        agreed: p.nextMeasurementDate == null ? null : parseDay(p.nextMeasurementDate!),
        minDays: p.measureIntervalDays,
        maxDays: p.measureIntervalMaxDays,
      ),
    );
  }

  Future<({int round, TestPart part, bool done})?> _fitnessTest(DateTime date, V3Day? v3) async {
    if (v3 == null || !v3.isV31) return null;
    final start = addDays(date, -(date.weekday - 1) - (v3.week - 1) * 7);
    final t = scheduledTest(start, date);
    if (t == null) return null;
    return (round: t.round, part: t.part, done: await FitnessTestRepository(db).done(t.round, t.part));
  }

  /// La sesión del récord, si el plan de ese día no era de circuito.
  /// Lo principal del día. El miércoles de resistencia muestra solo lo de la
  /// semana: la ronda de Cindy (o de las 10 por tiempo) o los 4 del Tabata.
  static List<String> _mainLines(PlanDayDraft day, V3Day? v3) {
    final resistance = day.type == DayType.resistencia || (v3 != null && v3.isV31 && v3.resistance != null);
    if (resistance && v3?.resistance == ResistanceMode.tabata) {
      return [for (final e in day.exercises) if (e.block == tabataBlock) '${e.name} 8 × 20 s a tope'];
    }
    if (resistance && v3?.resistance == ResistanceMode.cindy) {
      return ['20 min: ${day.main.map((e) => '${e.repsMin ?? ''} ${e.name.toLowerCase()}'.trim()).join(' + ')}'];
    }
    return day.main.map((e) => '${e.name} ${e.targetLabel}'.trim()).toList();
  }

  /// Mientras no haya v3.1, se propone desde el próximo lunes (§19: arranca
  /// el lunes 12 oct). Ya no espera a las 10 rondas limpias: el viernes del
  /// v3.1 sigue siendo el circuito hasta lograrlas.
  Future<DateTime?> _v3Suggestion(DateTime today) async {
    if (await plan.hasScheme(v31Scheme)) return null;
    return nextMonday(addDays(today, 1));
  }

  /// ¿Hubo partido de lunes a jueves de la semana de `friday`?
  Future<bool> _gameThisWeekBefore(DateTime friday) async {
    final monday = addDays(friday, -(friday.weekday - 1));
    final rows = await (db.select(db.footballGames)
          ..where((t) => t.date.isBetweenValues(dayKey(monday), dayKey(addDays(friday, -1)))))
        .get();
    return rows.isNotEmpty;
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
/// 3×8–12 · Hollow body hold 2×20–40 s". El Tabata no va (tiene su propia
/// línea cuando toca); el calentamiento y el pino dicen que van antes.
List<String> blockLines(PlanDayDraft day) {
  final groups = <String, List<PlanExerciseDraft>>{};
  for (final e in day.exercises.where((e) => e.block != null && e.block != tabataBlock)) {
    final name = e.block == warmupBlock
        ? 'Para calentar'
        : preBlocks.contains(e.block)
            ? 'Antes, sin fatiga'
            : e.block![0].toUpperCase() + e.block!.substring(1);
    groups.putIfAbsent(e.variant == null ? name : '$name ${e.variant}', () => []).add(e);
  }
  return [
    for (final g in groups.entries) '${g.key}: ${g.value.map((e) => '${e.name} ${e.targetLabel}'.trim()).join(' · ')}',
  ];
}
