import '../dates.dart';
import '../enums.dart';
import '../format.dart';
import '../nutrition.dart';
import '../session_math.dart';
import 'alerts.dart';
import 'report_input.dart';
import 'report_stats.dart';

/// Genera el informe en Markdown. Función pura: misma entrada, mismo texto.
String buildReport(ReportInput input) {
  final s = ReportStats(input);
  final b = StringBuffer();
  _header(b, s);
  _summary(b, s);
  _sessions(b, s);
  _football(b, s);
  _nutrition(b, s);
  _body(b, s);
  _alerts(b, s);
  _notes(b, s);
  return b.toString().trimRight();
}

void _header(StringBuffer b, ReportStats s) {
  final i = s.input;
  final wStart = weekIndexFor(i.programStart, i.rangeStart);
  final wEnd = weekIndexFor(i.programStart, i.rangeEnd);
  final isWeek = daysBetween(i.rangeStart, i.rangeEnd) == 6 &&
      dayKey(weekRange(i.programStart, wStart).start) == dayKey(i.rangeStart);
  final range = '${formatShort(i.rangeStart)} a ${formatLong(i.rangeEnd)}';
  b.writeln(isWeek ? '# Informe semanal — $range' : '# Informe — $range');

  final weekLabel = wStart == wEnd ? 'Semana $wStart' : 'Semanas $wStart–$wEnd';
  final plans = s.plansInRange;
  final planLabel = switch (plans.length) {
    0 => 'Sin plan',
    1 => 'Plan v${plans.first.number}',
    _ => 'Plan ${plans.map((p) => 'v${p.number} (desde ${formatShort(p.validFrom)})').join(' → ')}',
  };
  b.writeln('$weekLabel desde inicio (${formatShort(i.programStart)}) · $planLabel');
  b.writeln();
}

void _summary(StringBuffer b, ReportStats s) {
  final i = s.input;
  final t = i.targets;
  b.writeln('## Resumen');

  final done = i.sessions.length;
  final sessions = s.expectedTraining > 0 ? '$done/${s.expectedTraining}' : '$done';
  final foot = s.expectedFootball > 0 ? '${i.football.length}/${s.expectedFootball}' : '${i.football.length}';
  b.writeln('- Sesiones: $sessions · Fútbol: $foot');

  final max = s.maxRoundsInRange;
  final prev = i.previousRoundsRecord;
  if (max != null) {
    if (prev == null) {
      b.writeln('- Récord de rondas: $max (primer registro)');
    } else if (max > prev) {
      b.writeln('- Récord de rondas: $max (anterior: $prev)');
    } else {
      b.writeln('- Máximo de rondas: $max (récord vigente: $prev)');
    }
  }

  final logged = s.loggedDays.length;
  final elapsed = s.elapsedDays.length;
  if (logged == 0) {
    b.writeln('- Nutrición: sin registros');
  } else {
    b.writeln('- Proteína promedio: ${fmtInt(s.avgProtein!)} g (meta ${t.proteinMin}–${t.proteinMax}) · '
        'kcal promedio: ${fmtInt(s.avgKcal!)} (meta ${fmtInt(t.kcalTarget)}) · '
        'días registrados: $logged/$elapsed');
    b.writeln('- Días bajo ${fmtInt(t.kcalFloor)} kcal: ${s.daysBelowFloor.length}');
  }

  final w = i.weightsInRange;
  if (w.isNotEmpty) {
    final fasted = w.where((x) => x.fasted).toList();
    final base = fasted.isNotEmpty ? fasted : w;
    final avg = base.map((x) => x.kg).reduce((a, c) => a + c) / base.length;
    final tag = fasted.isNotEmpty ? 'en ayunas' : 'sin ayunas';
    final delta = i.baselineWeight == null ? '' : ' · Δ vs línea base: ${fmtDelta(avg - i.baselineWeight!.kg)} kg';
    final n = base.length;
    b.writeln('- Peso promedio: ${fmtDec(avg)} kg ($tag, $n ${n == 1 ? 'pesaje' : 'pesajes'})$delta');
  }
  b.writeln();
}

void _sessions(StringBuffer b, ReportStats s) {
  b.writeln('## Sesiones');
  final list = s.sessionsSorted;
  if (list.isEmpty) {
    b.writeln('Sin sesiones registradas.');
    b.writeln();
    return;
  }
  b.writeln('| Día | Tipo | Total | Cal/Enf | Neto | Rondas | RPE | Series partidas | Contexto |');
  b.writeln('|---|---|---|---|---|---|---|---|---|');
  for (final x in list) {
    final net = circuitNetSec(totalSec: x.totalSec, warmupSec: x.warmupSec, cooldownSec: x.cooldownSec);
    final rounds = _roundsCell(x);
    final splits = x.sets.where((e) => e.split).length;
    b.writeln('| ${_dayLabel(x.date, x.startTime)} | ${x.type.label}${x.outOfPlan ? ' ⚠ fuera de plan' : ''} | '
        '${formatDuration(x.totalSec)} | '
        '${formatDuration(x.warmupSec)} / ${formatDuration(x.cooldownSec)} | ${formatDuration(net)} | $rounds | '
        '${x.rpe ?? '—'} | ${splits == 0 ? '—' : splits} | ${mdCell(x.context)} |');
  }
  b.writeln();

  b.writeln('### Detalle por sesión');
  for (final x in list) {
    b.writeln('**${_dayLabel(x.date, x.startTime)} · ${x.type.label}**');
    if (x.lapsSec.isNotEmpty) {
      b.writeln('- Vueltas: ${x.lapsSec.map(formatDuration).join(' · ')} '
          '(media ${formatDuration(meanSec(x.lapsSec)!)})');
    }
    final byExercise = <String, List<SetEntry>>{};
    for (final set in x.sets) {
      byExercise.putIfAbsent(set.exercise, () => []).add(set);
    }
    for (final e in byExercise.entries) {
      final sets = [...e.value]..sort((a, c) => a.setIndex.compareTo(c.setIndex));
      b.writeln('- ${e.key}: ${sets.map(_setLabel).join(' · ')}');
    }
    final extra = [
      if (x.limitingExercise != null && x.limitingExercise!.isNotEmpty) 'Limitante: ${x.limitingExercise}',
      if (x.rpe != null) 'RPE ${x.rpe}',
    ];
    if (extra.isNotEmpty) b.writeln('- ${extra.join(' · ')}');
    if (x.notes != null && x.notes!.trim().isNotEmpty) b.writeln('- Notas: ${x.notes!.trim()}');
    b.writeln();
  }
}

/// `7/8 (incompleta)`, `~6 (est.)`, `8`.
String _roundsCell(SessionEntry x) {
  if (x.roundsDone == null) return '—';
  final prefix = x.roundsEstimated ? '~' : '';
  final target = x.plannedRounds == null ? '' : '/${x.plannedRounds}';
  final estimated = x.roundsEstimated ? ' (est.)' : '';
  final unfinished = x.incomplete ? ' (incompleta)' : '';
  return '$prefix${x.roundsDone}$target$estimated$unfinished';
}

String _setLabel(SetEntry e) {
  var out = e.split && e.splitDetail != null && e.splitDetail!.trim().isNotEmpty
      ? '${e.splitDetail!.trim()} (partida)'
      : e.split
          ? '${e.reps} (partida)'
          : '${e.reps}';
  if (e.toFailure) out += ' (fallo)';
  return out;
}

void _football(StringBuffer b, ReportStats s) {
  final list = [...s.input.football]..sort((a, c) => a.date.compareTo(c.date));
  if (list.isEmpty) return;
  b.writeln('## Fútbol');
  b.writeln('| Día | Formato | Min | Pasos | Intensidad | Fatiga | Notas |');
  b.writeln('|---|---|---|---|---|---|---|');
  for (final f in list) {
    b.writeln('| ${_dayLabel(f.date, null)} | ${f.format} | ${f.minutes} | '
        '${f.steps == null ? '—' : fmtInt(f.steps!)} | ${f.intensity ?? '—'} | ${f.fatigueAfter ?? '—'} | '
        '${mdCell(f.notes)} |');
  }
  b.writeln();
}

void _nutrition(StringBuffer b, ReportStats s) {
  b.writeln('## Nutrición');
  final meals = s.input.meals;
  if (meals.isEmpty) {
    b.writeln('Sin comidas registradas.');
    b.writeln();
    return;
  }
  final hasOther = meals.any((m) => m.slot == MealSlot.otro);
  final slots = [MealSlot.desayuno, MealSlot.almuerzo, MealSlot.merienda, MealSlot.cena, if (hasOther) MealSlot.otro];
  b.writeln('| Día | ${slots.map((x) => x.label).join(' | ')} | kcal | Proteína |');
  b.writeln('|---|${'---|' * slots.length}---|---|');
  for (final d in s.elapsedDays.isEmpty ? s.days : s.elapsedDays) {
    final dayMeals = meals.where((m) => dayKey(m.date) == dayKey(d)).toList();
    final cells = slots.map((slot) {
      final m = Macros.sum(dayMeals.where((x) => x.slot == slot).map((x) => x.macros));
      final any = dayMeals.any((x) => x.slot == slot);
      return any ? '${fmtInt(m.kcal)} · ${fmtInt(m.protein)} g' : '—';
    });
    final total = s.macrosOn(d);
    final flag = total != null && total.kcal < s.input.targets.kcalFloor ? ' ⚠' : '';
    b.writeln('| ${_dayLabel(d, null)} | ${cells.join(' | ')} | '
        '${total == null ? 'sin registro' : '${fmtInt(total.kcal)}$flag'} | '
        '${total == null ? '—' : '${fmtInt(total.protein)} g'} |');
  }
  final (verifiedKcal, referenceKcal, freeKcal) = s.kcalBySource;
  final totalKcal = verifiedKcal + referenceKcal + freeKcal;
  if (totalKcal > 0) {
    b.writeln();
    b.writeln('Procedencia de las kcal: ${_pct(verifiedKcal, totalKcal)} de etiqueta · '
        '${_pct(referenceKcal, totalKcal)} de tablas de referencia · '
        '${_pct(freeKcal, totalKcal)} estimado a ojo');
  }
  if (s.loggedDays.isNotEmpty) {
    b.writeln();
    b.writeln('Promedio (días registrados): ${fmtInt(s.avgKcal!)} kcal · P ${fmtInt(s.avgProtein!)} g · '
        'C ${fmtInt(s.avgCarbs!)} g · G ${fmtInt(s.avgFat!)} g');
  }
  b.writeln();

  b.writeln('### Detalle de comidas');
  final sorted = [...meals]..sort((a, c) => '${dayKey(a.date)} ${a.slot.index} ${a.time ?? ''}'
      .compareTo('${dayKey(c.date)} ${c.slot.index} ${c.time ?? ''}'));
  String? currentDay;
  for (final m in sorted) {
    final k = dayKey(m.date);
    if (k != currentDay) {
      currentDay = k;
      b.writeln('- **${_dayLabel(m.date, null)}**');
    }
    final items = m.items
        .map((it) => it.quantityLabel == null ? it.label : '${it.label} ${it.quantityLabel}')
        .join(', ');
    final time = m.time == null ? '' : ' ${m.time}';
    final note = m.notes == null || m.notes!.trim().isEmpty ? '' : ' — ${m.notes!.trim()}';
    b.writeln('  - ${m.slot.label}$time: ${items.isEmpty ? '(vacía)' : items} '
        '→ ${fmtInt(m.macros.kcal)} kcal · ${fmtInt(m.macros.protein)} g P$note');
  }
  b.writeln();
}

void _body(StringBuffer b, ReportStats s) {
  final i = s.input;
  if (i.measurementsInRange.isEmpty) return;
  final unit = i.targets.lengthUnit;
  b.writeln('## Medidas');
  final dates = i.measurementsInRange.map((m) => dayKey(m.date)).toSet().toList()..sort();
  final conditions = dates.map((k) {
    final fasted = i.measurementsInRange.where((m) => dayKey(m.date) == k).every((m) => m.fasted);
    return '${formatShort(parseDay(k))} (${fasted ? 'ayunas' : 'sin ayunas'})';
  });
  b.writeln('Tomadas: ${conditions.join(', ')} · unidad: ${unit.label}');
  b.writeln();
  b.writeln('| Medida | Línea base | Actual | Δ |');
  b.writeln('|---|---|---|---|');
  if (i.baselineWeight != null && i.weightsInRange.isNotEmpty) {
    final last = ([...i.weightsInRange]..sort((a, c) => a.date.compareTo(c.date))).last;
    b.writeln('| Peso (kg) | ${fmtDec(i.baselineWeight!.kg)} (${formatShort(i.baselineWeight!.date)}) | '
        '${fmtDec(last.kg)} | ${fmtDelta(last.kg - i.baselineWeight!.kg)} |');
  }
  for (final site in MeasureSite.values) {
    final inRange = i.measurementsInRange.where((m) => m.site == site).toList()
      ..sort((a, c) => a.date.compareTo(c.date));
    if (inRange.isEmpty) continue;
    final current = inRange.last;
    final base = i.baselineMeasurements[site];
    final cur = fromCm(current.valueCm, unit);
    if (base == null || dayKey(base.date) == dayKey(current.date)) {
      b.writeln('| ${site.label} | ${fmtDec(cur)} (línea base) | ${fmtDec(cur)} | — |');
    } else {
      final baseV = fromCm(base.valueCm, unit);
      b.writeln('| ${site.label} | ${fmtDec(baseV)} (${formatShort(base.date)}) | ${fmtDec(cur)} | '
          '${fmtDelta(cur - baseV)} |');
    }
  }
  b.writeln();
}

void _alerts(StringBuffer b, ReportStats s) {
  b.writeln('## Alertas automáticas');
  final alerts = buildAlerts(s);
  if (alerts.isEmpty) {
    b.writeln('- Ninguna');
  } else {
    for (final a in alerts) {
      b.writeln('- $a');
    }
  }
  b.writeln();
}

void _notes(StringBuffer b, ReportStats s) {
  b.writeln('## Notas de la semana');
  final n = s.input.notes?.trim();
  b.writeln(n == null || n.isEmpty ? '—' : n);
}

String _pct(double part, double total) => '${fmtInt(part / total * 100)}%';

String _dayLabel(DateTime d, String? time) =>
    '${weekdayShort(d.weekday)} ${formatShort(d)}${time == null ? '' : ' $time'}';
