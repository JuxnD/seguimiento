import 'dart:convert';

import '../domain/dates.dart';
import '../domain/enums.dart';
import '../domain/plan_v3.dart' show ResistanceModeLabel;
import '../domain/fitness_test.dart' show TestPart;
import '../domain/goal_history.dart';
import '../domain/nutrition.dart' show fatGoalMaxG, fatGoalMinG;
import '../domain/readiness.dart' show readinessLoad3Days;
import '../domain/reminders.dart';
import '../domain/test_protocol.dart';
import 'database.dart';
import 'repositories/exercise_repository.dart';
import 'repositories/goal_repository.dart';
import 'repositories/plan_repository.dart';
import 'repositories/readiness_repository.dart';
import 'repositories/reminder_repository.dart';
import 'repositories/training_repository.dart';

/// Plan 056 (§16.28.4 B): «Exportar manual». Los datos se leen **de la app
/// viva** (plan vigente, días armados, agenda de tests, metas y
/// recordatorios): si algo no está en los datos, no sale. De los mismos
/// datos salen el Markdown (para leer) y el JSON (plan 057, para comparar).
Future<Map<String, Object?>> appManualData(AppDatabase db,
    {required String appVersion, DateTime? now}) async {
  final today = dateOnly(now ?? DateTime.now());
  final exercises = ExerciseRepository(db);
  final plan = PlanRepository(db, exercises);
  final training = TrainingRepository(db, exercises);
  final readiness = ReadinessRepository(db);

  final todayView = await plan.dayFor(today);
  final v3 = await training.blockDay(todayView, today);
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < 14; i++) {
    final d = addDays(today, i);
    final view = await plan.dayFor(d);
    if (view == null) {
      days.add({'date': dayKey(d), 'weekday': weekdayShort(d.weekday), 'type': null});
      continue;
    }
    final block = await training.blockDay(view, d);
    final day =
        await training.withV31Blocks(view.day, d, block, planche: false);
    final test = block == null || !block.isV31
        ? null
        : await readiness.effectiveTestOn(d,
            scheme: block.scheme,
            blockStart: block.blockStart ?? d,
            protocol: block.isV32
                ? TestProtocolId.v32_13
                : TestProtocolId.v31_12,
            gate: false);
    days.add({
      'date': dayKey(d),
      'weekday': weekdayShort(d.weekday),
      'type': day.type.label,
      if (test != null)
        'test':
            'Test ${test.round} de ${test.part == TestPart.torso ? 'torso' : 'piernas'}',
      if (block?.resistance case final r?) 'resistance': r.label,
      'deload': block?.reducedVolume == true,
      if (view.nominalDate != null) 'rolledFrom': dayKey(view.nominalDate!),
      'notes': day.notes?.trim(),
      'exercises': [
        for (final e in day.exercises)
          {
            'name': e.name,
            'block': e.block,
            'sets': e.sets,
            'dose': e.targetLabel,
            'rirMin': e.rirMin,
            'rirMax': e.rirMax,
            'restSec': e.restSec,
            'purpose': e.purpose,
            'notes': e.notes,
          }
      ],
    });
  }

  final agenda = v3 == null || !v3.isV31
      ? const <EffectiveTest>[]
      : await readiness.testAgenda(
          scheme: v3.scheme,
          blockStart: v3.blockStart ?? today,
          protocol: v3.isV32 ? TestProtocolId.v32_13 : TestProtocolId.v31_12,
          gates: false);

  final h = await GoalRepository(db).history();
  final settings = await ReminderRepository(db).settings();
  return {
    'app': appVersion,
    'generated': dayKey(today),
    'plan': v3 == null
        ? (todayView == null ? 'sin plan' : 'sin bloque v3')
        : {
            'title': v3.title,
            'blockStart': dayKey(v3.blockStart ?? today),
            'week': v3.week,
            'weeks': v3.totalWeeks,
            'deload': v3.reducedVolume,
            'torsoTests': v3.isV32 ? 13 : 12,
            'legTests': 4,
          },
    'days': days,
    'tests': [
      for (final t in agenda)
        {
          'round': t.round,
          'part': t.part == TestPart.torso ? 'torso' : 'piernas',
          'date': dayKey(t.date),
          'weekday': weekdayShort(t.date.weekday),
          if (t.moved) 'planned': dayKey(t.planned),
        }
    ],
    'goals': {
      for (final m in GoalMetric.values)
        m.label: switch (goalReferenceOn(h, m, today)) {
          final g when g.comparable => '${g.value!.round()} ${m.unit}',
          _ => 'sin meta',
        },
      'Grasa': '$fatGoalMinG–$fatGoalMaxG g',
    },
    'rules': [
      'Recuperación activa: carga de anteayer y ayer ≥ $readinessLoad3Days, '
          '2 partidos entre ayer y hoy, pulso ≥ +5, escaleras 3–4 o dolor muscular ≥ 6 (amarillo); '
          'pulso ≥ +10, escaleras ≥ 5 o enfermo (rojo).',
      'Escaleras al despertar: obligatorias en el registro de la mañana.',
      'Semanas 1 y 2: RIR mínimo 2–3. Nórdico: 2 series en sus 2 primeras semanas.',
      'Con el v3.2, la dosis del test fija el tope del rango (70–75 %; aguantes 50–60 %).',
    ],
    'reminders': [
      for (final kind in ReminderKind.values)
        if (settings[kind] case final s?)
          {
            'name': kind.label,
            'time': s.enabled ? s.timeLabel : 'apagado',
            'what': kind.description,
          }
    ],
  };
}

/// El manual en Markdown, de [appManualData].
String renderAppManual(Map<String, Object?> data) {
  final b = StringBuffer();
  b.writeln('# Manual de My Prime ${data['app']}');
  b.writeln();
  b.writeln('Generado el ${data['generated']} desde los datos de la app.');
  b.writeln();
  b.writeln('## 1. Versión');
  b.writeln('- App: ${data['app']}');
  switch (data['plan']) {
    case final Map<String, Object?> p:
      b.writeln('- Plan: ${p['title']} · bloque desde el ${p['blockStart']} · '
          'semana ${p['week']} de ${p['weeks']}${p['deload'] == true ? ' (descarga)' : ''}');
      b.writeln('- Tests: ${p['torsoTests']} pruebas de torso y ${p['legTests']} de piernas');
    case final other:
      b.writeln('- Plan: $other');
  }
  b.writeln();

  b.writeln('## 2. Próximos 14 días');
  for (final d in (data['days']! as List).cast<Map<String, Object?>>()) {
    if (d['type'] == null) {
      b.writeln('- **${d['weekday']} ${d['date']}**: sin plan');
      continue;
    }
    final extras = [
      if (d['test'] case final t?) t,
      if (d['resistance'] case final r?) r,
      if (d['deload'] == true) 'descarga',
      if (d['rolledFrom'] case final r?) 'rodado desde el $r',
    ];
    b.writeln('- **${d['weekday']} ${d['date']}** · ${d['type']}'
        '${extras.isEmpty ? '' : ' · ${extras.join(' · ')}'}');
    for (final e in (d['exercises']! as List).cast<Map<String, Object?>>()) {
      final rir = e['rirMin'] == null
          ? ''
          : ' · RIR ${e['rirMin']}${e['rirMax'] != null && e['rirMax'] != e['rirMin'] ? '–${e['rirMax']}' : ''}';
      final rest = e['restSec'] == null ? '' : ' · ${e['restSec']} s';
      final block = e['block'] == null ? '' : ' [${e['block']}]';
      b.writeln('  - ${e['name']}$block: ${e['dose']}$rir$rest'
          '${e['purpose'] == null ? '' : ' — ${e['purpose']}'}');
    }
    if (d['notes'] case final String n when n.isNotEmpty) {
      b.writeln('  - Nota: $n');
    }
  }
  b.writeln();

  final tests = (data['tests']! as List).cast<Map<String, Object?>>();
  if (tests.isNotEmpty) {
    b.writeln('## 3. Agenda de tests del bloque');
    for (final t in tests) {
      b.writeln('- Test ${t['round']} de ${t['part']}: ${t['weekday']} ${t['date']}'
          '${t['planned'] == null ? '' : ' (previsto el ${t['planned']})'}');
    }
    b.writeln();
  }

  b.writeln('## 4. Metas vigentes hoy');
  for (final g in (data['goals']! as Map<String, Object?>).entries) {
    b.writeln('- ${g.key}: ${g.value}');
  }
  b.writeln();

  b.writeln('## 5. Reglas con umbral');
  for (final r in (data['rules']! as List)) {
    b.writeln('- $r');
  }
  b.writeln();

  b.writeln('## 6. Recordatorios');
  for (final r in (data['reminders']! as List).cast<Map<String, Object?>>()) {
    b.writeln('- ${r['name']}: ${r['time']} — ${r['what']}');
  }
  return b.toString();
}

/// Markdown del manual (compatibilidad con el plan 056).
Future<String> buildAppManual(AppDatabase db,
        {required String appVersion, DateTime? now}) async =>
    renderAppManual(
        await appManualData(db, appVersion: appVersion, now: now));

/// JSON del manual, con los mismos datos que el Markdown.
String appManualJson(Map<String, Object?> data) =>
    const JsonEncoder.withIndent('  ').convert(data);
