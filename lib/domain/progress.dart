/// Métricas de progreso que alimentan la pantalla Hoy y las gráficas.
/// Lógica pura: recibe fechas y números, devuelve números.
library;

import 'dates.dart';

/// Racha de días entrenados hasta hoy. Un día de entrenamiento sin sesión la
/// corta; un día de descanso o fútbol no la corta ni la alarga.
///
/// `trainingDates` son los días con sesión registrada; `isRestDay` dice si un
/// día no exigía entrenar.
int currentStreak({
  required DateTime today,
  required Set<String> trainingDates,
  required bool Function(DateTime) isRestDay,
  int maxLookback = 400,
}) {
  var streak = 0;
  var day = dateOnly(today);
  for (var i = 0; i < maxLookback; i++) {
    final key = dayKey(day);
    if (trainingDates.contains(key)) {
      streak++;
    } else if (isRestDay(day)) {
      // Descanso planificado: no suma, pero tampoco rompe.
    } else if (i == 0) {
      // Hoy todavía puede entrenarse: no rompe la racha.
    } else {
      break;
    }
    day = addDays(day, -1);
  }
  return streak;
}

/// Progreso hacia una meta, acotado a [0, 1] para pintar anillos.
double goalProgress(num value, num goal) {
  if (goal <= 0) return 0;
  final v = value / goal;
  return v.isNaN ? 0 : v.clamp(0, 1).toDouble();
}

/// Un récord es superar el máximo anterior, no igualarlo.
bool isRecord(int rounds, int? previousMax) => previousMax == null ? rounds > 0 : rounds > previousMax;

/// Punto de una serie para las gráficas.
class SeriesPoint {
  const SeriesPoint(this.date, this.value, {this.label});

  final DateTime date;
  final double value;
  final String? label;
}

/// Agrupa valores por día, sumando los del mismo día.
List<SeriesPoint> dailyTotals(Iterable<(DateTime, double)> entries) {
  final byDay = <String, double>{};
  for (final (date, value) in entries) {
    final k = dayKey(date);
    byDay[k] = (byDay[k] ?? 0) + value;
  }
  final keys = byDay.keys.toList()..sort();
  return [for (final k in keys) SeriesPoint(parseDay(k), byDay[k]!)];
}

/// Rellena los días sin dato con 0 para que la gráfica no invente pendientes.
List<SeriesPoint> fillDays(List<SeriesPoint> points, DateTime from, DateTime to) {
  final byDay = {for (final p in points) dayKey(p.date): p.value};
  final out = <SeriesPoint>[];
  for (var d = dateOnly(from); !d.isAfter(dateOnly(to)); d = addDays(d, 1)) {
    out.add(SeriesPoint(d, byDay[dayKey(d)] ?? 0));
  }
  return out;
}

/// Máximo de la serie, útil para escalar el eje.
double seriesMax(List<SeriesPoint> points, {double atLeast = 1}) =>
    points.isEmpty ? atLeast : points.map((p) => p.value).reduce((a, b) => a > b ? a : b).clamp(atLeast, double.infinity);

/// Comparación con la sesión anterior del mismo tipo, para el cierre.
class SessionComparison {
  const SessionComparison({
    required this.rounds,
    this.plannedRounds,
    this.meanLapSec,
    this.previousRounds,
    this.previousMeanLapSec,
    this.previousDateLabel,
    this.incomplete = false,
    this.isRecord = false,
  });

  final int? rounds;
  final int? plannedRounds;
  final int? meanLapSec;
  final int? previousRounds;
  final int? previousMeanLapSec;

  /// "el lunes 21", para que el mensaje diga contra qué se compara.
  final String? previousDateLabel;
  final bool incomplete;
  final bool isRecord;
}

/// Titular y frase de cierre. Siempre dice algo verdadero y concreto: nada de
/// "¡buen trabajo!" genérico si el dato no lo respalda.
(String, String) sessionPraise(SessionComparison c) {
  final rounds = c.rounds;
  final since = c.previousDateLabel == null ? '' : ' que ${c.previousDateLabel}';

  if (c.isRecord && rounds != null) {
    return ('¡Récord!', '$rounds rondas: nunca habías hecho tantas.');
  }
  if (c.incomplete) {
    final done = rounds == null ? 'Lo que hiciste' : '$rounds de ${c.plannedRounds ?? '?'} ${c.plannedRounds == 1 ? 'ronda' : 'rondas'}';
    return ('Sesión registrada', '$done. Parar a tiempo también es entrenar bien.');
  }
  if (rounds != null && c.previousRounds != null && rounds > c.previousRounds!) {
    final diff = rounds - c.previousRounds!;
    return ('¡Subiste!', '+$diff ${diff == 1 ? 'ronda' : 'rondas'} más$since.');
  }
  if (c.meanLapSec != null && c.previousMeanLapSec != null) {
    final faster = c.previousMeanLapSec! - c.meanLapSec!;
    if (faster >= 2) {
      return ('Más rápido', 'Cada ronda te tomó $faster s menos$since.');
    }
  }
  if (rounds != null && c.plannedRounds != null && rounds >= c.plannedRounds!) {
    final unit = c.plannedRounds == 1 ? 'ronda' : 'rondas';
    return ('Plan cumplido', '$rounds de ${c.plannedRounds} $unit. Constancia es lo que suma.');
  }
  return ('Sesión completa', 'Un día más en la racha.');
}

/// Cuándo toca medir. La fecha acordada (perfil) manda mientras no se haya
/// medido ya en o después de ella; si no, la última toma + la ventana
/// [mínimo, máximo] de días del perfil.
class MeasurementDue {
  const MeasurementDue({required this.dueDate, required this.windowEnd, required this.today, this.agreed = false});

  /// Desde cuándo toca medir.
  final DateTime dueDate;

  /// Hasta cuándo es buen momento; después, la medición va atrasada.
  final DateTime windowEnd;
  final DateTime today;

  /// true si sale de una fecha acordada, no del intervalo.
  final bool agreed;

  /// > 0: faltan días. ≤ 0: toca medir.
  int get daysLeft => daysBetween(today, dueDate);

  /// Días pasados del final de la ventana (0 si aún se está a tiempo).
  int get daysLate {
    final late = daysBetween(windowEnd, today);
    return late > 0 ? late : 0;
  }

  bool get isDue => daysLeft <= 0;
}

/// La fecha acordada solo vale si todavía no se midió en o después de ella.
DateTime? effectiveAgreedDate({DateTime? agreed, DateTime? lastMeasurement}) {
  if (agreed == null) return null;
  if (lastMeasurement != null && !lastMeasurement.isBefore(dateOnly(agreed))) return null;
  return dateOnly(agreed);
}

/// null si no hay ni línea base ni fecha acordada: no hay con qué calcular.
MeasurementDue? measurementDue({
  required DateTime today,
  DateTime? lastMeasurement,
  DateTime? agreed,
  required int minDays,
  required int maxDays,
}) {
  final day = dateOnly(today);
  final fixed = effectiveAgreedDate(agreed: agreed, lastMeasurement: lastMeasurement);
  if (fixed != null) return MeasurementDue(dueDate: fixed, windowEnd: fixed, today: day, agreed: true);
  if (lastMeasurement == null) return null;
  final last = dateOnly(lastMeasurement);
  return MeasurementDue(
    dueDate: addDays(last, minDays),
    windowEnd: addDays(last, maxDays < minDays ? minDays : maxDays),
    today: day,
  );
}
