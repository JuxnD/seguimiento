import 'package:drift/drift.dart';

import '../../domain/adaptive_coach.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/goal_history.dart';
import '../../domain/recovery.dart';
import '../database.dart';
import '../../domain/progress.dart' show progressionSteps;
import 'exercise_repository.dart';
import 'goal_repository.dart';
import 'plan_repository.dart' show PlanDayDraft;
import 'training_repository.dart';
import 'recovery_repository.dart';

/// Lectura del acompañamiento para un día (plan 009). Hoy y los avisos usan
/// la misma: una señal, una interpretación.
class CoachRepository {
  CoachRepository(this.db);

  final AppDatabase db;

  /// Carga y racha real hasta `date` (sin truncar a 7 días). Lo importado no
  /// cuenta; el test de condición tampoco.
  Future<LoadReading> load(DateTime date) async {
    final throughToday = dayKey(date);
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.date.isSmallerOrEqualValue(throughToday) & db.trainingSessions & t.imported.equals(false)))
        .get();
    final games = await (db.select(db.footballGames)
          ..where((t) => t.date.isSmallerOrEqualValue(throughToday) & t.imported.equals(false)))
        .get();
    return loadReading([
      for (final s in sessions.where((s) => s.mode != 'test'))
        LoadItem(date: parseDay(s.date), minutes: (s.totalSec - s.warmupSec - s.cooldownSec) ~/ 60, effort: s.rpe),
      for (final g in games) LoadItem(date: parseDay(g.date), minutes: g.minutes, effort: g.intensity, isFootball: true),
    ], date);
  }

  /// Cansancio declarado hoy o ayer: RPE ≥ 9 o "cansado" al despertar.
  Future<bool> fatigue(DateTime date) async {
    final d0 = dateOnly(date);
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.date.isBetweenValues(dayKey(addDays(d0, -1)), dayKey(d0)) &
              db.trainingSessions &
              t.imported.equals(false)))
        .get();
    return declaredFatigue(
      rpeTodayAndYesterday: [for (final s in rows) s.rpe],
      morningFeeling: await RecoveryRepository(db).feelingOn(d0),
    );
  }

  /// Recuperación declarada en los últimos 3 días: al despertar (1–2 bien,
  /// 3 cansado) o `recoveryOk` al cerrar una sesión (sin test ni importado).
  /// Una declaración desfavorable pesa más que una favorable. Nada declarado
  /// es desconocida: el RPE moderado no prueba recuperación.
  Future<RecoverySignal> recovery(DateTime date) async {
    final d0 = dateOnly(date);
    final from = dayKey(addDays(d0, -2));
    final feelings = await (db.select(db.morningChecks)
          ..where((t) => t.date.isBetweenValues(from, dayKey(d0)) & t.feeling.isNotNull()))
        .get();
    final sessions = await (db.select(db.sessions)
          ..where((t) =>
              t.date.isBetweenValues(from, dayKey(d0)) &
              db.trainingSessions &
              t.imported.equals(false) &
              t.recoveryOk.isNotNull()))
        .get();
    final declared = sessions.where((s) => s.mode != 'test').map((s) => s.recoveryOk!);
    if (feelings.any((f) => f.feeling == 3) || declared.any((ok) => !ok)) return RecoverySignal.desfavorable;
    if (feelings.any((f) => f.feeling! <= 2) || declared.any((ok) => ok)) return RecoverySignal.favorable;
    return RecoverySignal.desconocida;
  }

  /// Fuerza del día (sobre la evidencia de 008): por cada ejercicio
  /// principal con rango de reps, si toca subir o por qué no. Los circuitos
  /// se leen por rondas, no aquí.
  Future<List<StrengthAdvice>> strengthAdvices(PlanDayDraft day, DateTime date, {int? planDayId, String? mode}) async {
    if (day.type.isCircuit) return const [];
    final exercises = ExerciseRepository(db);
    final training = TrainingRepository(db, exercises);
    final picks = [
      for (final e in day.exercises)
        if (e.block == null && e.repsMax != null && e.sets != null && (e.repsMax ?? 0) > (e.repsMin ?? 0)) e,
    ];
    if (picks.isEmpty) return const [];
    final guides = await exercises.byNames(picks.map((e) => e.name));
    final seen = <String>{};
    return [
      for (final e in picks)
        if (seen.add(e.name))
          strengthAdvice(
            exercise: e.name,
            evidence: await training.lastStrengthEvidence(e.name, date, mode: mode),
            date: date,
            repsMin: e.repsMin,
            repsMax: e.repsMax,
            plannedSets: e.perSide ? e.sets! * 2 : e.sets,
            perSide: e.perSide,
            planDayId: planDayId,
            mode: mode,
            tracksLoad: guides[e.name]?.tracksLoad ?? false,
            chain: progressionSteps(guides[e.name]?.progressionNote),
          ),
    ];
  }

  Future<CoachReading> stepsReading(DateTime date, {LoadReading? load}) async {
    final d0 = dateOnly(date);
    final goals = GoalRepository(db);
    final history = await goals.history();
    final current = history.current(GoalMetric.pasos, d0);
    final goal = current?.value?.round() ?? 5000;
    // En prueba sólo un cambio hecho por la persona (Ajustes o propuesta).
    final since = current != null &&
            !current.legacy &&
            (current.origin == GoalOrigin.perfil || current.origin == GoalOrigin.propuesta)
        ? current.effectiveFrom
        : null;
    final from = dayKey(addDays(d0, -(coachWindowWeekdays * 2)));
    final rows = await (db.select(db.dailySteps)
          ..where((t) => t.date.isBiggerOrEqualValue(from) & t.date.isSmallerThanValue(dayKey(d0))))
        .get();
    return stepsReadingFrom(
      today: d0,
      steps: {for (final r in rows) parseDay(r.date): r.steps},
      goal: goal,
      goalSince: since,
      history: history,
      load: load ?? await this.load(d0),
      fatigue: await fatigue(d0),
      recovery: await recovery(d0),
      last: await goals.lastProposal('pasos'),
    );
  }
}

/// Lo mismo, con las piezas a mano (pruebas, informe).
CoachReading stepsReadingFrom({
  required DateTime today,
  required Map<DateTime, int> steps,
  required int goal,
  DateTime? goalSince,
  required GoalHistory history,
  required LoadReading load,
  required bool fatigue,
  RecoverySignal recovery = RecoverySignal.desconocida,
  ProposalRecord? last,
}) =>
    stepsReading(
      today: today,
      steps: steps,
      goal: goal,
      goalSince: goalSince,
      stepsGoalOn: (day) {
        final at = history.on(GoalMetric.pasos, day);
        return at == null || !at.known ? null : at.value?.round();
      },
      load: load,
      fatigue: fatigue,
      recovery: recovery,
      last: last,
    );
