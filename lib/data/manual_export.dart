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

/// Plan 056 (§16.28.4 B): «Exportar manual». Markdown generado **desde los
/// datos vivos de la app** (plan vigente, días armados, agenda de tests,
/// metas y recordatorios): si algo no está en los datos, no sale. Se le
/// pasa al entrenador cada vez que cambia el plan o la versión.
Future<String> buildAppManual(AppDatabase db,
    {required String appVersion, DateTime? now}) async {
  final today = dateOnly(now ?? DateTime.now());
  final exercises = ExerciseRepository(db);
  final plan = PlanRepository(db, exercises);
  final training = TrainingRepository(db, exercises);
  final readiness = ReadinessRepository(db);
  final b = StringBuffer();

  final todayView = await plan.dayFor(today);
  final v3 = await training.blockDay(todayView, today);
  b.writeln('# Manual de My Prime $appVersion');
  b.writeln();
  b.writeln('Generado el ${dayKey(today)} desde los datos de la app.');
  b.writeln();
  b.writeln('## 1. Versión');
  b.writeln('- App: $appVersion');
  if (v3 != null) {
    b.writeln('- Plan: ${v3.title} · bloque desde el ${dayKey(v3.blockStart ?? today)} · '
        'semana ${v3.week} de ${v3.totalWeeks}'
        '${v3.reducedVolume ? ' (descarga)' : ''}');
    b.writeln('- Tests: ${v3.isV32 ? '13 pruebas de torso (v3.2)' : '12 pruebas de torso (v3.1)'} y 4 de piernas');
  } else {
    b.writeln('- Plan: ${todayView == null ? 'sin plan' : 'sin bloque v3'}');
  }
  b.writeln();

  b.writeln('## 2. Próximos 14 días');
  for (var i = 0; i < 14; i++) {
    final d = addDays(today, i);
    final view = await plan.dayFor(d);
    if (view == null) {
      b.writeln('- **${weekdayShort(d.weekday)} ${dayKey(d)}**: sin plan');
      continue;
    }
    final block = await training.blockDay(view, d);
    final day = await training.withV31Blocks(view.day, d, block, planche: false);
    final test = block == null || !block.isV31
        ? null
        : await readiness.effectiveTestOn(d,
            scheme: block.scheme,
            blockStart: block.blockStart ?? d,
            protocol: block.isV32
                ? TestProtocolId.v32_13
                : TestProtocolId.v31_12,
            gate: false);
    final extras = [
      if (test != null)
        'Test ${test.round} de ${test.part == TestPart.torso ? 'torso' : 'piernas'}',
      if (block?.resistance case final r?) r.label,
      if (block?.reducedVolume == true) 'descarga',
      if (view.nominalDate != null) 'rodado desde el ${dayKey(view.nominalDate!)}',
    ];
    b.writeln('- **${weekdayShort(d.weekday)} ${dayKey(d)}** · ${day.type.label}'
        '${extras.isEmpty ? '' : ' · ${extras.join(' · ')}'}');
    for (final e in day.exercises) {
      final rir = e.rirMin == null
          ? ''
          : ' · RIR ${e.rirMin}${e.rirMax != null && e.rirMax != e.rirMin ? '–${e.rirMax}' : ''}';
      final rest = e.restSec == null ? '' : ' · ${e.restSec} s';
      final block = e.block == null ? '' : ' [${e.block}]';
      b.writeln('  - ${e.name}$block: ${e.targetLabel}$rir$rest'
          '${e.purpose == null ? '' : ' — ${e.purpose}'}');
    }
    if (day.notes case final n? when n.trim().isNotEmpty) {
      b.writeln('  - Nota: ${n.trim()}');
    }
  }
  b.writeln();

  if (v3 != null && v3.isV31) {
    b.writeln('## 3. Agenda de tests del bloque');
    final agenda = await readiness.testAgenda(
        scheme: v3.scheme,
        blockStart: v3.blockStart ?? today,
        protocol: v3.isV32 ? TestProtocolId.v32_13 : TestProtocolId.v31_12,
        gates: false);
    for (final t in agenda) {
      b.writeln('- Test ${t.round} de ${t.part == TestPart.torso ? 'torso' : 'piernas'}: '
          '${weekdayShort(t.date.weekday)} ${dayKey(t.date)}'
          '${t.moved ? ' (previsto el ${dayKey(t.planned)})' : ''}');
    }
    b.writeln();
  }

  b.writeln('## 4. Metas vigentes hoy');
  final h = await GoalRepository(db).history();
  String goal(GoalMetric m) {
    final g = goalReferenceOn(h, m, today);
    return g.comparable ? '${g.value!.round()} ${m.unit}' : 'sin meta';
  }

  for (final m in GoalMetric.values) {
    b.writeln('- ${m.label}: ${goal(m)}');
  }
  b.writeln('- Grasa: $fatGoalMinG–$fatGoalMaxG g');
  b.writeln();

  b.writeln('## 5. Reglas con umbral');
  b.writeln('- Recuperación activa: carga de anteayer y ayer ≥ $readinessLoad3Days, '
      '2 partidos entre ayer y hoy, pulso ≥ +5, escaleras 3–4 o dolor muscular ≥ 6 (amarillo); '
      'pulso ≥ +10, escaleras ≥ 5 o enfermo (rojo).');
  b.writeln('- Escaleras al despertar: obligatorias en el registro de la mañana.');
  b.writeln('- Semanas 1 y 2: RIR mínimo 2–3. Nórdico: 2 series en sus 2 primeras semanas.');
  b.writeln();

  b.writeln('## 6. Recordatorios');
  final settings = await ReminderRepository(db).settings();
  for (final kind in ReminderKind.values) {
    final s = settings[kind];
    if (s == null) continue;
    b.writeln('- ${kind.label}: ${s.enabled ? s.timeLabel : 'apagado'} — ${kind.description}');
  }
  return b.toString();
}
