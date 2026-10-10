import 'dart:convert';

import 'dates.dart';
import 'format.dart';
import 'progress.dart' show ProgressionProposal, strengthProgressionHint;
import 'progress_evidence.dart';
import 'recovery.dart' show LoadReading;
import 'steps.dart' show stepsGoalFor;

// Acompañamiento (plan 009, ADR 0016): una lectura del día con su evidencia,
// estado y próxima revisión. Decide local y reproducible: misma entrada y
// fecha, misma lectura. No escribe; la persistencia de propuestas es del
// repositorio. Base de pasos 5.000; aumentos según progreso y recuperación
// (decisión del owner, 9 oct). Nunca sube una meta sola.

/// Versión de la política; va en cada lectura y propuesta.
const coachPolicy = 1;

/// La política v1 es **experimental**: sus umbrales (cobertura 8/10, 80 %,
/// 50 %, RPE ≥ 9, ventana de 3 días, redondeo de 500) están pendientes de
/// confirmar con el owner (ADR 0016). Son una revisión de metas que la
/// persona elige, no una prescripción: nada se aplica sin su decisión.
const coachPolicyExperimental = true;

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
  const ProposalRecord({required this.id, required this.status, this.reviewAfter, this.decidedOn, this.evidence});

  final String id;
  final ProposalStatus status;
  final DateTime? reviewAfter;
  final DateTime? decidedOn;

  /// Lo guardado con la decisión (en fuerza, la dosis en JSON).
  final String? evidence;
}

class StepsProposal {
  const StepsProposal({
    required this.from,
    required this.to,
    required this.average,
    required this.daysAtGoal,
    this.goalFrom,
  });

  final int from;
  final int to;
  final int average;
  final int daysAtGoal;

  /// Desde cuándo rige la meta que se revisa; null = legado. Volver a 5.000
  /// después de aceptar 6.000 es otra vigencia y, por tanto, otro ciclo.
  final DateTime? goalFrom;

  /// Estable por evidencia, vigencia y política: la misma propuesta no
  /// vuelve como novedad cada mañana; otra cifra u otra vigencia es otra.
  String get id => 'pasos:$from>$to:${goalFrom == null ? 'legado' : dayKey(goalFrom!)}:p$coachPolicy';
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

/// Lo que se sabe de la recuperación de los últimos 3 días, sólo por lo que
/// la persona declaró: al despertar (1–2 bien, 3 cansado) o "recuperación
/// normal" al cerrar una sesión (`recoveryOk`). La intensidad moderada, el
/// tiempo o las notas no cuentan como respuesta (revisión de Codex).
enum RecoverySignal { favorable, desconocida, desfavorable }

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
  DateTime? goalFrom,
  required int? Function(DateTime day) stepsGoalOn,
  required LoadReading load,
  required bool fatigue,
  RecoverySignal recovery = RecoverySignal.desconocida,
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

  // Lo declarado manda (R2): si dijo que no se recuperó bien, Hoy, las
  // caminatas y el aviso no empujan pasos. No es un diagnóstico de
  // agotamiento: se repite lo que la persona marcó.
  if (recovery == RecoverySignal.desfavorable) {
    const why = 'declaraste que no te recuperaste bien en los últimos 3 días';
    return CoachReading(
      evaluatedOn: d0,
      state: CoachState.recuperacion,
      reason: 'Hoy la recuperación va primero: $why.',
      evidence: const [why],
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
    // Subir pide saber que la recuperación va bien: carga alta hoy o dos
    // sesiones hoy frenan; sin ninguna señal conocida no se presume.
    if (load.highToday || load.twoToday) {
      return CoachReading(
        evaluatedOn: d0,
        state: CoachState.observar,
        reason: 'Vas para subir la meta, pero la carga de hoy ya es alta (${load.todayLoad}): la revisión espera.',
        evidence: [...evidence, 'carga de hoy ${load.todayLoad}'],
        nextReview: addDays(d0, 1),
      );
    }
    if (recovery == RecoverySignal.desconocida) {
      return CoachReading(
        evaluatedOn: d0,
        state: CoachState.faltanDatos,
        reason: 'Vas para subir la meta, pero falta saber cómo te recuperas: responde "¿Cómo amaneciste?" '
            'o marca si te recuperaste al cerrar una sesión.',
        evidence: [...evidence, 'sin señales de recuperación en 3 días'],
        action: 'Registro de la mañana: cómo amaneciste.',
        nextReview: addDays(d0, 1),
      );
    }
    final p = StepsProposal(
        from: goal, to: candidate, average: average, daysAtGoal: atGoal, goalFrom: goalFrom ?? goalSince);
    var decided = last != null && last.id == p.id ? last : null;
    // Un rechazo vale para la ventana con la que se decidió; con una ventana
    // nueva completa (14 días después) se puede reconsiderar.
    if (decided?.status == ProposalStatus.rechazada &&
        decided!.decidedOn != null &&
        !d0.isBefore(addDays(dateOnly(decided.decidedOn!), coachReviewDays))) {
      decided = null;
    }
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
      reason: 'Revisión de tu meta: la cumpliste $atGoal de ${judged.length} días con un promedio de '
          '${fmtInt(average)}. Podrías subirla a ${fmtInt(candidate)}; tú decides.',
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

// ---------------------------------------------------------------------------
// Fuerza (plan 009 sobre la evidencia de 008): por ejercicio del día, si toca
// subir y, si no, por qué. Reutiliza `strengthProgressionHint`; las causas
// salen de lo guardado, nunca de la etiqueta ni del tiempo.
// ---------------------------------------------------------------------------

enum StrengthStatus { subir, mantener, sinDatos }

class StrengthAdvice {
  const StrengthAdvice(this.exercise, this.status, this.text,
      {this.sessionId, this.decision, this.review, this.dose});

  final String exercise;
  final StrengthStatus status;

  /// Qué subir, o la causa de no subir.
  final String text;

  /// Sesión que sostiene la lectura (la evidencia de 008).
  final int? sessionId;

  /// Lo decidido sobre esta misma propuesta, si se decidió.
  final ProposalStatus? decision;

  /// Tras aceptar una subida: si se intentó y se sostuvo en la sesión siguiente.
  final String? review;

  /// La subida que propone la regla, estructurada: es lo que se guarda al
  /// aceptarla y contra lo que se revisa la sesión siguiente.
  final StrengthDose? dose;

  String? get proposalId => sessionId == null ? null : strengthProposalId(exercise, sessionId!);

  StrengthAdvice copyWith({StrengthStatus? status, String? text, ProposalStatus? decision, String? review}) =>
      StrengthAdvice(exercise, status ?? this.status, text ?? this.text,
          sessionId: sessionId, decision: decision ?? this.decision, review: review ?? this.review, dose: dose);
}

/// Qué sube la regla de 008 (`doubleProgressionHint`): carga (+2–5 kg),
/// la variante siguiente de la cadena, o banda/pausa (que no se registra).
enum DoseKind { carga, variante, otra }

/// La dosis de una subida propuesta, con lo que hace falta para revisarla
/// sin leer texto: desde qué carga o variante, cuántas series, qué piso de
/// reps, protocolo y día del plan. Se guarda como JSON en la decisión.
class StrengthDose {
  const StrengthDose({
    required this.kind,
    required this.sessionId,
    this.fromLoadKg,
    this.fromVariant,
    this.toVariant,
    this.sets,
    this.repsMin,
    this.mode,
    this.planDayId,
  });

  /// Lo que sube la regla con carga: entre 2 y 5 kg (no se inventa otra cifra).
  static const minLoadStepKg = 2.0, maxLoadStepKg = 5.0;

  final DoseKind kind;

  /// Sesión cuya evidencia propuso la subida.
  final int sessionId;
  final double? fromLoadKg;
  final String? fromVariant;
  final String? toVariant;
  final int? sets;
  final int? repsMin;
  final String? mode;
  final int? planDayId;

  Map<String, Object?> toJson() => {
        'v': 1,
        'kind': kind.name,
        'sessionId': sessionId,
        'fromLoadKg': fromLoadKg,
        'fromVariant': fromVariant,
        'toVariant': toVariant,
        'sets': sets,
        'repsMin': repsMin,
        'mode': mode,
        'planDayId': planDayId,
      };

  String encode() => jsonEncode(toJson());

  /// null si lo guardado no es una dosis completa: una decisión anterior que
  /// sólo guardó el texto, o un JSON sin series/piso válidos o (variante) sin
  /// la variante destino. Entonces no se revisa; nunca se completa a ciegas.
  static StrengthDose? decode(String? raw) {
    if (raw == null || !raw.startsWith('{')) return null;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      if (j['v'] != 1) return null;
      final kind = DoseKind.values.asNameMap()[j['kind']];
      final sessionId = j['sessionId'], sets = j['sets'], repsMin = j['repsMin'];
      final load = j['fromLoadKg'], from = j['fromVariant'], to = j['toVariant'];
      final mode = j['mode'], planDayId = j['planDayId'];
      if (kind == null || sessionId is! int || sets is! int || sets < 1 || repsMin is! int || repsMin < 1) return null;
      if (load != null && (load is! num || !load.isFinite || load < 0)) return null;
      if ((from != null && from is! String) || (to != null && to is! String)) return null;
      if ((mode != null && mode is! String) || (planDayId != null && planDayId is! int)) return null;
      if (kind == DoseKind.variante && (to is! String || to.isEmpty)) return null;
      return StrengthDose(
        kind: kind,
        sessionId: sessionId,
        fromLoadKg: (load as num?)?.toDouble(),
        fromVariant: from as String?,
        toVariant: to as String?,
        sets: sets,
        repsMin: repsMin,
        mode: mode as String?,
        planDayId: planDayId as int?,
      );
    } on Object {
      return null;
    }
  }
}

/// La dosis que corresponde a la subida que propone la regla (mismas ramas
/// que `doubleProgressionHint`). Sólo cuando la regla propone subir.
StrengthDose strengthDose({
  required StrengthSessionEvidence evidence,
  required int? repsMin,
  required int? plannedSets,
  bool tracksLoad = false,
  List<String> chain = const [],
  String? mode,
  int? planDayId,
}) {
  final last = evidence.sets.last;
  final current = last.variant == null ? 0 : chain.indexOf(last.variant!);
  final kind = tracksLoad
      ? DoseKind.carga
      : (chain.isNotEmpty && current >= 0 && current + 1 < chain.length ? DoseKind.variante : DoseKind.otra);
  return StrengthDose(
    kind: kind,
    sessionId: evidence.sessionId,
    fromLoadKg: evidence.sets.first.loadKg,
    fromVariant: last.variant,
    toVariant: kind == DoseKind.variante ? chain[current + 1] : null,
    sets: plannedSets,
    repsMin: repsMin,
    mode: mode,
    planDayId: planDayId,
  );
}

/// Revisión de una subida aceptada contra la sesión que la intentó (R2).
/// Sólo dice "subiste" si lo guardado lo demuestra: carga o variante
/// acordada en todas las series esperadas, mismo protocolo y día del plan.
String strengthReview(StrengthDose dose, StrengthSessionEvidence later) {
  final when = 'el ${formatShort(later.date)}';
  if (later.imported) return 'aceptaste subir; $when es historial importado: no demuestra la subida';
  if (later.mode != dose.mode) return 'aceptaste subir; $when fue otro protocolo: no demuestra la subida';
  if (dose.planDayId != null && later.planDayId != dose.planDayId) {
    return 'aceptaste subir; $when fue otro día del plan: no demuestra la subida';
  }
  if (dose.kind == DoseKind.otra) {
    return 'aceptaste subir (más banda o pausa arriba); la banda y la pausa no se registran: no se puede demostrar';
  }
  double load(StrengthSetEvidence s) => s.loadKg ?? 0;
  final from = dose.fromLoadKg ?? 0;
  // Subir carga es con la misma variante: otro agarre o ejercicio con +2 kg
  // no es la misma progresión.
  bool atDose(StrengthSetEvidence s) => switch (dose.kind) {
        DoseKind.carga => s.variant == dose.fromVariant &&
            load(s) - from >= StrengthDose.minLoadStepKg - 1e-9 &&
            load(s) - from <= StrengthDose.maxLoadStepKg + 1e-9,
        DoseKind.variante => s.variant == dose.toVariant,
        DoseKind.otra => false,
      };
  String kg(double v) => v == 0 ? 'peso corporal' : '${fmtDec(v)} kg';
  final target = dose.kind == DoseKind.carga ? '+2–5 kg de mochila' : (dose.toVariant ?? '');
  final done = later.sets.where(atDose).toList();
  if (done.isEmpty) {
    final s = later.sets.first;
    if (dose.kind == DoseKind.carga && s.variant != dose.fromVariant) {
      return 'aceptaste subir carga; $when cambiaste de variante '
          '(${dose.fromVariant ?? 'sin variante'} → ${s.variant ?? 'sin variante'}): no es la misma progresión';
    }
    final same = dose.kind == DoseKind.carga ? load(s) == from : s.variant == dose.fromVariant;
    if (same) {
      return 'aceptaste subir; $when repetiste ${dose.kind == DoseKind.carga ? kg(from) : (dose.fromVariant ?? 'la misma variante')}: '
          'no demuestra la subida';
    }
    return 'aceptaste subir ($target); $when usaste '
        '${dose.kind == DoseKind.carga ? kg(load(s)) : (s.variant ?? 'otra variante')}: no es la subida acordada';
  }
  final expected = dose.sets ?? later.sets.length;
  final label = dose.kind == DoseKind.carga ? kg(load(done.first)) : target;
  if (done.length < expected || done.length < later.sets.length) {
    return 'aceptaste subir a $label; $when sólo ${done.length} de $expected series con la subida: no demostrada';
  }
  String? cause;
  if (later.incomplete) {
    cause = 'la sesión quedó incompleta';
  } else if (done.any((s) => s.toFailure)) {
    cause = 'llegaste al fallo';
  } else if (done.firstWhereOrNull((s) => s.split) case final s?) {
    cause = 'hubo una serie partida${s.splitDetail == null ? '' : ' (${s.splitDetail})'}';
  } else if (done.any((s) => s.rir == 0)) {
    cause = 'una serie quedó a RIR 0';
  } else if (dose.repsMin != null && done.any((s) => s.reps < dose.repsMin!)) {
    final low = done.map((s) => s.reps).reduce((a, b) => a < b ? a : b);
    cause = 'la más baja fue $low, bajo el piso de ${dose.repsMin}';
  }
  if (cause != null) return 'subiste a $label; $when no se sostuvo: $cause';
  // Lo que se demuestra es lo guardado: sin fallo ni partidas y, si se anotó,
  // RIR ≥ 1. Un RIR sin anotar no es una reserva demostrada (008 lo admite
  // como dato no declarado).
  final noRir = done.where((s) => s.rir == null).length;
  final quality = noRir == 0
      ? 'sin fallo ni partidas, RIR ≥ 1 anotado'
      : 'sin fallo ni partidas; RIR no anotado en ${noRir == done.length ? 'ninguna' : '$noRir'}';
  return 'subiste a $label y se sostuvo $when (${done.length} series $quality)';
}

extension<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final x in this) {
      if (test(x)) return x;
    }
    return null;
  }
}

StrengthAdvice strengthAdvice({
  required String exercise,
  required StrengthSessionEvidence? evidence,
  required DateTime date,
  required int? repsMin,
  required int? repsMax,
  required int? plannedSets,
  bool perSide = false,
  int? planDayId,
  String? mode,
  bool tracksLoad = false,
  List<String> chain = const [],
}) {
  final e = evidence;
  StrengthAdvice keep(String why) => StrengthAdvice(exercise, StrengthStatus.mantener, why, sessionId: e?.sessionId);
  if (e == null) return StrengthAdvice(exercise, StrengthStatus.sinDatos, 'sin registro anterior');
  final hint = strengthProgressionHint(
    evidence: e,
    date: date,
    repsMin: repsMin,
    repsMax: repsMax,
    plannedSets: plannedSets,
    perSide: perSide,
    planDayId: planDayId,
    mode: mode,
    tracksLoad: tracksLoad,
    chain: chain,
  );
  if (hint != null) {
    return StrengthAdvice(exercise, StrengthStatus.subir, hint,
        sessionId: e.sessionId,
        dose: strengthDose(
            evidence: e,
            repsMin: repsMin,
            plannedSets: plannedSets,
            tracksLoad: tracksLoad,
            chain: chain,
            mode: mode,
            planDayId: planDayId));
  }
  final when = 'el ${formatShort(e.date)}';
  if (e.imported) return keep('lo anterior es historial importado');
  if (e.mode == 'tecnica') return keep('la última ($when) fue sesión técnica');
  if (e.mode != mode) return keep('la última ($when) fue otro protocolo');
  if (perSide) return keep('por lado: no se puede comparar lado a lado con lo guardado');
  if (e.incomplete) return keep('la sesión del ${formatShort(e.date)} quedó incompleta');
  if (e.sets.any((x) => x.toFailure)) return keep('$when llegaste al fallo');
  final split = e.sets.where((x) => x.split).firstOrNull;
  if (split != null) return keep('$when hubo una serie partida${split.splitDetail == null ? '' : ' (${split.splitDetail})'}');
  if (e.sets.any((x) => x.rir == 0)) return keep('$when una serie quedó a RIR 0');
  if (e.sets.any((x) => x.variant != e.sets.first.variant || x.loadKg != e.sets.first.loadKg)) {
    return keep('$when mezclaste variante o carga');
  }
  if (planDayId != null && e.planDayId != planDayId) return keep('la última fue en otro día del plan');
  if (repsMax != null && e.sets.any((x) => x.reps < repsMax)) {
    final best = e.sets.map((x) => x.reps).reduce((a, b) => a < b ? a : b);
    return keep('todavía no todas las series llegan a $repsMax ($when la más baja: $best)');
  }
  if (plannedSets != null && e.sets.length < plannedSets) return keep('$when hiciste ${e.sets.length} de $plannedSets series');
  return keep('se mantiene la dosis');
}

// ---------------------------------------------------------------------------
// Seguimiento de propuestas con criterios existentes (rondas de §2, fuerza de
// 008, escaleras de §19.10). No crea incrementos: registra la decisión sobre
// lo que esas reglas ya proponen. ID estable por evidencia: otra sesión u
// otro peldaño es otra propuesta.
// ---------------------------------------------------------------------------

/// "Hoy no" oculta la propuesta sólo ese día (la regla vuelve a ofrecerla en
/// la próxima sesión con la misma evidencia).
const proposalTodayOnlyDays = 1;

String roundsProposalId({required int fromRounds, required int toRounds, required int sessionId}) =>
    'rondas:$fromRounds>$toRounds:s$sessionId:p$coachPolicy';

String strengthProposalId(String exercise, int sessionId) => 'fuerza:$exercise:s$sessionId:p$coachPolicy';

String strengthProposalKind(String exercise) => 'fuerza:$exercise';

/// Escalera: identidad por peldaño y desde cuándo se está en él (subir o
/// bajar abre otra propuesta).
String ladderProposalId(String ladder, int step, DateTime since) =>
    'escalera:$ladder:$step>${step + 1}:${dayKey(since)}:p$coachPolicy';

/// ¿La decisión oculta hoy la propuesta? Rechazada: sí, para esa evidencia.
/// Pospuesta: hasta su fecha. Aceptada o sin decidir: no.
bool proposalHidden(ProposalRecord? r, DateTime day) {
  if (r == null) return false;
  if (r.status == ProposalStatus.rechazada) return true;
  if (r.status == ProposalStatus.pospuesta) {
    return r.reviewAfter == null || dateOnly(day).isBefore(dateOnly(r.reviewAfter!));
  }
  return false;
}

/// Sesión de la que salió una propuesta de fuerza (`...:s123:p1`).
int? proposalSessionId(String id) {
  final m = RegExp(r':s(\d+):p\d+$').firstMatch(id);
  return m == null ? null : int.parse(m.group(1)!);
}

/// La propuesta de rondas cuando la persona decidió no subir: se mantiene en
/// las de la última vez, con la razón a la vista.
ProgressionProposal heldProposal(ProgressionProposal p, ProposalStatus status) => ProgressionProposal(
      rounds: p.lastRounds,
      lastRounds: p.lastRounds,
      lastDate: p.lastDate,
      sessionId: p.sessionId,
      unmet: [status == ProposalStatus.rechazada ? 'decidiste mantener con esta evidencia' : 'hoy no (lo pospusiste)'],
    );

