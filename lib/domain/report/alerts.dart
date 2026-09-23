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
  // El plan pide avisar a partir de 3 sesiones con el mismo ejercicio partido.
  final repeated = splitSessions.entries.where((e) => e.value >= 3).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in repeated) {
    out.add('${e.key} partidas en ${e.value} sesiones');
  }

  for (final (session, before, blockers) in progressionViolations(s)) {
    out.add('Subiste de $before a ${session.roundsDone} rondas el ${formatShort(session.date)} '
        'sin cumplir la regla de progresión (${blockers.join(', ')})');
  }

  final shortWarmups = s.input.sessions.where((x) => x.warmupSec < t.minWarmupSec).length;
  if (shortWarmups > 0) {
    out.add('Calentamiento < ${fmtDec(t.minWarmupSec / 60)} min en $shortWarmups '
        '${shortWarmups == 1 ? 'sesión' : 'sesiones'}');
  }

  final shortCooldowns = s.input.sessions.where((x) => x.cooldownSec < t.minCooldownSec).length;
  if (shortCooldowns > 0) {
    out.add('Enfriamiento < ${fmtDec(t.minCooldownSec / 60)} min en $shortCooldowns '
        '${shortCooldowns == 1 ? 'sesión' : 'sesiones'}');
  }

  final outOfPlan = s.input.sessions.where((x) => x.outOfPlan).toList();
  if (outOfPlan.isNotEmpty) {
    out.add('Fuera de plan: ${outOfPlan.map((x) => '${x.type.label} el ${formatShort(x.date)}').join(', ')}');
  }

  final unfinished = s.input.sessions.where((x) => x.incomplete).toList();
  if (unfinished.isNotEmpty) {
    out.add('Sesiones cerradas antes de completar el plan: '
        '${unfinished.map((x) => formatShort(x.date)).join(', ')}');
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

  return out;
}

String _days(List<DateTime> days) => days.map((d) => '${weekdayShort(d.weekday)} ${d.day}').join(', ');

