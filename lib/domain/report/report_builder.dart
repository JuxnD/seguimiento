import '../dates.dart';
import '../enums.dart';
import '../format.dart';
import '../nutrition.dart';
import '../session_math.dart';
import 'alerts.dart';
import 'period_summary.dart';
import 'report_input.dart';
import 'report_stats.dart';

/// Genera el informe en Markdown. Función pura: misma entrada, mismo texto.
String buildReport(ReportInput input) {
  final s = ReportStats(input);
  final b = StringBuffer();
  _header(b, s);
  _summary(b, s);
  _sessions(b, s);
  _volume(b, s);
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
  final ahead = s.expectedTrainingAhead;
  final sessions = s.expectedTraining == 0
      ? '$done'
      : '$done/${s.expectedTraining}${ahead > 0 ? ' (${ahead == 1 ? 'queda 1' : 'quedan $ahead'} en el plan)' : ''}';
  final foot = s.expectedFootball > 0 ? '${i.football.length}/${s.expectedFootball}' : '${i.football.length}';
  b.writeln('- Sesiones: $sessions · Fútbol: $foot');
  final mobility = i.mobility;
  if (mobility.isNotEmpty) {
    final minutes = (mobility.fold<int>(0, (a, m) => a + m.totalSec) / 60).round();
    b.writeln('- Movilidad (opcional): ${mobility.length} (${fmtInt(minutes)} min)');
  }

  final max = s.maxRoundsInRange;
  final prev = i.previousRoundsRecord;
  if (max != null) {
    if (prev == null) {
      b.writeln('- Récord de rondas: $max (primer registro)');
    } else if (max > prev) {
      b.writeln('- 🏆 **Récord nuevo: $max rondas** (anterior: $prev)');
    } else {
      b.writeln('- Máximo de rondas: $max (récord vigente: $prev)');
    }
  }
  // Por tipo: comparar un circuito ligero con el día de progresión no dice
  // nada (§16.8).
  final byType = s.maxRoundsByType;
  final prevByType = s.previous?.maxRoundsByType ?? const <SessionType, int>{};
  final compared = [
    for (final e in byType.entries)
      if (prevByType[e.key] case final before?)
        '${e.key.label} $before → ${e.value} (${fmtDelta(e.value - before, decimals: 0)})',
  ];
  if (compared.isNotEmpty) b.writeln('- Rondas vs semana anterior, por tipo: ${compared.join(' · ')}');

  final logged = s.loggedDays.length;
  final elapsed = s.elapsedDays.length;
  final closed = s.closedDays.length;
  if (logged == 0) {
    b.writeln('- Nutrición: sin registros');
  } else if (closed == 0) {
    b.writeln('- Nutrición: $logged ${logged == 1 ? 'día registrado' : 'días registrados'}, ninguno cerrado '
        '(falta desayuno, almuerzo o cena): sin promedios');
  } else {
    final prev = s.previous;
    String vs(double now, double? before) => before == null ? '' : ' (${fmtDelta(now - before, decimals: 0)} vs semana anterior)';
    b.writeln('- Proteína promedio: ${fmtInt(s.avgProtein!)} g (meta ${t.proteinMin}–${t.proteinMax})'
        '${vs(s.avgProtein!, prev?.avgProtein)} · '
        'kcal promedio: ${fmtInt(s.avgKcal!)} (meta ${fmtInt(t.kcalTarget)}'
        '${t.kcalTargetFootball == null ? '' : ' entre semana, ${fmtInt(t.kcalTargetFootball!)} fútbol'})'
        '${vs(s.avgKcal!, prev?.avgKcal)} · '
        'días cerrados: $closed/$elapsed');
    b.writeln('- Días bajo ${fmtInt(t.kcalFloor)} kcal: ${s.daysBelowFloor.length}');
  }

  final steps = s.steps;
  if (steps != null) {
    final n = steps.days;
    final weekday = steps.weekdayAverage == null
        ? ''
        : ' · entre semana ${fmtInt(steps.weekdayAverage!)} (meta ${fmtInt(t.stepsTarget)}, '
            '${steps.weekdaysAtGoal}/${steps.weekdayDays} ${steps.weekdayDays == 1 ? 'día' : 'días'} en meta)';
    final before = s.previous?.steps?.average;
    final vs = before == null ? '' : ' (${fmtDelta(steps.average - before, decimals: 0)} vs semana anterior)';
    b.writeln('- Pasos: ${fmtInt(steps.average)}/día ($n ${n == 1 ? 'día registrado' : 'días registrados'})'
        '$vs$weekday');
  }

  // Totales del rango: lo que el promedio no dice.
  final p = summarizePeriod(i);
  if (p.activeSec > 0 || p.stepsTotal > 0) {
    b.writeln('- Movimiento: ${formatDuration(p.activeSec)} activo · ${fmtInt(p.stepsTotal)} pasos '
        '(≈ ${fmtDec(p.distanceKm)} km)');
  }
  if (p.kcalBurned case final k? when k > 0) {
    b.writeln('- Gasto aprox. por actividad: ≈ ${fmtInt(k)} kcal (entrenamiento ${fmtInt(p.kcalTraining ?? 0)} · '
        'fútbol ${fmtInt(p.kcalFootball ?? 0)} · caminar ${fmtInt(p.kcalSteps ?? 0)}; con ${fmtDec(p.weightKg!)} kg, ±30 %)');
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
  b.writeln('| Día | Tipo | Total | Cal/Enf | Descanso | Neto | Rondas | RPE | Series partidas | Contexto |');
  b.writeln('|---|---|---|---|---|---|---|---|---|---|');
  for (final x in list) {
    final net =
        circuitNetSec(totalSec: x.totalSec, warmupSec: x.warmupSec, cooldownSec: x.cooldownSec, restSec: x.restSec);
    final rounds = _roundsCell(x);
    final splits = x.sets.where((e) => e.split).length;
    b.writeln('| ${_dayLabel(x.date, x.startTime)} | ${x.typeLabel}${x.outOfPlan ? ' ⚠ fuera de plan' : ''} | '
        '${formatDuration(x.totalSec)} | '
        '${formatDuration(x.warmupSec)} / ${formatDuration(x.cooldownSec)} | '
        '${x.restSec == 0 ? '—' : formatDuration(x.restSec)} | ${formatDuration(net)} | $rounds | '
        '${x.rpe ?? (x.pendingReview ? '⚠ sin revisar' : '—')} | ${splits == 0 ? '—' : splits} | ${mdCell(x.context)} |');
  }
  b.writeln();

  b.writeln('### Detalle por sesión');
  for (final x in list) {
    b.writeln('**${_dayLabel(x.date, x.startTime)} · ${x.typeLabel}**');
    if (x.mode == 'cindy' && x.roundsDone != null) {
      b.writeln('- Cindy: ${x.roundsDone} rondas + ${x.extraReps ?? 0} reps en 20 min');
    }
    if (x.roundWorkSec.isNotEmpty) {
      // Una ronda tras un descanso de 0:00 casi siempre se comió ese
      // descanso: va marcada y fuera de la media y del R1→Rn (§16.9).
      final suspects = suspectRounds(x.roundWorkSec, x.roundRestSec).toSet();
      final valid = [
        for (var i = 0; i < x.roundWorkSec.length; i++)
          if (!suspects.contains(i)) x.roundWorkSec[i],
      ];
      final delta = firstToLastDelta(valid);
      final laps = [
        for (var i = 0; i < x.roundWorkSec.length; i++)
          '${formatDuration(x.roundWorkSec[i])}${suspects.contains(i) ? ' ⚠' : ''}',
      ];
      b.writeln('- Trabajo por ronda: ${laps.join(' · ')} '
          '(media ${valid.isEmpty ? '—' : formatDuration(meanSec(valid)!)}'
          '${delta == null ? '' : ' · R1→R${x.roundWorkSec.length} ${fmtDelta(delta, decimals: 0)} s'})');
      final rests = x.roundRestSec.take(x.roundRestSec.length - 1).toList();
      if (rests.isNotEmpty) b.writeln('- Descanso entre rondas: ${rests.map(formatDuration).join(' · ')}');
      if (suspects.isNotEmpty) {
        b.writeln('- ⚠ ${suspects.map((i) => 'R${i + 1}').join(', ')} fuera de la media: el descanso previo fue de '
            'menos de 5 s y la ronda duró mucho más que las demás (probable descanso contado como trabajo). '
            'Se corrige en la sesión, "Pasar 30 s al descanso".');
      }
    } else if (x.lapsSec.isNotEmpty) {
      // Sin descansos medidos cada vuelta lleva dentro el descanso previo.
      b.writeln('- Vueltas (con descanso): ${x.lapsSec.map(formatDuration).join(' · ')} '
          '(media ${formatDuration(meanSec(x.lapsSec)!)})');
    }
    final byExercise = <String, List<SetEntry>>{};
    for (final set in x.sets) {
      byExercise.putIfAbsent(set.exercise, () => []).add(set);
    }
    for (final e in byExercise.entries) {
      final sets = [...e.value]..sort((a, c) => a.setIndex.compareTo(c.setIndex));
      final hold = s.input.holdExercises.contains(e.key);
      b.writeln('- ${e.key}: ${sets.map((x) => _setLabel(x, seconds: hold)).join(' · ')}');
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

String _setLabel(SetEntry e, {bool seconds = false}) {
  final amount = seconds ? '${e.reps} s' : '${e.reps}';
  var out = e.split && e.splitDetail != null && e.splitDetail!.trim().isNotEmpty
      ? '${e.splitDetail!.trim()} (partida)'
      : e.split
          ? '$amount (partida)'
          : amount;
  if (e.loadKg != null) out += ' @ ${fmtDec(e.loadKg!)} kg';
  if (e.variant != null) out += ' (${e.variant})';
  if (e.toFailure) out += ' (fallo)';
  return out;
}

/// Volumen de la semana por ejercicio y su cambio contra la anterior.
void _volume(StringBuffer b, ReportStats s) {
  final now = s.volumeByExercise;
  if (now.isEmpty) return;
  // Semana en curso: contra el mismo punto de la anterior, no contra la
  // semana entera (1 día hecho contra 7 siempre "baja"; §16.8).
  final partial = s.inProgress && s.previous != null;
  final before = partial ? s.previous!.volumeFirstDays(s.elapsedCount) : s.previous?.volumeByExercise;
  b.writeln('## Volumen por ejercicio');
  if (partial) {
    b.writeln('Semana en curso (${s.elapsedCount} de ${s.days.length} días): se compara con los mismos '
        '${s.elapsedCount} primeros días de la anterior.');
    b.writeln();
  }
  final holds = s.input.holdExercises;
  String unit(String exercise, num v) => holds.contains(exercise) ? '$v s' : '$v';
  if (before == null) {
    b.writeln('| Ejercicio | Reps o s |');
    b.writeln('|---|---|');
    for (final e in now.entries) {
      b.writeln('| ${e.key} | ${unit(e.key, e.value)} |');
    }
  } else {
    b.writeln('| Ejercicio | Reps o s | ${partial ? 'Anterior, mismo punto' : 'Semana anterior'} | Δ |');
    b.writeln('|---|---|---|---|');
    for (final e in now.entries) {
      final prev = before[e.key];
      b.writeln('| ${e.key} | ${unit(e.key, e.value)} | ${prev == null ? '—' : unit(e.key, prev)} | '
          '${prev == null ? 'nuevo' : fmtDelta(e.value - prev, decimals: 0)} |');
    }
  }
  b.writeln();
}

void _football(StringBuffer b, ReportStats s) {
  final list = [...s.input.football]..sort((a, c) => a.date.compareTo(c.date));
  if (list.isEmpty) return;
  b.writeln('## Fútbol');
  b.writeln('| Día | Formato | Min | Pasos | Intensidad | Fatiga | Golpe | Notas |');
  b.writeln('|---|---|---|---|---|---|---|---|');
  for (final f in list) {
    final knock = switch (f.knock) { true => 'sí', false => 'no', null => '—' };
    b.writeln('| ${_dayLabel(f.date, null)} | ${f.format} | ${f.minutes} | '
        '${f.steps == null ? '—' : fmtInt(f.steps!)} | ${f.intensity ?? '—'} | ${f.fatigueAfter ?? '—'} | '
        '$knock | ${mdCell(f.notes)} |');
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
    final closed = s.isClosed(d);
    final flag = closed && total != null && total.kcal < s.input.targets.kcalFloor ? ' ⚠' : '';
    final open = total != null && !closed ? ' (incompleto)' : '';
    b.writeln('| ${_dayLabel(d, null)} | ${cells.join(' | ')} | '
        '${total == null ? 'sin registro' : '${fmtInt(total.kcal)}$flag$open'} | '
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
  if (s.closedDays.isNotEmpty) {
    b.writeln();
    b.writeln('Promedio (días cerrados): ${fmtInt(s.avgKcal!)} kcal · P ${fmtInt(s.avgProtein!)} g · '
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
      // Ayunas contra después de comer: el delta se da, pero no se lee como
      // progreso (§16.10).
      final mismatch = base.fasted != current.fasted ? ' (condiciones distintas)' : '';
      b.writeln('| ${site.label} | ${fmtDec(baseV)} (${formatShort(base.date)}) | ${fmtDec(cur)} | '
          '${fmtDelta(cur - baseV)}$mismatch |');
    }
  }
  // Proporción en V: hombros ÷ cintura de la última toma que tenga ambas.
  final byDate = <String, Map<MeasureSite, double>>{};
  for (final m in i.measurementsInRange) {
    byDate.putIfAbsent(dayKey(m.date), () => {})[m.site] = m.valueCm;
  }
  final withBoth = (byDate.entries
          .where((e) => e.value.containsKey(MeasureSite.hombros) && e.value.containsKey(MeasureSite.cinturaEstrecha))
          .toList()
        ..sort((a, c) => a.key.compareTo(c.key)))
      .lastOrNull;
  if (withBoth != null) {
    final ratio = withBoth.value[MeasureSite.hombros]! / withBoth.value[MeasureSite.cinturaEstrecha]!;
    b.writeln();
    b.writeln('Índice hombros ÷ cintura: ${fmtDec(ratio, decimals: 2)} (referencia estética ≈ 1,6)');
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
