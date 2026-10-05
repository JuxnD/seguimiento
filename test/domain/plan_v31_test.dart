import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/plan_v3.dart';
import 'package:seguimiento/domain/progress.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart' show scriptDayFrom;
import 'package:seguimiento/features/training/v3_timers.dart' show tabataTimeSplit, tabataTimeline;

/// Plan v3.1 (§19, 5 oct).
void main() {
  final start = DateTime(2026, 10, 12); // lunes
  DateTime d(int month, int day) => DateTime(2026, month, day);

  group('calendario (§19.4)', () {
    test('9 semanas: bloque 1 de 5, descarga en la 6, bloque 2 de 3', () {
      expect([for (var w = 1; w <= 9; w++) v31Phase(w)], [
        ...List.filled(5, V3Phase.bloque1),
        V3Phase.descarga,
        ...List.filled(3, V3Phase.bloque2),
      ]);
      expect([for (var w = 1; w <= 9; w++) v31ReducedVolume(w)].where((r) => r).length, 1);
      expect(v31ReducedVolume(6), isTrue);
      expect(v3WeekIndex(start, d(11, 16)), 6, reason: '16–22 nov es la descarga');
    });

    test('pruebas el viernes 11 dic; abdomen cada 2 semanas en sábado', () {
      expect(dayKey(v31TestDate(start)), '2026-12-11');
      expect(v31MeasurementDates(start).map(dayKey), ['2026-10-17', '2026-10-31', '2026-11-14', '2026-11-28', '2026-12-12']);
      expect(v31FullMeasurementDates(start).map(dayKey), ['2026-11-14', '2026-12-12']);
      expect(v31NextMeasurement(start, d(10, 17)), d(10, 17), reason: 'el mismo día todavía toca');
      expect(v31NextMeasurement(start, d(10, 18)), d(10, 31));
      expect(v31NextMeasurement(start, d(12, 13)), isNull);
    });

    test('el día dice semana, fase y la nota de la descarga', () {
      final monday = v3Day(start, start, scheme: v31Scheme)!;
      expect((monday.isV31, monday.week, monday.totalWeeks, monday.title), (true, 1, 9, 'Plan v3.1'));
      expect(monday.hint, contains('RIR 2–3'));
      expect(monday.burpees, isNull, reason: 'el v3.1 quita el EMOM de burpees');
      final deload = v3Day(start, d(11, 18), scheme: v31Scheme)!;
      expect(deload.reducedVolume, isTrue);
      expect(deload.deloadNote, 'Semana 6 del v3.1: descarga (mitad de series, sin lastre extra)');
    });
  });

  group('viernes (§19.1)', () {
    final test11 = v31TestDate(start);

    test('sin 10 rondas limpias es el circuito de progresión', () {
      expect(v31Friday(date: d(10, 16), testDate: test11), isNull);
      expect(v3Day(start, d(10, 16), scheme: v31Scheme)!.resistance, isNull);
    });

    test('desde el viernes siguiente a las 10 limpias: Cindy y Tabata alternos, Cindy de prueba cada 4 semanas', () {
      final clean = d(10, 9);
      final fridays = [d(10, 16), d(10, 23), d(10, 30), d(11, 6), d(11, 13)];
      expect([for (final f in fridays) v31Friday(date: f, testDate: test11, cleanTen: clean)], [
        (mode: ResistanceMode.cindy, cindyTest: true),
        (mode: ResistanceMode.tabata, cindyTest: false),
        (mode: ResistanceMode.cindy, cindyTest: false),
        (mode: ResistanceMode.tabata, cindyTest: false),
        (mode: ResistanceMode.cindy, cindyTest: true),
      ]);
    });

    test('las 10 limpias de un viernes cambian el siguiente, no el mismo', () {
      expect(v31Friday(date: d(10, 16), testDate: test11, cleanTen: d(10, 16)), isNull);
      expect(v31Friday(date: d(10, 23), testDate: test11, cleanTen: d(10, 16))?.mode, ResistanceMode.cindy);
    });

    test('el viernes de pruebas siempre es Cindy', () {
      expect(v31Friday(date: test11, testDate: test11), (mode: ResistanceMode.cindy, cindyTest: true));
    });
  });

  group('semana tipo (§19.1)', () {
    final plan = planV31(start);

    test('tipos por día y esquema', () {
      expect(plan.scheme, v31Scheme);
      expect(plan.days.map((d) => d.type), [
        DayType.trenSuperior,
        DayType.trenSuperior,
        DayType.piernas,
        DayType.trenSuperior,
        DayType.progresion,
        DayType.futbol,
        DayType.futbol,
      ]);
      expect(plan.days[4].main.map((e) => e.name), ['Dominadas', 'Flexiones', 'Sentadillas']);
      expect(plan.days[4].targetRounds, 10);
      expect([for (final e in plan.days[4].exercises) if (e.block == tabataBlock) e.name], tabataLowImpact);
      expect(planDraftProblem(plan), isNull);
    });

    test('lunes: pino primero, luego dominadas; remo y laterales en superserie', () {
      final steps = buildScript(scriptDayFrom(plan.days[0]));
      final work = steps.whereType<WorkStep>().toList();
      expect((work.first.exercise, work.first.holdSec), ('Pino pecho a la pared', 300));
      expect(steps[1], isA<RestStep>());
      expect(work[1].exercise, 'Dominadas');
      final remo = work.indexWhere((w) => w.exercise == 'Remo invertido (mesa)');
      expect(work.skip(remo).take(4).map((w) => w.exercise), [
        'Remo invertido (mesa)',
        'Elevaciones laterales con banda',
        'Remo invertido (mesa)',
        'Elevaciones laterales con banda',
      ]);
      expect(work.where((w) => w.exercise == 'Elevaciones laterales con banda').length, 4,
          reason: 'la cuarta serie de laterales va sola');
    });

    test('miércoles: el FIFA 11+ es el calentamiento, no un paso', () {
      final work = buildScript(scriptDayFrom(plan.days[2])).whereType<WorkStep>();
      expect(work.any((w) => w.exercise == 'Calentamiento tipo FIFA 11+'), isFalse);
      expect(work.first.exercise, 'Salto vertical');
    });

    test('viernes: pino, 10 rondas y habilidades; el Tabata no entra al cronómetro', () {
      final steps = buildScript(scriptDayFrom(plan.days[4]));
      final work = steps.whereType<WorkStep>().toList();
      expect(work.first.exercise, 'Pino pecho a la pared');
      expect(work.where((w) => w.isRound).length, 30);
      expect(work.last.exercise, 'Toes-to-bar');
      expect(work.any((w) => w.exercise == 'Hollow rocks'), isFalse);
    });

    test('jueves: compresión (A) o L-sit (B)', () {
      final a = buildScript(scriptDayFrom(plan.days[3]), coreVariant: 'A').whereType<WorkStep>();
      final b = buildScript(scriptDayFrom(plan.days[3]), coreVariant: 'B').whereType<WorkStep>();
      expect(a.any((w) => w.exercise == 'Barca / V-sit'), isTrue);
      expect(a.any((w) => w.exercise == 'L-sit'), isFalse);
      expect(b.any((w) => w.exercise == 'L-sit'), isTrue);
    });

    test('descarga del v3.1: la mitad de las series, redondeando hacia arriba', () {
      final deload = deloadVersion(plan.days[0], half: true);
      int sets(PlanDayDraft d, String name) => d.exercises.firstWhere((e) => e.name == name).sets!;
      expect(sets(deload, 'Dominadas'), 2);
      expect(sets(deload, 'Remo invertido (mesa)'), 2);
      expect(sets(deload, 'Face pull con banda'), 1);
      final friday = deloadVersion(plan.days[4], half: true);
      expect(friday.main.map((e) => e.sets), [null, null, null], reason: 'el circuito no se toca');
    });
  });

  group('doble progresión (§19.2)', () {
    List<({int reps, int? rir})> sets(List<int> reps, [int? rir = 2]) => [for (final r in reps) (reps: r, rir: rir)];

    test('todas al tope sin fallo: con lastre, +2–5 kg', () {
      expect(
        doubleProgressionHint(repsMin: 5, repsMax: 8, plannedSets: 4, lastSets: sets([8, 8, 8, 8]), tracksLoad: true),
        '+2–5 kg de mochila y vuelve a 5',
      );
    });

    test('sin lastre: el siguiente escalón de la cadena', () {
      expect(
        doubleProgressionHint(
          repsMin: 4,
          repsMax: 6,
          plannedSets: 3,
          lastSets: sets([6, 6, 6]),
          chain: const ['arquero', 'una mano con mano elevada', 'una mano'],
          lastVariant: 'arquero',
        ),
        'una mano con mano elevada y vuelve a 4',
      );
    });

    test('no toca: una serie por debajo, una al fallo o faltan series', () {
      expect(doubleProgressionHint(repsMin: 5, repsMax: 8, plannedSets: 4, lastSets: sets([8, 8, 7, 8])), isNull);
      expect(
          doubleProgressionHint(
              repsMin: 5, repsMax: 8, plannedSets: 2, lastSets: [(reps: 8, rir: 2), (reps: 8, rir: 0)]),
          isNull);
      expect(doubleProgressionHint(repsMin: 5, repsMax: 8, plannedSets: 4, lastSets: sets([8, 8, 8])), isNull);
      expect(doubleProgressionHint(repsMin: 5, repsMax: 8, plannedSets: 2, lastSets: sets([8, 8], null)), isNotNull,
          reason: 'sin RIR anotado no frena');
    });
  });

  test('Tabata cortado: solo cuentan las pausas que llegaron', () {
    final timeline = tabataTimeline();
    expect(tabataTimeSplit(timeline, 20), (work: 20, rest: 0), reason: 'a los 20 s no hubo descanso');
    expect(tabataTimeSplit(timeline, 35), (work: 25, rest: 10));
    final all = tabataTimeline().fold(0, (a, s) => a + s.seconds);
    expect(tabataTimeSplit(timeline, all), (work: 640, rest: all - 640));
  });

  test('meta de kcal: sábado y domingo usan la de fútbol (§19.3)', () {
    expect(dailyKcalTarget(day: d(10, 16), weekdayTarget: 2100, footballTarget: 2400), 2100);
    expect(dailyKcalTarget(day: d(10, 17), weekdayTarget: 2100, footballTarget: 2400), 2400);
    expect(dailyKcalTarget(day: d(10, 18), weekdayTarget: 2100), 2100, reason: 'sin meta de fútbol, la misma');
  });
}
