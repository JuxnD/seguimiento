import 'dates.dart';
import 'format.dart';
import 'recovery.dart' show LoadReading;
import 'steps.dart' show stepsGoalFor;

// Acompañamiento (plan 009, ADR 0016): una lectura del día con su evidencia,
// estado y próxima revisión. Decide local y reproducible: misma entrada y
// fecha, misma lectura. No escribe; la persistencia de propuestas es del
// repositorio. Base de pasos 5.000; aumentos según progreso y recuperación
// (decisión del owner, 9 oct). Nunca sube una meta sola.

/// Versión de la política; va en cada lectura y propuesta.
const coachPolicy = 1;

/// Ventana: los últimos 10 días entre semana cerrados (2 semanas, como la
/// regla de 2 semanas y las escaleras).
const coachWindowWeekdays = 10;

/// Cobertura mínima de la ventana para leer algo (8 de 10 días con cifra).
const coachMinCoverage = 8;

/// Cumplimiento para proponer revisar al alza: 80 % de los días registrados.
const coachProposeShare = 0.8;

/// Tras aceptar o cambiar una meta, se revisa a los 14 días.
const coachReviewDays = 14;

/// Posponer deja la revisión para dentro de 7 días.
const coachPostponeDays = 7;

/// Redondeo de la meta sugerida (hacia abajo, nunca por encima del promedio).
const coachStepsRounding = 500;

enum CoachState {
  /// Todo en orden: se mantiene y se sigue mirando.
  observar('Observando'),

  /// No hay datos suficientes para decidir.
  faltanDatos('Faltan datos'),

  /// Hay una propuesta para decidir.
  propuesta('Propuesta'),

  /// Se aceptó un cambio y está en su período de prueba.
  aceptada('En prueba'),

  /// Toca revisar un cambio aceptado.
  revisar('Revisar'),

  /// Hoy la recuperación va primero.
  recuperacion('Recuperar');

  const CoachState(this.label);
  final String label;
}

/// Lo que se decidió sobre una propuesta.
enum ProposalStatus { pendiente, aceptada, pospuesta, rechazada }

class ProposalRecord {
  const ProposalRecord({required this.id, required this.status, this.reviewAfter, this.decidedOn});

  final String id;
  final ProposalStatus status;
  final DateTime? reviewAfter;
  final DateTime? decidedOn;
}

class StepsProposal {
  const StepsProposal({required this.from, required this.to, required this.average, required this.daysAtGoal});

  final int from;
  final int to;
  final int average;
  final int daysAtGoal;

  /// Estable por evidencia y política: la misma propuesta no vuelve como
  /// novedad cada mañana; otra cifra es otra evidencia.
  String get id => 'pasos:$from>$to:p$coachPolicy';
}

class CoachReading {
  const CoachReading({
    required this.evaluatedOn,
    required this.state,
    required this.reason,
    this.evidence = const [],
    this.action,
    this.nextReview,
    this.proposal,
    this.policy = coachPolicy,
  });

  final DateTime evaluatedOn;
  final CoachState state;
  final String reason;
  final List<String> evidence;

  /// Qué hacer hoy.
  final String? action;
  final DateTime? nextReview;
  final StepsProposal? proposal;
  final int policy;

  /// Hoy no se presiona con caminatas ni con la meta.
  bool get recoveryFirst => state == CoachState.recuperacion;
}

/// Señales de fatiga declaradas: RPE ≥ 9 hoy o ayer, o "cansado" al
/// despertar. Sin respuesta no es recuperación ni fatiga.
bool declaredFatigue({required List<int?> rpeTodayAndYesterday, int? morningFeeling}) =>
    rpeTodayAndYesterday.any((r) => r != null && r >= 9) || morningFeeling == 3;

/// Los últimos [coachWindowWeekdays] días entre semana antes de `today`.
List<DateTime> coachWindow(DateTime today) {
  final out = <DateTime>[];
  var d = addDays(dateOnly(today), -1);
  while (out.length < coachWindowWeekdays) {
    if (stepsGoalFor(d, 1) != null) out.add(d);
    d = addDays(d, -1);
  }
  return out.reversed.toList();
}

/// Lectura de pasos. `goal`: la meta vigente hoy; `goalSince`: desde cuándo
/// (null = legado sin fecha). `stepsGoalOn`: la meta de cada día de la
/// ventana (null = sin meta conocida ese día). `last`: lo decidido sobre la
/// última propuesta de pasos.
CoachReading stepsReading({
  required DateTime today,
  required Map<DateTime, int> steps,
  required int goal,
  DateTime? goalSince,
  required int? Function(DateTime day) stepsGoalOn,
  required LoadReading load,
  required bool fatigue,
  ProposalRecord? last,
}) {
  final d0 = dateOnly(today);
  if (load.threeIntense || fatigue) {
    final why = load.threeIntense
        ? '${load.intenseStreak} días intensos seguidos'
        : 'cansancio declarado (RPE alto o al despertar)';
    return CoachReading(
      evaluatedOn: d0,
      state: CoachState.recuperacion,
      reason: 'Hoy la recuperación va primero por $why.',
      evidence: [why],
      action: 'Pasos suaves, en llano. Sin caminata extra por la meta.',
      nextReview: addDays(d0, 1),
    );
  }

  final window = coachWindow(d0);
  final byDay = {for (final e in steps.entries) dateOnly(e.key): e.value};
  final recorded = [for (final d in window) if (byDay[d] != null) d];
  final coverage = '${recorded.length} de ${window.length} días entre semana con pasos';
  if (recorded.length < coachMinCoverage) {
    return CoachReading(
      evaluatedOn: d0,
      state: CoachState.faltanDatos,
      reason: 'Faltan registros para leer la meta: $coverage (mínimo $coachMinCoverage).',
      evidence: [coverage],
      action: 'Sincroniza el reloj o anota los pasos del día.',
      nextReview: addDays(d0, 1),
    );
  }

  // Sólo cuentan los días con meta conocida: un día anterior a la meta
  // vigente se mide con la suya, y uno sin meta registrada no se clasifica.
  final judged = [for (final d in recorded) if (stepsGoalOn(d) != null) d];
  final atGoal = judged.where((d) => byDay[d]! >= stepsGoalOn(d)!).length;
  final average = (recorded.map((d) => byDay[d]!).reduce((a, b) => a + b) / recorded.length).round();
  final evidence = [
    coverage,
    'promedio ${fmtInt(average)}',
    if (judged.isNotEmpty) '$atGoal de ${judged.length} días en la meta',
    if (judged.length < recorded.length) '${recorded.length - judged.length} días con meta histórica no registrada',
  ];

  // Un cambio reciente está en prueba hasta su revisión.
  if (goalSince != null) {
    final review = addDays(dateOnly(goalSince), coachReviewDays);
    if (d0.isBefore(review)) {
      return CoachReading(
        evaluatedOn: d0,
        state: CoachState.aceptada,
        reason: 'Meta de ${fmtInt(goal)} desde el ${formatShort(goalSince)}: se revisa el ${formatShort(review)}.',
        evidence: evidence,
        nextReview: review,
      );
    }
  }

  final share = judged.isEmpty ? 0.0 : atGoal / judged.length;
  final candidate = average ~/ coachStepsRounding * coachStepsRounding;
  if (judged.length >= coachMinCoverage && share >= coachProposeShare && candidate > goal) {
    final p = StepsProposal(from: goal, to: candidate, average: average, daysAtGoal: atGoal);
    final decided = last != null && last.id == p.id ? last : null;
    final snoozed = decided?.status == ProposalStatus.pospuesta &&
        decided!.reviewAfter != null &&
        d0.isBefore(dateOnly(decided.reviewAfter!));
    if (decided?.status == ProposalStatus.aceptada) {
      final starts = addDays(dateOnly(decided!.decidedOn ?? d0), 1);
      return CoachReading(
        evaluatedOn: d0,
        state: CoachState.aceptada,
        reason: 'Aceptaste subir la meta: rige desde el ${formatShort(starts)}. Hoy se mide con ${fmtInt(goal)}.',
        evidence: evidence,
        nextReview: addDays(starts, coachReviewDays),
      );
    }
    if (decided?.status == ProposalStatus.rechazada || snoozed) {
      return CoachReading(
        evaluatedOn: d0,
        state: CoachState.observar,
        reason: decided!.status == ProposalStatus.rechazada
            ? 'Mantienes ${fmtInt(goal)}: rechazaste subir a ${fmtInt(candidate)} con esta misma evidencia.'
            : 'Pospusiste revisar la meta hasta el ${formatShort(decided.reviewAfter!)}.',
        evidence: evidence,
        nextReview: decided.reviewAfter,
      );
    }
    return CoachReading(
      evaluatedOn: d0,
      state: CoachState.propuesta,
      reason: 'Cumpliste la meta $atGoal de ${judged.length} días con un promedio de ${fmtInt(average)}. '
          'Podrías subirla a ${fmtInt(candidate)}; tú decides.',
      evidence: evidence,
      action: 'Revisa la propuesta: puedes ajustar la cifra, posponer o rechazar.',
      proposal: p,
    );
  }

  // Revisión de un cambio ya en prueba: si no se sostiene, se dice; volver
  // atrás lo decide la persona en Ajustes.
  if (goalSince != null && judged.isNotEmpty && share < 0.5) {
    return CoachReading(
      evaluatedOn: d0,
      state: CoachState.revisar,
      reason: 'La meta de ${fmtInt(goal)} se cumplió $atGoal de ${judged.length} días. Revisa si te sirve o vuelve a la anterior en Ajustes.',
      evidence: evidence,
      nextReview: addDays(d0, coachReviewDays),
    );
  }

  return CoachReading(
    evaluatedOn: d0,
    state: CoachState.observar,
    reason: 'Meta de ${fmtInt(goal)}: $atGoal de ${judged.length} días cumplidos, promedio ${fmtInt(average)}. Se mantiene.',
    evidence: evidence,
    nextReview: addDays(d0, 1),
  );
}
