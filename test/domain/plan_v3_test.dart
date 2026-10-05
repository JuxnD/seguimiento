import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/plan_v3.dart';
import 'package:seguimiento/domain/progress.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart' show scriptDayFrom;
import 'package:seguimiento/features/training/v3_timers.dart';

/// Plan v3 "Cierre de año" (§18).
void main() {
  final start = DateTime(2026, 10, 12); // lunes

  group('periodización (§18.6)', () {
    test('semanas y fases desde el lunes de inicio', () {
      expect(v3WeekIndex(start, DateTime(2026, 10, 11)), isNull, reason: 'antes de empezar');
      expect(v3WeekIndex(start, start), 1);
      expect(v3WeekIndex(start, DateTime(2026, 10, 18)), 1, reason: 'domingo de la semana 1');
      expect(v3WeekIndex(start, DateTime(2026, 11, 2)), 4);
      expect([for (var w = 1; w <= 10; w++) v3Phase(w)], [
        V3Phase.acumulacion,
        V3Phase.acumulacion,
        V3Phase.acumulacion,
        V3Phase.descarga,
        V3Phase.intensificacion,
        V3Phase.intensificacion,
        V3Phase.intensificacion,
        V3Phase.descarga,
        V3Phase.pico,
        V3Phase.pico,
      ]);
    });

    test('fechas clave: mediciones 6 nov y 4 dic, test 18 dic', () {
      expect(v3MeasurementDates(start).map(dayKey), ['2026-11-06', '2026-12-04']);
      expect(dayKey(v3TestDate(start)), '2026-12-18');
    });

    test('volumen reducido: semanas 4 y 8, y la 10 hasta el miércoles', () {
      expect(v3ReducedVolume(3, DateTime.monday), isFalse);
      expect(v3ReducedVolume(4, DateTime.friday), isTrue);
      expect(v3ReducedVolume(8, DateTime.monday), isTrue);
      expect(v3ReducedVolume(10, DateTime.wednesday), isTrue);
      expect(v3ReducedVolume(10, DateTime.thursday), isFalse);
    });

    test('miércoles: Cindy impares, Tabata pares; la 4 y la 10 Cindy, la 8 por tiempo', () {
      expect([for (var w = 1; w <= 10; w++) v3Resistance(w)], [
        ResistanceMode.cindy,
        ResistanceMode.tabata,
        ResistanceMode.cindy,
        ResistanceMode.cindy,
        ResistanceMode.cindy,
        ResistanceMode.tabata,
        ResistanceMode.cindy,
        ResistanceMode.porTiempo,
        ResistanceMode.cindy,
        ResistanceMode.cindy,
      ]);
    });

    test('burpees EMOM por fase, sin burpees en descarga ni en la semana del test (§18.10)', () {
      expect([for (var w = 1; w <= 10; w++) v3Burpees(w)],
          [(6, 6), (6, 6), (6, 6), null, (8, 8), (8, 8), (8, 8), null, (10, 10), null]);
    });

    test('el v3 arranca en lunes', () {
      expect(nextMonday(DateTime(2026, 10, 9)), DateTime(2026, 10, 12));
      expect(nextMonday(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
    });
  });

  group('semana tipo (§18.2)', () {
    final plan = planV3(start);

    test('tipos de día y esquema', () {
      expect(plan.scheme, v3Scheme);
      expect(plan.days.map((d) => d.type), [
        DayType.trenSuperior,
        DayType.piernas,
        DayType.resistencia,
        DayType.trenSuperior,
        DayType.densidad,
        DayType.futbol,
        DayType.futbol,
      ]);
    });

    test('jueves: curl y extensión van en superserie y el cronómetro los alterna', () {
      final thursday = plan.days[3];
      final pair = thursday.exercises.where((e) => e.supersetGroup == 'brazos').map((e) => e.name).toList();
      expect(pair, ['Curl con banda', 'Extensión de tríceps sobre la cabeza con banda']);

      final steps = buildScript(scriptDayFrom(thursday));
      final armSteps = [
        for (final s in steps)
          if (s is WorkStep && pair.contains(s.exercise)) s.exercise.split(' ').first,
      ];
      expect(armSteps, ['Curl', 'Extensión', 'Curl', 'Extensión', 'Curl', 'Extensión'],
          reason: 'A1 → B1 → descanso → A2 → B2…');
      final firstCurl = steps.indexWhere((s) => s is WorkStep && s.exercise == 'Curl con banda');
      expect(steps[firstCurl + 1], isA<WorkStep>(), reason: 'sin descanso entre curl y extensión');
      expect(steps[firstCurl + 2], isA<RestStep>(), reason: 'el descanso va después del par');
    });

    test('viernes: 6 rondas de circuito y después L-sit y toes-to-bar', () {
      final friday = plan.days[4];
      expect((friday.targetRounds, friday.restBetweenRoundsSec), (6, 30));
      expect(friday.blocks.keys, ['core avanzado']);
    });

    test('descarga: una serie menos en los ejercicios de series; el circuito no cambia', () {
      final monday = deloadVersion(plan.days[0]);
      expect(monday.exercises.firstWhere((e) => e.name == 'Dominadas').sets, 3, reason: '4 → 3');
      expect(monday.exercises.firstWhere((e) => e.name == 'Separaciones con banda').sets, 1);
      final friday = deloadVersion(plan.days[4]);
      expect(friday.targetRounds, 6);
      expect(friday.exercises.firstWhere((e) => e.name == 'L-sit').sets, 4);
    });
  });

  group('cronómetros', () {
    test('Tabata: 4 × 8 de 20/10 con 1 min entre bloques = 16:10', () {
      final t = tabataTimeline();
      expect(t.where((s) => s.kind == 'trabajo').length, 32);
      expect(t.where((s) => s.kind == 'bloque').length, 3);
      expect(t.fold(0, (a, s) => a + s.seconds), 4 * (8 * 20 + 7 * 10) + 3 * 60);
    });

    test('Cindy: la ronda a medias se reparte en orden', () {
      expect(splitPartialRound(0), isEmpty);
      expect(splitPartialRound(12), [('Dominadas', 5), ('Flexiones', 7)]);
      expect(splitPartialRound(29), [('Dominadas', 5), ('Flexiones', 10), ('Sentadillas', 14)]);
    });

    test('EMOM: un minuto fallado baja al escalón anterior', () {
      expect(emomFallback(10), 8);
      expect(emomFallback(8), 6);
      expect(emomFallback(6), 5);
      const r = EmomResult(target: 6, perMinute: [6, 6, 4, 5, 5, 5]);
      expect(r.completeMinutes, 2);
    });
  });

  test('PlanExerciseDraft.copyWith conserva la superserie', () {
    final e = PlanExerciseDraft(name: 'Curl con banda', sets: 3, supersetGroup: 'brazos');
    expect(e.copyWith(sets: 2).supersetGroup, 'brazos');
  });

  test('variantes: la cadena de progresión se parte en escalones (§18.4)', () {
    expect(progressionSteps('pike → pies elevados → HSPU asistido → HSPU'),
        ['pike', 'pies elevados', 'HSPU asistido', 'HSPU']);
    expect(progressionSteps('Progresa con carga, no con más repeticiones.'), isEmpty);
    expect(progressionSteps(null), isEmpty);
  });

  test('el informe nombra el formato de resistencia y la variante de cada serie', () {
    final md = buildReport(ReportInput(
      programStart: DateTime(2026, 8, 26),
      rangeStart: DateTime(2026, 10, 12),
      rangeEnd: DateTime(2026, 10, 18),
      today: DateTime(2026, 10, 18),
      sessions: [
        SessionEntry(date: DateTime(2026, 10, 14), type: SessionType.resistencia, mode: 'cindy', roundsDone: 12, extraReps: 7),
        SessionEntry(date: DateTime(2026, 10, 15), type: SessionType.trenSuperior, sets: const [
          SetEntry(exercise: 'Flexión arquero', setIndex: 1, reps: 4, variant: 'arquero'),
        ]),
      ],
    ));
    expect(md, contains('Resistencia (Cindy)'));
    expect(md, contains('- Cindy: 12 rondas + 7 reps en 20 min'));
    expect(md, contains('4 (arquero)'));
  });

  test('una Cindy cortada dice lo que duró y que no es marca', () {
    final md = buildReport(ReportInput(
      programStart: DateTime(2026, 8, 26),
      rangeStart: DateTime(2026, 10, 12),
      rangeEnd: DateTime(2026, 10, 18),
      today: DateTime(2026, 10, 18),
      sessions: [
        SessionEntry(
          date: DateTime(2026, 10, 16),
          type: SessionType.resistencia,
          mode: 'cindy',
          roundsDone: 1,
          extraReps: 3,
          totalSec: 600 + 120 + 180,
          warmupSec: 600,
          cooldownSec: 180,
          incomplete: true,
        ),
      ],
    ));
    expect(md, contains('- Cindy: 1 ronda + 3 reps en 2:00 (cortada antes de los 20 min: no es marca)'));
    expect(md, isNot(contains('en 20 min')));
  });
}
