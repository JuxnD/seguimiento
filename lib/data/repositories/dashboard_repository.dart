import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart';
import '../../domain/test_protocol.dart';
import '../../domain/plan_v32.dart';
import '../../domain/leg_chain.dart' show PlanBAdvice;
import '../../domain/nutrition.dart';
import '../../domain/plan_v3.dart';
import '../../domain/progress.dart';
import '../../domain/football_summary.dart';
import '../../domain/recovery.dart';
import '../../domain/session_script.dart'
    show preBlocks, tabataBlock, warmupBlock;
import '../../domain/goal_history.dart';
import '../../domain/technique_session.dart';
import '../database.dart';
import '../../domain/adaptive_coach.dart';
import 'coach_repository.dart';
import 'goal_repository.dart';
import 'exercise_repository.dart';
import 'fitness_test_repository.dart';
import 'leg_chain_repository.dart';
import 'readiness_repository.dart';
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
    this.footballGamesToday = const [],
    this.hardFootballYesterday,
    required this.streak,
    required this.macros,
    required this.proteinMin,
    required this.proteinMax,
    required this.kcalTarget,
    this.proteinReference,
    this.kcalReference,
    this.stepsReference,
    this.stepsToday,
    this.stepsGoal,
    required this.roundsRecord,
    this.recordSuspect,
    this.recordDate,
    this.v3,
    this.v3Suggestion,
    required this.measurement,
    this.proposal,
    this.roundsDecision,
    this.midweekGame = false,
    this.load =
        const LoadReading(todayLoad: 0, todayCount: 0, intenseStreak: 0),
    this.restingHrWarning,
    this.soreZones = const [],
    this.planB = false,
    this.planBAdvice = PlanBAdvice.none,
    this.fitnessTest,
    this.fitnessTestStart,
    this.techniqueSuggested = false,
    this.coach,
    this.strength = const [],
  });

  /// Fuerza del día: qué subir o por qué no (plan 009 + evidencia de 008).
  final List<StrengthAdvice> strength;

  /// Lectura del acompañamiento (plan 009): pasos según cobertura,
  /// cumplimiento y recuperación. null fuera de Hoy.
  final CoachReading? coach;

  /// Ofrecer la sesión técnica (§16.21): descarga, víspera de test o de las
  /// pruebas, o con plan B. Alternativa, no reemplazo.
  final bool techniqueSuggested;

  /// Test de condición de hoy (§19.11): el lunes sustituye el tirón; el
  /// miércoles va antes de la sesión de piernas. null si hoy no toca.
  final ({int round, TestPart part, bool done})? fitnessTest;

  /// Lunes de inicio del v3.1 del test de hoy: su identidad para moverlo.
  final DateTime? fitnessTestStart;

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
  final List<FootballGameRow> footballGamesToday;

  /// Conserva el row representativo para hidratación/lectores legados; el
  /// acumulado usa todos y no mezcla pesajes entre partidos.
  List<FootballGameRow> get gamesToday => footballGamesToday.isNotEmpty
      ? footballGamesToday
      : [if (footballToday != null) footballToday!];
  FootballDaySummary get footballSummary => FootballDaySummary(
      date,
      gamesToday.map((g) =>
          (minutes: g.minutes, intensity: g.intensity, format: g.format)));

  /// Partido de ayer si fue intenso (≥ 8) o hubo golpe: hoy se baja la carga.
  final FootballGameRow? hardFootballYesterday;
  final int streak;
  final Macros macros;
  final int? proteinMin;
  final int? proteinMax;
  final int? kcalTarget;
  final GoalAt? proteinReference;
  final GoalAt? kcalReference;
  final GoalAt? stepsReference;

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

  bool get recentRecord =>
      recordDate != null && daysBetween(recordDate!, date) <= 6;

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

  /// Motivos del Plan B con sus datos (§16.24, plan 039). La misma
  /// clasificación que la sección de cadena del informe.
  final PlanBAdvice planBAdvice;

  /// Cuándo toca medir. null = sin línea base ni fecha acordada.
  final MeasurementDue? measurement;

  /// Día de progresión: lo que propone la regla. La meta del viernes sale de
  /// aquí y no del plan, que tiene un número fijo y no avanzaba (§16.9).
  final ProgressionProposal? proposal;

  /// Lo decidido sobre la propuesta de rondas de hoy (plan 009).
  final ProposalStatus? roundsDecision;

  /// Lo del día está hecho. Un partido lo cumple en días de fútbol o descanso;
  /// en un día de entrenamiento no reemplaza la sesión del plan (la racha sí
  /// lo cuenta).
  bool get trained =>
      sessionsToday > 0 || (footballToday != null && !dayType.isTraining);
  double? get proteinProgress =>
      proteinMin == null ? null : goalProgress(macros.protein, proteinMin!);
  double? get kcalProgress =>
      kcalTarget == null ? null : goalProgress(macros.kcal, kcalTarget!);
  double? get stepsProgress =>
      stepsGoal == null ? null : goalProgress(stepsToday ?? 0, stepsGoal!);
  double get roundsProgress => goalProgress(roundsDone ?? 0, targetRounds ?? 0);
}

class RecordSuspect {
  const RecordSuspect(
      {required this.sessionId, required this.date, required this.plannedType});

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
  Future<TodayDashboard> today(
      {DateTime? now, bool planche = false, bool rings = false}) async {
    final date = dateOnly(now ?? DateTime.now());
    // Lo que ya rige hoy pasa al perfil antes de leerlo (plan 009).
    await GoalRepository(db).projectDueGoals(date);
    final p = await profile.get();
    final history = await GoalRepository(db).history();
    final protein = goalReferenceOn(history, GoalMetric.proteinaMin, date);
    final proteinMax = goalReferenceOn(history, GoalMetric.proteinaMax, date);
    final kcal = kcalGoalReferenceOn(history, date);
    final steps = date.weekday >= DateTime.saturday
        ? const GoalAt(null, known: true)
        : goalReferenceOn(history, GoalMetric.pasos, date);
    final view = await plan.dayFor(date);
    final training = TrainingRepository(db, ExerciseRepository(db));
    final v3 = await training.blockDay(view, date);
    final effective = view == null
        ? null
        : v3?.isV32 == true
            ? await training.withV31Blocks(view.day, date, v3,
                planche: planche, rings: rings)
            : view.day;
    // El viernes del v3.1 deja de ser circuito cuando ya salieron 10 limpias.
    final type = v3 != null && v3.isV31 && v3.resistance != null
        ? DayType.resistencia
        : effective?.type ?? DayType.descanso;
    var proposal = type == DayType.progresion && v3?.isV32 != true
        ? await training.progressionProposal(date)
        : null;
    // Lo decidido sobre esa misma propuesta de rondas (plan 009).
    ProposalStatus? roundsDecision;
    if (proposal != null &&
        proposal.canProgress &&
        proposal.sessionId != null) {
      final id = roundsProposalId(
          fromRounds: proposal.lastRounds,
          toRounds: proposal.rounds,
          sessionId: proposal.sessionId!);
      final decided = await GoalRepository(db).proposal(id);
      roundsDecision = decided?.status;
      if (proposalHidden(decided, date)) {
        proposal = heldProposal(proposal, decided!.status);
      }
    }

    final sessions = await (db.select(db.sessions)
          ..where((t) => t.date.equals(dayKey(date)) & db.trainingSessions))
        .get();
    final test = await _fitnessTest(date, v3);
    final planSessions = sessions.where((s) => s.mode != 'test').toList();
    final torsoComplete =
        (v3?.isV32 == true || date.weekday == DateTime.monday) &&
            test?.part == TestPart.torso &&
            test!.done;
    final meals = await nutrition.range(date, date);
    final footballGames = await (db.select(db.footballGames)
          ..where((t) => t.date.equals(dayKey(date)))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    final football = footballGames.isEmpty ? null : footballGames.last;
    final yesterday = await _lastGame(addDays(date, -1));

    final maxRounds = db.sessions.roundsDone.max();
    final record = await (db.selectOnly(db.sessions)
          ..addColumns([maxRounds])
          ..where(db.countedCircuitRounds))
        .map((r) => r.read(maxRounds))
        .getSingle();

    // Carga y racha real hasta hoy (sin truncar a 7 días), la misma que lee
    // el acompañamiento y los avisos (plan 009).
    final coachRepo = CoachRepository(db);
    final load = await coachRepo.load(date);
    final coach = await coachRepo.stepsReading(date, load: load);
    final recovery = RecoveryRepository(db);
    final soreness = await recovery.sorenessRange(date);
    final dayHasLegs = view != null &&
        (view.day.type == DayType.piernas ||
            view.day.exercises.any((e) => legExercises.contains(e.name)));

    final lastMeasurement = await (db.select(db.measurements)
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();

    final eve = planSessions.isEmpty && await _eveOfTest(date, training);
    // Cadena de piernas y motivos separados (§16.24, plan 039): no la racha
    // global de días intensos.
    final legChain = LegChainRepository(db);
    final planBAdvice = planSessions.isEmpty
        ? await legChain.planB(date, dayHasLegs: dayHasLegs, legs: (await legChain.chains(date)).legs)
        : PlanBAdvice.none;
    final planB = planBAdvice.show;
    return TodayDashboard(
      date: date,
      weekIndex: weekIndexFor(p.programStart, date),
      dayType: type,
      planVersion: view?.versionNumber,
      planSummary: effective == null ? null : _summary(effective),
      mainExercises: effective == null ? const [] : _mainLines(effective, v3),
      blockExercises: view == null || view.day.type == DayType.resistencia
          ? const []
          : blockLines(v3?.isV32 == true
              ? effective!
              : await training.withV31Blocks(view.day, date, v3,
                  planche: planche, rings: rings)),
      midweekGame: type == DayType.resistencia &&
          (v3?.isV31 ?? false) &&
          await _gameThisWeekBefore(date),
      load: load,
      restingHrWarning:
          restingHrWarning(await recovery.restingHrRange(date), date),
      soreZones: persistentSoreness(soreness, date),
      planB: planB,
      planBAdvice: planBAdvice,
      targetRounds: v3?.isV32 == true && date.weekday == DateTime.friday
          ? maintenanceRounds(v3!.week)
          : proposal?.rounds ?? view?.day.targetRounds,
      roundsDecision: roundsDecision,
      proposal: proposal,
      roundsDone:
          sessions.map((s) => s.roundsDone).whereType<int>().firstOrNull,
      sessionsToday: planSessions.length + (torsoComplete ? 1 : 0),
      footballToday: football,
      footballGamesToday: footballGames,
      hardFootballYesterday:
          yesterday != null && isHardGame(yesterday) ? yesterday : null,
      streak: await _streak(date),
      macros: Macros.sum(meals.map((m) => m.macros)),
      proteinMin: protein.comparable ? protein.value!.round() : null,
      proteinMax: proteinMax.comparable ? proteinMax.value!.round() : null,
      kcalTarget: kcal.comparable ? kcal.value!.round() : null,
      proteinReference: protein,
      kcalReference: kcal,
      stepsReference: steps,
      stepsToday: (await (db.select(db.dailySteps)
                ..where((t) => t.date.equals(dayKey(date))))
              .getSingleOrNull())
          ?.steps,
      stepsGoal: steps.comparable ? steps.value!.round() : null,
      roundsRecord: record,
      recordSuspect: record == null ? null : await _recordSuspect(record),
      recordDate: record == null ? null : await _recordDate(record),
      v3: v3,
      v3Suggestion: v3 == null || !v3.isV31 ? await _v3Suggestion(date) : null,
      fitnessTest: test,
      fitnessTestStart: test == null ? null : _v31StartFor(date, v3),
      coach: coach,
      strength: view == null || type == DayType.resistencia
          ? const []
          : await coachRepo.strengthAdvices(effective!, date,
              planDayId: view.dayId),
      techniqueSuggested: planSessions.isEmpty &&
          suggestTechniqueSession(
            deload: v3?.reducedVolume ?? false,
            eveOfTest: eve,
            planB: planB,
          ),
      measurement: measurementDue(
        today: date,
        lastMeasurement:
            lastMeasurement == null ? null : parseDay(lastMeasurement.date),
        agreed: p.nextMeasurementDate == null
            ? null
            : parseDay(p.nextMeasurementDate!),
        minDays: p.measureIntervalDays,
        maxDays: p.measureIntervalMaxDays,
      ),
    );
  }

  /// Mañana hay test de condición o es el viernes de pruebas del v3.1. Se
  /// mira el v3.1 de mañana: el domingo antes del Test 1 todavía no hay v3.1.
  Future<bool> _eveOfTest(DateTime date, TrainingRepository training) async {
    final tomorrow = addDays(date, 1);
    final v3 = await training.blockDay(await plan.dayFor(tomorrow), tomorrow);
    if (v3 == null || !v3.isV31) return false;
    final start =
        addDays(tomorrow, -(tomorrow.weekday - 1) - (v3.week - 1) * 7);
    return await ReadinessRepository(db).effectiveScheduledTest(start, tomorrow,
                scheme: v3.scheme,
                protocol:
                    v3.isV32 ? TestProtocolId.v32_13 : TestProtocolId.v31_12) !=
            null ||
        dateOnly(v3.testDate) == tomorrow;
  }

  static DateTime? _v31StartFor(DateTime date, V3Day? v3) =>
      v3 == null || !v3.isV31
          ? null
          : addDays(date, -(date.weekday - 1) - (v3.week - 1) * 7);

  Future<({int round, TestPart part, bool done})?> _fitnessTest(
      DateTime date, V3Day? v3) async {
    final start = _v31StartFor(date, v3);
    if (start == null) return null;
    // Con los tests movidos por la recuperación activa (§19.17).
    final protocol = v3!.isV32 ? TestProtocolId.v32_13 : TestProtocolId.v31_12;
    final t = await ReadinessRepository(db).effectiveScheduledTest(start, date,
        scheme: v3.scheme, protocol: protocol);
    if (t == null) return null;
    final key = TestScheduleKey(
        scheme: v3.scheme,
        blockStart: start,
        protocolId: protocol,
        round: t.round,
        part: t.part);
    return (
      round: t.round,
      part: t.part,
      done: await FitnessTestRepository(db)
          .done(t.round, t.part, protocol: protocol, key: key)
    );
  }

  /// La sesión del récord, si el plan de ese día no era de circuito.
  /// Lo principal del día. El miércoles de resistencia muestra solo lo de la
  /// semana: la ronda de Cindy (o de las 10 por tiempo) o los 4 del Tabata.
  static List<String> _mainLines(PlanDayDraft day, V3Day? v3) {
    final resistance = day.type == DayType.resistencia ||
        (v3 != null && v3.isV31 && v3.resistance != null);
    if (resistance && v3?.resistance == ResistanceMode.tabata) {
      return [
        for (final e in day.exercises)
          if (e.block == tabataBlock) '${e.name} 8 × 20 s a tope'
      ];
    }
    if (resistance && v3?.resistance == ResistanceMode.cindy) {
      return [
        '20 min: ${day.main.map((e) => '${e.repsMin ?? ''} ${e.name.toLowerCase()}'.trim()).join(' + ')}'
      ];
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
          ..where((t) => t.date
              .isBetweenValues(dayKey(monday), dayKey(addDays(friday, -1)))))
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

  Future<FootballGameRow?> _lastGame(DateTime day) =>
      (db.select(db.footballGames)
            ..where((t) => t.date.equals(dayKey(day)))
            ..orderBy([
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)
            ])
            ..limit(1))
          .getSingleOrNull();

  String _summary(PlanDayDraft day) {
    final rounds =
        day.targetRounds == null ? null : '${day.targetRounds} rondas';
    final exercises =
        day.main.map((e) => '${e.name} ${e.targetLabel}'.trim()).join(' · ');
    return [if (rounds != null) rounds, if (exercises.isNotEmpty) exercises]
        .join(' · ');
  }

  /// Días seguidos con actividad guardada, sin que el descanso planificado
  /// los rompa. Incluye movilidad, técnica, rutinas parciales y fútbol;
  /// no cambia el criterio de entrenamiento/adherencia de Hoy.
  Future<int> _streak(DateTime today) async {
    final rows = await db.select(db.sessions).get();
    final games = await db.select(db.footballGames).get();
    final dates = {...rows.map((s) => s.date), ...games.map((g) => g.date)};
    final versions = await plan.versions();
    if (versions.isEmpty) return dates.contains(dayKey(today)) ? 1 : 0;

    // Mapa weekday → tipo por versión, para no recargar el plan por día.
    final byVersion = <int, Map<int, DayType>>{};
    for (final v in versions) {
      final days = await (db.select(db.planDays)
            ..where((t) => t.planVersionId.equals(v.id)))
          .get();
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
bool isHardGame(FootballGameRow game) =>
    (game.intensity ?? 0) >= 8 || game.knock == true;

/// Una línea por bloque y variante: "Core A: Elevación de piernas colgado
/// 3×8–12 · Hollow body hold 2×20–40 s". El Tabata no va (tiene su propia
/// línea cuando toca); el calentamiento y el pino dicen que van antes.
List<String> blockLines(PlanDayDraft day) {
  final groups = <String, List<PlanExerciseDraft>>{};
  for (final e in day.exercises
      .where((e) => e.block != null && e.block != tabataBlock)) {
    final name = e.block == warmupBlock
        ? 'Para calentar'
        : preBlocks.contains(e.block)
            ? 'Antes, sin fatiga'
            : e.block![0].toUpperCase() + e.block!.substring(1);
    groups
        .putIfAbsent(e.variant == null ? name : '$name ${e.variant}', () => [])
        .add(e);
  }
  return [
    for (final g in groups.entries)
      '${g.key}: ${g.value.map((e) => '${e.name} ${e.targetLabel}'.trim()).join(' · ')}',
  ];
}
