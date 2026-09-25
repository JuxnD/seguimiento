import '../dates.dart';
import '../enums.dart';
import '../format.dart';
import 'report_input.dart';
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
  // Hoy todavía se está registrando: no es un día incompleto.
  final incomplete = s.incompleteDays.where((d) => dayKey(d) != dayKey(s.input.today)).toList();
  if (incomplete.isNotEmpty) {
    out.add('Días incompletos (falta desayuno, almuerzo o cena): ${_days(incomplete)} — fuera de los promedios. '
        'Si ese día no hubo más comidas, ciérralo en Comidas');
  }

  for (final streak in s.lowKcalStreaks.where((st) => st.length >= 2)) {
    out.add('${streak.length} días seguidos bajo ${fmtInt(t.kcalFloor)} kcal (${_days(streak)})');
  }

  final p = s.avgProtein;
  if (p != null && p < t.proteinMin) {
    out.add('Proteína promedio ${fmtInt(p)} g, bajo el mínimo de ${t.proteinMin} g');
  }

  // Solo días ya cerrados: a mitad de semana no es una falta lo que aún no llega.
  final done = s.input.sessions.length;
  if (s.expectedTrainingClosed > 0 && done < s.expectedTrainingClosed) {
    out.add('Sesiones por debajo del plan: $done de ${s.expectedTrainingClosed} '
        'en los días ya cerrados');
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

  // RPE 9–10 en un día que debería salir cómodo: casi siempre es un error de
  // registro (la escala es al revés de lo que parece).
  final hardLight = s.input.sessions.where((x) => x.type == SessionType.circuitoLigero && (x.rpe ?? 0) >= 9).toList();
  if (hardLight.isNotEmpty) {
    out.add('RPE ≥ 9 en circuito ligero: ${hardLight.map((x) => 'RPE ${x.rpe} el ${formatShort(x.date)}').join(', ')} '
        '— revisa si fue un error de registro');
  }

  out.addAll(interferenceNotes(s));

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

/// Ejercicio del circuito → ejercicio del Plan v2 que puede restarle.
const interferencePairs = {
  'Flexiones': ('Pike push-up', 'miércoles'),
  'Sentadillas': ('Sentadilla búlgara', 'martes'),
};

/// Si el ejercicio del circuito empeoró en el viernes (progresión) respecto
/// al viernes anterior y esa semana se hizo el ejercicio nuevo que lo carga,
/// sugiere bajarlo a 2 series. Peor = más series partidas o menos reps por
/// serie.
List<String> interferenceNotes(ReportStats s) {
  final all = [...?s.input.previous?.sessions, ...s.input.sessions]
    ..sort((a, c) => a.date.compareTo(c.date));
  final progression = all.where((x) => x.type == SessionType.progresion).toList();
  final out = <String>[];
  for (final session in s.input.sessions.where((x) => x.type == SessionType.progresion)) {
    final i = progression.indexOf(session);
    if (i <= 0) continue;
    final before = progression[i - 1];
    for (final entry in interferencePairs.entries) {
      final (extra, day) = entry.value;
      final now = _setStats(session, entry.key);
      final prev = _setStats(before, entry.key);
      if (now == null || prev == null) continue;
      final worse = now.$1 > prev.$1 || now.$2 < prev.$2 - 0.01;
      if (!worse) continue;
      final weekStart = addDays(session.date, -6);
      final didExtra = all.any((x) =>
          !x.date.isBefore(weekStart) && x.date.isBefore(session.date) && x.sets.any((set) => set.exercise == extra));
      if (!didExtra) continue;
      final detail = now.$1 > prev.$1
          ? 'partidas ${prev.$1}→${now.$1}'
          : 'reps por serie ${fmtDec(prev.$2)}→${fmtDec(now.$2)}';
      out.add('${entry.key} del ${formatShort(session.date)} peor que el ${formatShort(before.date)} ($detail) '
          'y esa semana hubo $extra: considera bajar $extra del $day a 2 series');
    }
  }
  return out;
}

/// (series partidas, reps medias por serie) de un ejercicio; null si no se hizo.
(int, double)? _setStats(SessionEntry x, String exercise) {
  final sets = x.sets.where((set) => set.exercise == exercise).toList();
  if (sets.isEmpty) return null;
  return (sets.where((set) => set.split).length, sets.map((set) => set.reps).reduce((a, c) => a + c) / sets.length);
}

String _days(List<DateTime> days) => days.map((d) => '${weekdayShort(d.weekday)} ${d.day}').join(', ');

