import 'package:drift/drift.dart';

import '../../domain/adaptive_coach.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/goal_history.dart';
import '../../domain/recovery.dart';
import '../database.dart';
import '../../domain/progress.dart' show progressionSteps;
import '../../domain/progress_evidence.dart';
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
    final goals = GoalRepository(db);
    final seen = <String>{};
    final out = <StrengthAdvice>[];
    for (final e in picks) {
      if (!seen.add(e.name)) continue;
      final evidence = await training.lastStrengthEvidence(e.name, date, mode: mode);
      var a = strengthAdvice(
        exercise: e.name,
        evidence: evidence,
        date: date,
        repsMin: e.repsMin,
        repsMax: e.repsMax,
        plannedSets: e.perSide ? e.sets! * 2 : e.sets,
        perSide: e.perSide,
        planDayId: planDayId,
        mode: mode,
        tracksLoad: guides[e.name]?.tracksLoad ?? false,
        chain: progressionSteps(guides[e.name]?.progressionNote),
      );
      // Lo decidido sobre esta misma propuesta.
      if (a.status == StrengthStatus.subir && a.proposalId != null) {
        final decided = await goals.proposal(a.proposalId!);
        if (proposalHidden(decided, date)) {
          a = a.copyWith(
            status: StrengthStatus.mantener,
            decision: decided!.status,
            text: decided.status == ProposalStatus.rechazada
                ? 'decidiste mantener la dosis con esta evidencia'
                : 'hoy no (lo pospusiste)',
          );
        } else if (decided != null) {
          a = a.copyWith(decision: decided.status);
        }
      }
      // Tras aceptar una subida: la primera sesión desde ese día con el
      // ejercicio, comparada con la dosis guardada (R2). Sin dosis guardada
      // no se revisa; sin sesión todavía, no hay revisión.
      final last = await goals.lastDecision(strengthProposalKind(e.name));
      if (last != null && last.$2.status == ProposalStatus.aceptada && last.$2.decidedOn != null) {
        final dose = StrengthDose.decode(last.$2.evidence);
        final attempt = await _firstSessionWith(e.name, from: last.$2.decidedOn!, before: date, notId: dose?.sessionId);
        if (attempt != null) {
          a = a.copyWith(
              review: dose == null
                  ? 'aceptaste subir; no quedó guardada la dosis acordada: no se puede revisar'
                  : strengthReview(dose, attempt));
        }
      }
      out.add(a);
    }
    return out;
  }

  /// Primera sesión (cualquier protocolo) con `exercise` desde `from` y antes
  /// de `before`: la que intentó la subida aceptada.
  Future<StrengthSessionEvidence?> _firstSessionWith(String exercise,
      {required DateTime from, required DateTime before, int? notId}) async {
    final exId = await ExerciseRepository(db).idOf(exercise);
    if (exId == null) return null;
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.date.isBiggerOrEqualValue(dayKey(from)) & t.date.isSmallerThanValue(dayKey(before)) & db.trainingSessions)
          ..orderBy([(t) => OrderingTerm(expression: t.date), (t) => OrderingTerm(expression: t.id)]))
        .get();
    for (final row in rows.where((r) => r.id != notId)) {
      final sets = await (db.select(db.sessionSets)
            ..where((t) => t.sessionId.equals(row.id) & t.exerciseId.equals(exId))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      if (sets.isEmpty) continue;
      return StrengthSessionEvidence(
        sessionId: row.id,
        date: parseDay(row.date),
        type: row.type,
        exercise: exercise,
        planDayId: row.planDayId,
        mode: row.mode,
        incomplete: row.incomplete,
        imported: row.imported,
        sets: [
          for (final s in sets)
            StrengthSetEvidence(
                reps: s.reps,
                rir: s.rir,
                split: s.split,
                splitDetail: s.splitDetail,
                toFailure: s.toFailure,
                loadKg: s.loadKg,
                variant: s.variant),
        ],
      );
    }
    return null;
  }

  /// Decide la propuesta de pasos que se mostró con el día real de la
  /// decisión (`now`), no el de la lectura (un diálogo abierto antes de
  /// medianoche). Antes de escribir revalida: si la lectura de ese día ya no
  /// ofrece la misma propuesta (otra ventana, ya decidida, recuperación
  /// primero), no escribe nada y devuelve la lectura nueva. null = decidida;
  /// la vigencia aceptada rige desde el día siguiente al real.
  Future<CoachReading?> decideSteps(StepsProposal shown, ProposalStatus status,
      {required DateTime now, int? acceptedValue}) async {
    final day = dateOnly(now);
    final fresh = await stepsReading(day);
    final p = fresh.proposal;
    if (fresh.state != CoachState.propuesta || p == null || p.id != shown.id) return fresh;
    await GoalRepository(db).decideSteps(p, status,
        today: day, acceptedValue: acceptedValue, evidence: fresh.evidence.join(' · '));
    return null;
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
      goalFrom: current == null || current.legacy ? null : current.effectiveFrom,
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
  DateTime? goalFrom,
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
      goalFrom: goalFrom,
      stepsGoalOn: (day) {
        final at = history.on(GoalMetric.pasos, day);
        return at == null || !at.known ? null : at.value?.round();
      },
      load: load,
      fatigue: fatigue,
      recovery: recovery,
      last: last,
    );
