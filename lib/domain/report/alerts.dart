import '../dates.dart';
import '../enums.dart';
import '../format.dart';
import 'report_stats.dart';

/// Alertas automáticas del informe. Cada regla es independiente y devuelve
/// texto listo para una viñeta Markdown.
List<String> buildAlerts(ReportStats s) {
  final t = s.input.targets;
  final out = <String>[];

  // Calidad del dato primero: sin esto los promedios engañan.
  if (s.unloggedDays.isNotEmpty) {
    out.add('Sin registro de comidas: ${_days(s.unloggedDays)} — excluidos de los promedios');
  }

  for (final streak in s.lowKcalStreaks.where((st) => st.length >= 2)) {
    out.add('${streak.length} días seguidos bajo ${fmtInt(t.kcalFloor)} kcal (${_days(streak)})');
  }

  final p = s.avgProtein;
  if (p != null && p < t.proteinMin) {
    out.add('Proteína promedio ${fmtInt(p)} g, bajo el mínimo de ${t.proteinMin} g');
  }

  final done = s.input.sessions.length;
  if (s.expectedTraining > 0 && done < s.expectedTraining) {
    out.add('Sesiones por debajo del plan: $done de ${s.expectedTraining}');
  }

  // Mismo ejercicio partido en varias sesiones.
  final splitSessions = <String, int>{};
  for (final session in s.input.sessions) {
    final names = session.sets.where((x) => x.split).map((x) => x.exercise).toSet();
    for (final n in names) {
      splitSessions[n] = (splitSessions[n] ?? 0) + 1;
    }
  }
  final repeated = splitSessions.entries.where((e) => e.value >= 2).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in repeated) {
    out.add('${e.key} partidas en ${e.value} sesiones');
  }

  final shortWarmups = s.input.sessions.where((x) => x.warmupSec < t.minWarmupSec).length;
  if (shortWarmups > 0) {
    out.add('Calentamiento < ${fmtDec(t.minWarmupSec / 60)} min en $shortWarmups '
        '${shortWarmups == 1 ? 'sesión' : 'sesiones'}');
  }

  final estimated = s.input.sessions.where((x) => x.roundsEstimated).length;
  if (estimated > 0) {
    out.add('Rondas estimadas por tiempo (no contadas) en $estimated '
        '${estimated == 1 ? 'sesión' : 'sesiones'}');
  }

  // Medición antes de tiempo.
  final measureDates = {
    for (final d in s.input.measurementDatesBefore) dayKey(d): d,
    for (final m in s.input.measurementsInRange) dayKey(m.date): m.date,
  }.values.toList()
    ..sort();
  for (var i = 1; i < measureDates.length; i++) {
    final cur = measureDates[i];
    if (!s.input.measurementsInRange.any((m) => dayKey(m.date) == dayKey(cur))) continue;
    final gap = daysBetween(measureDates[i - 1], cur);
    if (gap < t.measureIntervalDays) {
      out.add('Medición del ${formatShort(cur)} a solo $gap días de la anterior '
          '(mínimo ${t.measureIntervalDays})');
    }
  }

  final notFasted = s.input.measurementsInRange.where((m) => !m.fasted).map((m) => dayKey(m.date)).toSet();
  if (notFasted.isNotEmpty) {
    out.add('Medidas tomadas sin ayunas: ${notFasted.map((k) => formatShort(parseDay(k))).join(', ')}');
  }

  final mismatch = s.input.sessions.where((x) {
    final plan = s.planFor(x.date);
    if (plan == null) return false;
    final planned = plan.typeFor(x.date.weekday);
    return !planned.isTraining;
  }).length;
  if (mismatch > 0) {
    out.add('$mismatch ${mismatch == 1 ? 'sesión' : 'sesiones'} en día no planificado para entrenar');
  }

  return out;
}

String _days(List<DateTime> days) => days.map((d) => '${weekdayShort(d.weekday)} ${d.day}').join(', ');

