/// Resumen de un periodo (semana, mes o desde el inicio) en números: cuánto
/// se movió, cuántas repeticiones de cada ejercicio, pasos, gasto aproximado
/// y cómo comió. Lógica pura sobre `ReportInput`, la misma entrada del
/// informe, para que un número no se calcule de dos formas.
library;

import '../dates.dart';
import '../energy.dart';
import '../enums.dart';
import '../session_math.dart';
import 'report_input.dart';
import 'report_stats.dart';

/// Total de un ejercicio en el periodo.
class ExerciseTotal {
  const ExerciseTotal({required this.name, required this.amount, required this.isHold, this.sets = 0, this.previous});

  final String name;

  /// Repeticiones, o segundos si es un ejercicio por tiempo.
  final int amount;
  final bool isHold;
  final int sets;

  /// Lo del periodo anterior (null si no se cargó; 0 si no se hizo).
  final int? previous;

  int? get delta => previous == null ? null : amount - previous!;
}

/// Un día del periodo con su actividad, para las barras.
class DayActivity {
  const DayActivity({required this.date, this.steps, this.reps = 0, this.activeSec = 0, this.trained = false});

  final DateTime date;
  final int? steps;
  final int reps;
  final int activeSec;
  final bool trained;
}

class PeriodSummary {
  const PeriodSummary({
    required this.from,
    required this.to,
    required this.trainingSessions,
    required this.plannedSessions,
    this.plannedElapsed = 0,
    this.plannedWithoutData = 0,
    this.dataStart,
    required this.footballGames,
    required this.footballMinutes,
    required this.mobilitySessions,
    required this.trainingSec,
    required this.workSec,
    required this.exercises,
    required this.maxRounds,
    required this.stepsTotal,
    required this.stepsDays,
    required this.bestStepsDay,
    required this.weekdaysAtGoal,
    required this.weekdaysWithSteps,
    required this.distanceKm,
    required this.kcalTraining,
    required this.kcalFootball,
    required this.kcalSteps,
    required this.weightKg,
    required this.avgKcalIn,
    required this.avgProtein,
    required this.closedDays,
    required this.proteinDaysAtMin,
    required this.days,
    this.previous,
  });

  final DateTime from;
  final DateTime to;

  /// Sesiones del plan (circuito, bloques…). La movilidad va aparte.
  final int trainingSessions;

  /// Las que pedía el plan en el periodo.
  final int plannedSessions;

  /// Las que pedía el plan desde el primer dato hasta hoy (§16.16).
  final int plannedElapsed;

  /// Las del plan anteriores al primer dato en la app: sin datos, no faltas.
  final int plannedWithoutData;
  final DateTime? dataStart;
  final int footballGames;
  final int footballMinutes;
  final int mobilitySessions;

  /// Tiempo total de las sesiones (calentamiento a enfriamiento) + movilidad.
  final int trainingSec;

  /// Trabajo neto: sin calentamiento, enfriamiento ni descansos.
  final int workSec;
  final List<ExerciseTotal> exercises;
  final int? maxRounds;
  final int stepsTotal;

  /// Días con pasos registrados.
  final int stepsDays;
  final (DateTime, int)? bestStepsDay;
  final int weekdaysAtGoal;
  final int weekdaysWithSteps;
  final double distanceKm;

  /// Gasto aproximado por actividad (null sin peso).
  final double? kcalTraining;
  final double? kcalFootball;
  final double? kcalSteps;

  /// Peso con el que se estimó el gasto.
  final double? weightKg;
  final double? avgKcalIn;
  final double? avgProtein;
  final int closedDays;
  final int proteinDaysAtMin;
  final List<DayActivity> days;
  final PeriodSummary? previous;

  /// Minutos activos: entrenamiento, movilidad y fútbol.
  int get activeSec => trainingSec + footballMinutes * 60;

  int get totalReps => exercises.where((e) => !e.isHold).fold(0, (a, e) => a + e.amount);

  double? get stepsAvg => stepsDays == 0 ? null : stepsTotal / stepsDays;

  /// Suma del gasto por actividad; null si no hay peso para estimarlo.
  double? get kcalBurned {
    if (weightKg == null) return null;
    return (kcalTraining ?? 0) + (kcalFootball ?? 0) + (kcalSteps ?? 0);
  }

  int? repsOf(String name) {
    for (final e in exercises) {
      if (e.name == name) return e.amount;
    }
    return null;
  }

  bool get isEmpty => trainingSessions == 0 && footballGames == 0 && mobilitySessions == 0 && stepsDays == 0 && closedDays == 0;
}

/// Arma el resumen del rango de `input` (y del anterior, si se cargó).
/// `heightCm` afina la zancada para los kilómetros; sin ella se usa 0,75 m.
PeriodSummary summarizePeriod(ReportInput input, {double? heightCm}) =>
    _summarize(input, heightCm: heightCm, withPrevious: true);

PeriodSummary _summarize(ReportInput input, {double? heightCm, required bool withPrevious}) {
  final stats = ReportStats(input);
  final weight = _weightFor(input);

  // Sesiones del plan y movilidad.
  var trainingSec = 0, workSec = 0;
  double? kcalTraining = weight == null ? null : 0;
  final reps = <String, int>{};
  final sets = <String, int>{};
  final repsByDay = <String, int>{};
  final activeByDay = <String, int>{};
  final trainedDays = <String>{};
  for (final s in input.sessions) {
    final net = circuitNetSec(totalSec: s.totalSec, warmupSec: s.warmupSec, cooldownSec: s.cooldownSec, restSec: s.restSec);
    trainingSec += s.totalSec;
    workSec += net;
    final k = dayKey(s.date);
    activeByDay[k] = (activeByDay[k] ?? 0) + s.totalSec;
    trainedDays.add(k);
    final kcal = sessionKcal(
      type: s.type,
      weightKg: weight,
      warmupSec: s.warmupSec,
      workSec: net,
      restSec: s.restSec,
      cooldownSec: s.cooldownSec,
    );
    if (kcal != null) kcalTraining = kcalTraining! + kcal;
    for (final set in s.sets) {
      reps[set.exercise] = (reps[set.exercise] ?? 0) + set.reps;
      sets[set.exercise] = (sets[set.exercise] ?? 0) + 1;
      if (!input.holdExercises.contains(set.exercise)) repsByDay[k] = (repsByDay[k] ?? 0) + set.reps;
    }
  }
  for (final m in input.mobility) {
    trainingSec += m.totalSec;
    final k = dayKey(m.date);
    activeByDay[k] = (activeByDay[k] ?? 0) + m.totalSec;
    final kcal = sessionKcal(type: SessionType.movilidad, weightKg: weight, workSec: m.totalSec);
    if (kcal != null) kcalTraining = kcalTraining! + kcal;
  }

  // Fútbol.
  var footballMinutes = 0;
  double? kcalFootball = weight == null ? null : 0;
  final footballDays = <String>{};
  for (final g in input.football) {
    footballMinutes += g.minutes;
    final k = dayKey(g.date);
    footballDays.add(k);
    activeByDay[k] = (activeByDay[k] ?? 0) + g.minutes * 60;
    final kcal = footballKcal(minutes: g.minutes, weightKg: weight);
    if (kcal != null) kcalFootball = kcalFootball! + kcal;
  }

  // Pasos. El día de partido el reloj ya cuenta el partido: esos pasos no se
  // suman al gasto para no contar dos veces lo mismo.
  final inRange = {
    for (final e in input.steps.entries)
      if (!e.key.isBefore(dateOnly(input.rangeStart)) && !e.key.isAfter(dateOnly(input.rangeEnd))) dayKey(e.key): e.value,
  };
  var stepsTotal = 0, stepsForKcal = 0, weekdaysAtGoal = 0, weekdaysWithSteps = 0;
  (DateTime, int)? best;
  for (final e in inRange.entries) {
    stepsTotal += e.value;
    if (!footballDays.contains(e.key)) stepsForKcal += e.value;
    final day = parseDay(e.key);
    if (best == null || e.value > best.$2) best = (day, e.value);
    if (day.weekday <= DateTime.friday) {
      weekdaysWithSteps++;
      if (e.value >= input.targets.stepsTarget) weekdaysAtGoal++;
    }
  }

  // Ejercicios, con el periodo anterior para comparar.
  final previous = withPrevious && input.previous != null
      ? _summarize(input.previous!, heightCm: heightCm, withPrevious: false)
      : null;
  final exercises = [
    for (final e in reps.entries)
      ExerciseTotal(
        name: e.key,
        amount: e.value,
        isHold: input.holdExercises.contains(e.key),
        sets: sets[e.key] ?? 0,
        previous: previous == null ? null : (previous.repsOf(e.key) ?? 0),
      ),
  ]..sort((a, b) {
      if (a.isHold != b.isHold) return a.isHold ? 1 : -1;
      return b.amount.compareTo(a.amount);
    });

  final closed = stats.closedDays;
  final proteinAtMin = closed.where((d) => stats.macrosOn(d)!.protein >= input.targets.proteinMin).length;

  return PeriodSummary(
    from: dateOnly(input.rangeStart),
    to: dateOnly(input.rangeEnd),
    trainingSessions: input.sessions.length,
    plannedSessions: stats.expectedTraining,
    plannedElapsed: stats.plannedElapsedWithData,
    plannedWithoutData: stats.plannedWithoutData,
    dataStart: input.dataStart,
    footballGames: input.football.length,
    footballMinutes: footballMinutes,
    mobilitySessions: input.mobility.length,
    trainingSec: trainingSec,
    workSec: workSec,
    exercises: exercises,
    maxRounds: stats.maxRoundsInRange,
    stepsTotal: stepsTotal,
    stepsDays: inRange.length,
    bestStepsDay: best,
    weekdaysAtGoal: weekdaysAtGoal,
    weekdaysWithSteps: weekdaysWithSteps,
    distanceKm: stepsKm(stepsTotal, heightCm: heightCm),
    kcalTraining: kcalTraining,
    kcalFootball: kcalFootball,
    kcalSteps: stepsKcal(stepsForKcal, weightKg: weight, heightCm: heightCm) ?? (weight == null ? null : 0),
    weightKg: weight,
    avgKcalIn: stats.avgKcal,
    avgProtein: stats.avgProtein,
    closedDays: closed.length,
    proteinDaysAtMin: proteinAtMin,
    days: [
      for (final d in stats.days)
        DayActivity(
          date: d,
          steps: inRange[dayKey(d)],
          reps: repsByDay[dayKey(d)] ?? 0,
          activeSec: activeByDay[dayKey(d)] ?? 0,
          trained: trainedDays.contains(dayKey(d)) || footballDays.contains(dayKey(d)),
        ),
    ],
    previous: previous,
  );
}

/// Peso para estimar el gasto: el último del rango o, si no hay, el primero
/// que se registró.
double? _weightFor(ReportInput input) {
  if (input.weightsInRange.isNotEmpty) {
    final sorted = [...input.weightsInRange]..sort((a, b) => a.date.compareTo(b.date));
    return sorted.last.kg;
  }
  return input.baselineWeight?.kg;
}
