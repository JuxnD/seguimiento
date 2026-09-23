/// Modelo de entrada del informe: datos planos, sin dependencia de la base de
/// datos. `ReportRepository` lo arma; `buildReport` lo convierte en Markdown.
library;

import '../enums.dart';
import '../nutrition.dart';

class Targets {
  const Targets({
    this.proteinMin = 130,
    this.proteinMax = 160,
    this.kcalTarget = 2400,
    this.kcalFloor = 2000,
    this.minWarmupSec = 360,
    this.minCooldownSec = minCooldownSecDefault,
    this.measureIntervalDays = 21,
    this.lengthUnit = LengthUnit.cm,
  });

  /// Por debajo de 1 min el enfriamiento no cuenta como tal. Es una
  /// definición, no una meta: por eso no está en el perfil (la meta,
  /// `cooldownTargetSec`, sí).
  static const minCooldownSecDefault = 60;

  final int proteinMin;
  final int proteinMax;
  final int kcalTarget;
  final int kcalFloor;
  final int minWarmupSec;

  /// Por debajo de esto el enfriamiento no cuenta como tal.
  final int minCooldownSec;
  final int measureIntervalDays;
  final LengthUnit lengthUnit;
}

class PlanVersionInfo {
  const PlanVersionInfo({required this.number, required this.validFrom, required this.dayTypes, this.notes});

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
  });

  final String exercise;
  final int setIndex;
  final int reps;
  final bool split;
  final String? splitDetail;
  final bool toFailure;
}

class SessionEntry {
  const SessionEntry({
    required this.date,
    required this.type,
    this.startTime,
    this.totalSec = 0,
    this.warmupSec = 0,
    this.cooldownSec = 0,
    this.roundsDone,
    this.roundsEstimated = false,
    this.rpe,
    this.limitingExercise,
    this.context,
    this.notes,
    this.sets = const [],
    this.lapsSec = const [],
    this.techniqueOk,
    this.fullRange,
    this.recoveryOk,
    this.outOfPlan = false,
    this.incomplete = false,
    this.plannedRounds,
  });

  final DateTime date;
  final String? startTime;
  final SessionType type;
  final int totalSec;
  final int warmupSec;
  final int cooldownSec;
  final int? roundsDone;
  final bool roundsEstimated;
  final int? rpe;
  final String? limitingExercise;
  final String? context;
  final String? notes;
  final List<SetEntry> sets;

  /// Duración de cada ronda registrada con el contador (segundos).
  final List<int> lapsSec;

  /// El tipo no coincide con lo que pedía el plan ese día.
  final bool outOfPlan;

  /// Se cerró antes de completar el plan.
  final bool incomplete;

  /// Rondas (o series) que pedía el plan.
  final int? plannedRounds;

  // Condiciones de la regla de progresión; null = no registrado.
  final bool? techniqueOk;
  final bool? fullRange;
  final bool? recoveryOk;

  /// Motivos por los que esta sesión no habilita subir de ronda.
  List<String> get progressionBlockers => [
        if (sets.any((s) => s.split)) 'series partidas',
        if (sets.any((s) => s.toFailure)) 'series al fallo',
        if (techniqueOk == false) 'técnica',
        if (fullRange == false) 'rango reducido',
        if (recoveryOk == false) 'recuperación',
      ];
}

class FootballEntry {
  const FootballEntry({
    required this.date,
    required this.format,
    required this.minutes,
    this.steps,
    this.intensity,
    this.fatigueAfter,
    this.notes,
  });

  final DateTime date;
  final int format;
  final int minutes;
  final int? steps;
  final int? intensity;
  final int? fatigueAfter;
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
  const MealEntry({required this.date, required this.slot, this.time, this.items = const [], this.notes});

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
  const MeasurementEntry({required this.date, required this.site, required this.valueCm, this.fasted = true});

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
    this.football = const [],
    this.meals = const [],
    this.weightsInRange = const [],
    this.baselineWeight,
    this.measurementsInRange = const [],
    this.baselineMeasurements = const {},
    this.measurementDatesBefore = const [],
    this.notes,
  });

  final DateTime programStart;
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

  /// Últimas rondas hechas antes del rango, por tipo de circuito: es contra
  /// esto que se juzga si una sesión subió de ronda.
  final Map<SessionType, int> roundsBeforeRange;
  final List<FootballEntry> football;
  final List<MealEntry> meals;
  final List<WeightEntry> weightsInRange;
  final WeightEntry? baselineWeight;
  final List<MeasurementEntry> measurementsInRange;

  /// Primera medida registrada de cada sitio (línea base).
  final Map<MeasureSite, MeasurementEntry> baselineMeasurements;

  /// Fechas de medición anteriores al rango (para la alerta de intervalo).
  final List<DateTime> measurementDatesBefore;
  final String? notes;
}
