/// Pasos: la palanca de gasto más barata que falta. Un día de oficina típico
/// registró ~1.935; la meta es 7.500 entre semana. El fin de semana es fútbol
/// y no tiene meta.
library;

import 'dates.dart';

/// Meta de pasos de un día, o null si ese día no tiene (sábado y domingo).
int? stepsGoalFor(DateTime day, int weekdayTarget) => day.weekday <= DateTime.friday ? weekdayTarget : null;

/// Resumen de pasos de un rango. Solo cuenta los días registrados: un día sin
/// cifra no es un día de 0 pasos.
class StepsSummary {
  const StepsSummary({
    required this.days,
    required this.average,
    required this.weekdayDays,
    this.weekdayAverage,
    required this.weekdaysAtGoal,
  });

  final int days;
  final int average;
  final int weekdayDays;
  final int? weekdayAverage;
  final int weekdaysAtGoal;
}

StepsSummary? summarizeSteps(Map<DateTime, int> byDay, int weekdayTarget) {
  if (byDay.isEmpty) return null;
  final weekdays = {
    for (final e in byDay.entries)
      if (stepsGoalFor(dateOnly(e.key), weekdayTarget) != null) e.key: e.value,
  };
  int avg(Iterable<int> v) => (v.reduce((a, b) => a + b) / v.length).round();
  return StepsSummary(
    days: byDay.length,
    average: avg(byDay.values),
    weekdayDays: weekdays.length,
    weekdayAverage: weekdays.isEmpty ? null : avg(weekdays.values),
    weekdaysAtGoal: weekdays.values.where((s) => s >= weekdayTarget).length,
  );
}

/// Qué cifra queda en un día al traer los pasos de Health Connect, o null si
/// no hay que tocar nada:
/// - un día vacío toma lo sincronizado;
/// - un día que ya venía de Health Connect se actualiza (el reloj sigue
///   sumando durante el día);
/// - un día anotado a mano solo cambia si lo sincronizado es mayor: si el
///   usuario escribió más, es que contó pasos que el reloj no vio.
int? mergeSyncedSteps({required int? current, required String? currentSource, required int synced}) {
  if (synced <= 0) return null;
  if (current == null) return synced;
  if (currentSource == 'health_connect') return synced == current ? null : synced;
  return synced > current ? synced : null;
}
