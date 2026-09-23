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
