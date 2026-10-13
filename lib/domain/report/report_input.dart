/// Modelo de entrada del informe: datos planos, sin dependencia de la base de
/// datos. `ReportRepository` lo arma; `buildReport` lo convierte en Markdown.
library;

import '../enums.dart';
import '../leg_chain.dart' show GroupChain;
import '../fitness_test.dart' show TestPart, TestResult;
import '../readiness.dart' show ReadinessWeek;
import '../progress.dart';
import '../nutrition.dart';
import '../goal_history.dart';

/// Un test de la agenda efectiva del bloque.
class TestAgendaEntry {
  const TestAgendaEntry({
    required this.round,
    required this.part,
    required this.planned,
    required this.date,
    required this.moves,
    required this.maxMoves,
    this.condition,
  });

  final int round;
  final TestPart part;
  final DateTime planned;
  final DateTime date;
  final int moves;
  final int maxMoves;

  /// Por qué ese día no se hace o de qué depende; null = se hace.
  final String? condition;
}

/// Un intento de test guardado (cabecera del esquema 25).
class TestAttemptEntry {
  const TestAttemptEntry({
    required this.id,
    required this.date,
    required this.round,
    required this.part,
    required this.protocolId,
    required this.sessionLinked,
  });

  final int id;
  final DateTime date;
  final int round;
  final TestPart part;
  final String protocolId;

  /// Tiene su sesión de test; false si se borró o nunca la tuvo.
  final bool sessionLinked;
}

/// Una toma de benchmarks de movilidad.
class BenchmarkScheduleEntry {
  const BenchmarkScheduleEntry({
    required this.planned,
    required this.date,
    required this.withMovedLegTest,
    required this.missing,
    required this.total,
  });

  final DateTime planned;
  final DateTime date;
  final bool withMovedLegTest;

  /// Mediciones que faltan (`knee_to_wall` cuenta por lado).
  final List<String> missing;

  /// Mediciones de una toma completa.
  final int total;
}

class Targets {
  const Targets({
    this.proteinMin = 130,
    this.proteinMax = 160,
    this.kcalTarget = 2400,
    this.kcalTargetFootball,
    this.kcalFloor = 2000,
    this.minWarmupSec = 360,
    this.minCooldownSec = minCooldownSecDefault,
    this.measureIntervalDays = 21,
    this.lengthUnit = LengthUnit.cm,
    this.stepsTarget = 5000,
  });

  /// Por debajo de 1 min el enfriamiento no cuenta como tal. Es una
  /// definición, no una meta: por eso no está en el perfil (la meta,
  /// `cooldownTargetSec`, sí).
  static const minCooldownSecDefault = 60;

  final int proteinMin;
  final int proteinMax;
  final int kcalTarget;

  /// Meta de los días de fútbol (sábado y domingo); null = la misma.
  final int? kcalTargetFootball;
  final int kcalFloor;
  final int minWarmupSec;

  /// Por debajo de esto el enfriamiento no cuenta como tal.
  final int minCooldownSec;
  final int measureIntervalDays;
  final LengthUnit lengthUnit;

  /// Pasos diarios entre semana.
  final int stepsTarget;
}

class PlanVersionInfo {
  const PlanVersionInfo(
      {required this.number,
      required this.validFrom,
      required this.dayTypes,
      this.notes});

  /// 1-based: v1, v2…
  final int number;
  final DateTime validFrom;

  /// weekday (1 = lunes … 7 = domingo) → tipo. Días ausentes = descanso.
  final Map<int, DayType> dayTypes;
  final String? notes;

  DayType typeFor(int weekday) => dayTypes[weekday] ?? DayType.descanso;
}

class SetEntry {
  const SetEntry({
    required this.exercise,
    required this.setIndex,
    required this.reps,
    this.split = false,
    this.splitDetail,
    this.toFailure = false,
    this.loadKg,
    this.variant,
    this.rir,
  });

  final String exercise;
  final int setIndex;
  final int reps;
  final bool split;
  final String? splitDetail;
  final bool toFailure;

  /// Carga externa (kg). null = peso corporal.
  final double? loadKg;

  /// Variante de la progresión usada (§18.4).
  final String? variant;

  /// Repeticiones en reserva (§19.2). null = no se anotó.
  final int? rir;
}

class SessionEntry {
  const SessionEntry({
    this.id,
    required this.date,
    required this.type,
    this.startTime,
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
    this.sets = const [],
    this.lapsSec = const [],
    this.roundWorkSec = const [],
    this.roundRestSec = const [],
    this.techniqueOk,
    this.fullRange,
    this.recoveryOk,
    this.outOfPlan = false,
    this.incomplete = false,
    this.plannedRounds,
    this.pendingReview = false,
    this.mode,
    this.extraReps,
    this.imported = false,
  });

  final int? id;
  final DateTime date;
  final String? startTime;
  final SessionType type;
  final int totalSec;
  final int warmupSec;
  final int cooldownSec;

  /// Descansos sumados (0 si no se registraron).
  final int restSec;
  final int? roundsDone;
  final bool roundsEstimated;

  /// Del historial anterior a la app (§16.16): suma a totales, no es marca.
  final bool imported;
  final int? rpe;
  final String? limitingExercise;
  final String? context;
  final String? notes;
  final List<SetEntry> sets;

  /// Duración de cada ronda registrada con el contador (segundos). Incluye
  /// el descanso previo: por eso la primera parece más rápida.
  final List<int> lapsSec;

  /// Trabajo de cada ronda sin descansos. Vacío si no se midió (sesiones
  /// anteriores al esquema 8 o del contador libre).
  final List<int> roundWorkSec;

  /// Descanso después de cada ronda (0 en la última). Vacío si no se midió.
  final List<int> roundRestSec;

  /// El tipo no coincide con lo que pedía el plan ese día.
  final bool outOfPlan;

  /// Se cerró antes de completar el plan.
  final bool incomplete;

  /// Rondas (o series) que pedía el plan.
  final int? plannedRounds;

  /// Guardada sola al terminar el cronómetro y sin revisar (falta el RPE).
  final bool pendingReview;

  /// Resistencia v3: 'cindy', 'tabata' o 'porTiempo'.
  final String? mode;

  /// Cindy: reps de la ronda a medias.
  final int? extraReps;

  /// "Resistencia (Cindy)" en vez de solo "Resistencia".
  String get typeLabel => switch (mode) {
        'cindy' => '${type.label} (Cindy)',
        'tabata' => '${type.label} (Tabata)',
        'porTiempo' => '${type.label} (10 rondas por tiempo)',
        _ => type.label,
      };

  // Condiciones de la regla de progresión; null = no registrado.
  final bool? techniqueOk;
  final bool? fullRange;
  final bool? recoveryOk;

  /// Motivos por los que esta sesión no habilita subir de ronda.
  ProgressionProposal? get progressionEvidence => imported || roundsEstimated
      ? null
      : proposeProgression(
          lastRounds: roundsDone,
          lastPlanned: plannedRounds,
          anySplit: sets.any((s) => s.split),
          anyFailure: sets.any((s) => s.toFailure),
          techniqueOk: techniqueOk,
          fullRange: fullRange,
          recoveryOk: recoveryOk,
          incomplete: incomplete,
        );

  List<String> get progressionBlockers =>
      progressionEvidence?.unmet ?? ['rondas sin registrar'];
}

class MobilityEntry {
  const MobilityEntry({required this.date, required this.totalSec});

  final DateTime date;
  final int totalSec;
}

class FootballEntry {
  const FootballEntry({
    required this.date,
    required this.format,
    required this.minutes,
    this.steps,
    this.intensity,
    this.fatigueAfter,
    this.knock,
    this.notes,
  });

  final DateTime date;
  final int format;
  final int minutes;
  final int? steps;
  final int? intensity;
  final int? fatigueAfter;

  /// Hubo golpe o molestia. null = no se registró.
  final bool? knock;
  final String? notes;
}

class MealItemEntry {
  const MealItemEntry({
    required this.label,
    required this.macros,
    this.quantityLabel,
    this.sourceVerified,
  });

  final String label;
  final String? quantityLabel;
  final Macros macros;

  /// true = macros de etiqueta; false = de tabla de referencia; null = entrada
  /// libre estimada a ojo.
  final bool? sourceVerified;
}

class MealEntry {
  const MealEntry(
      {required this.date,
      required this.slot,
      this.time,
      this.items = const [],
      this.notes});

  final DateTime date;
  final MealSlot slot;
  final String? time;
  final List<MealItemEntry> items;
  final String? notes;

  Macros get macros => Macros.sum(items.map((i) => i.macros));
}

class WeightEntry {
  const WeightEntry({required this.date, required this.kg, this.fasted = true});

  final DateTime date;
  final double kg;
  final bool fasted;
}

class MeasurementEntry {
  const MeasurementEntry(
      {required this.date,
      required this.site,
      required this.valueCm,
      this.fasted = true});

  final DateTime date;
  final MeasureSite site;
  final double valueCm;
  final bool fasted;
}

class ReportInput {
  const ReportInput({
    required this.programStart,
    required this.rangeStart,
    required this.rangeEnd,
    required this.today,
    this.targets = const Targets(),
    this.planVersions = const [],
    this.sessions = const [],
    this.previousRoundsRecord,
    this.roundsBeforeRange = const {},
    this.sessionsBeforeRange = const {},
    this.football = const [],
    this.meals = const [],
    this.weightsInRange = const [],
    this.baselineWeight,
    this.measurementsInRange = const [],
    this.baselineMeasurements = const {},
    this.measurementDatesBefore = const [],
    this.closedDays = const {},
    this.steps = const {},
    this.sleep = const {},
    this.mobility = const [],
    this.holdExercises = const {},
    this.perSideExercises = const {},
    this.dataStart,
    this.goals,
    this.previous,
    this.notes,
    this.recovery,
    this.kneeStairs = const {},
    this.mobilityBenchmarks = const [],
    this.legChains,
    this.testAgenda = const [],
    this.testAttempts = const [],
    this.testResults = const [],
    this.benchmarkSchedule = const [],
  });

  /// Tests del bloque previstos o efectivos en el rango (agenda efectiva).
  final List<TestAgendaEntry> testAgenda;

  /// Intentos de test registrados en el rango.
  final List<TestAttemptEntry> testAttempts;

  /// Todos los resultados hasta el final del rango (con y sin intento), para
  /// comparar cada intento sólo con su misma línea base.
  final List<TestResult> testResults;

  /// Tomas de benchmarks de movilidad que caen en el rango.
  final List<BenchmarkScheduleEntry> benchmarkSchedule;

  final DateTime programStart;

  /// Recuperación activa de la semana (§19.17); null = no se calculó.
  final ReadinessWeek? recovery;
  final Map<DateTime, int?> kneeStairs;

  /// Explicit optional measurements; never converted into training workload.
  final List<String> mobilityBenchmarks;

  /// Cadenas de días intensos al cierre del periodo (§16.24, plan 039), con
  /// la misma clasificación que el Plan B de Hoy. null = no se calculó.
  final ({GroupChain legs, GroupChain torso})? legChains;
  final DateTime rangeStart;

  /// Inclusivo.
  final DateTime rangeEnd;

  /// Para no marcar como "sin registro" días que aún no llegan.
  final DateTime today;
  final Targets targets;

  /// Todas las versiones del plan, en cualquier orden.
  final List<PlanVersionInfo> planVersions;
  final List<SessionEntry> sessions;

  /// Máximo de rondas de circuito antes del rango.
  final int? previousRoundsRecord;

  /// Últimas rondas por tipo, conservadas para lectores cuantitativos legados.
  /// La evaluación de progresión requiere sessionsBeforeRange.
  final Map<SessionType, int> roundsBeforeRange;

  /// Última sesión completa por tipo antes del rango. Los enteros legados
  /// anteriores no prueban calidad ni permiso para progresar.
  final Map<SessionType, SessionEntry> sessionsBeforeRange;
  final List<FootballEntry> football;
  final List<MealEntry> meals;
  final List<WeightEntry> weightsInRange;
  final WeightEntry? baselineWeight;
  final List<MeasurementEntry> measurementsInRange;

  /// Primera medida registrada de cada sitio (línea base).
  final Map<MeasureSite, MeasurementEntry> baselineMeasurements;

  /// Fechas de medición anteriores al rango (para la alerta de intervalo).
  final List<DateTime> measurementDatesBefore;

  /// Horas en cama por mañana (§19.3).
  final Map<DateTime, double> sleep;

  /// Días (`YYYY-MM-DD`) que el usuario cerró a mano aunque les falte una
  /// comida principal.
  final Set<String> closedDays;

  /// Pasos registrados por día del rango. Un día ausente no es un día de 0.
  final Map<DateTime, int> steps;

  /// Sesiones de movilidad: opcionales, fuera de `sessions` para que no
  /// cuenten en adherencia, récords ni alertas.
  final List<MobilityEntry> mobility;

  /// Ejercicios por tiempo (plancha, hollow): sus series guardan segundos, no
  /// repeticiones, y así se muestran.
  final Set<String> holdExercises;

  /// Ejercicios por lado (búlgara, peso muerto a una pierna…): el cronómetro
  /// guarda derecho e izquierdo como dos entradas seguidas por serie.
  final Set<String> perSideExercises;

  /// Primer día con algo registrado en la app (incluido el historial
  /// importado). Los días del plan anteriores no son faltas: no hay datos
  /// (§16.16). null = no se sabe; cuenta todo el rango.
  final DateTime? dataStart;

  /// Metas con historia (plan 009): cada día se mide con la suya. null =
  /// sin historia cargada: se usa `targets` como hasta ahora.
  final GoalHistory? goals;

  /// Meta de un día: la vigente ese día; null si es "meta histórica no
  /// registrada" (no se clasifica). Sin historia, la de `targets`.
  double? goalOn(GoalMetric metric, DateTime day, num fallback) {
    final at = referenceOn(metric, day, fallback);
    return at.known ? at.value : null;
  }

  /// Visual comparisons fail closed when a loaded history has no dated value.
  GoalAt referenceOn(GoalMetric metric, DateTime day, num? fallback) {
    return goalReferenceOn(goals, metric, day, fallback: fallback);
  }

  /// Reuses the established Saturday/Sunday calendar. The 0/1 selector is
  /// internal, never a calorie amount: nullable/unknown evidence stays so.
  GoalAt kcalReferenceOn(DateTime day) {
    return kcalGoalReferenceOn(goals, day,
        weekdayFallback: targets.kcalTarget,
        footballFallback: targets.kcalTargetFootball);
  }

  /// El rango anterior del mismo largo (la semana pasada), para comparar.
  /// null en el propio rango anterior: la comparación no se encadena.
  final ReportInput? previous;
  final String? notes;
}
