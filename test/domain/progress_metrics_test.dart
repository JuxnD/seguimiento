import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/progress_metrics.dart';
import 'package:seguimiento/domain/personal_radar.dart';
import '../support/radar_fixture.dart';
import 'package:seguimiento/domain/cindy_protocol.dart' as pure;
import 'package:seguimiento/features/training/v3_timers.dart' as timer;

void main() {
  test('una sola fecha apta no demuestra un cambio entre fechas', () {
    final single = buildPersonalRadar(tests: [
      knownRadarTest(round: 1, item: 'pullup', value: 8, date: radarDay)
    ], asOf: radarDay);
    expect(single.axis(RadarAxis.pull).current?.value, 8);
    expect(single.axis(RadarAxis.pull).changePercent, isNull);
    final sameDay = buildPersonalRadar(tests: [
      knownRadarTest(round: 1, item: 'pullup', value: 5, date: radarDay),
      knownRadarTest(round: 2, item: 'pullup', value: 8, date: radarDay)
    ], asOf: radarDay);
    expect(sameDay.axis(RadarAxis.pull).changePercent, isNull);
  });
  test('sólo un prefijo parcial no demuestra el denominador de Cindy', () {
    final row = radarCindy(rounds: 0, extra: 3);
    final axis = buildPersonalRadar(
            tests: [],
            cindy: [row],
            references: radarReferences(),
            asOf: radarDay)
        .axis(RadarAxis.circuit);
    expect(axis.currentPercent, isNull);
    expect(axis.observations.single.cindy?.rounds, 0);
    expect(axis.observations.single.cindy?.extraReps, 3);
  });
  test('conteo extremo no acredita receta por overflow de entero', () {
    final row = radarCindy(rounds: 0x5555555555555556, extra: 0, sets: [
      const CindySet(exercise: 'Dominadas', reps: 5),
      const CindySet(exercise: 'Flexiones', reps: 10)
    ]);
    final axis = buildPersonalRadar(tests: [], cindy: [row], asOf: radarDay)
        .axis(RadarAxis.circuit);
    expect(axis.current, isNull);
    expect(axis.observations.single.cindy, same(row));
  });
  test('helper extraído conserva receta y export público del timer', () {
    expect(timer.cindyRound, same(pure.cindyRound));
    expect(timer.splitPartialRound(17),
        [('Dominadas', 5), ('Flexiones', 10), ('Sentadillas', 2)]);
    expect(pure.cindyRepsPerRound, 30);
  });
  test('referencias inválidas no producen coordenada ni defaults', () {
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      final radar = buildPersonalRadar(
          tests: radarTests(),
          asOf: radarDay,
          references: radarReferences(pull: value));
      expect(radar.axis(RadarAxis.pull).reference, isNull);
      expect(radar.axis(RadarAxis.pull).current?.value, 8);
      expect(radar.axis(RadarAxis.pull).currentPercent, isNull);
    }
    for (final ref in [
      RadarReference(
          id: 'r',
          axis: RadarAxis.pull,
          value: 10,
          unit: 'kg',
          from: radarDay,
          source: 'f'),
      RadarReference(
          id: 'r',
          axis: RadarAxis.push,
          value: 10,
          unit: 'reps',
          from: radarDay,
          source: 'f'),
      RadarReference(
          id: 'r',
          axis: RadarAxis.pull,
          value: 10,
          unit: 'reps',
          from: DateTime(2026, 10, 11),
          source: 'f'),
      RadarReference(
          id: 'r',
          axis: RadarAxis.pull,
          value: 10,
          unit: 'reps',
          from: DateTime(2026, 10, 1),
          until: DateTime(2026, 10, 9),
          source: 'f'),
      RadarReference(
          id: '',
          axis: RadarAxis.pull,
          value: 10,
          unit: 'reps',
          from: radarDay,
          source: 'f'),
      RadarReference(
          id: 'r',
          axis: RadarAxis.pull,
          value: 10,
          unit: 'reps',
          from: radarDay,
          source: ' '),
      RadarReference(
          id: 'r',
          axis: RadarAxis.pull,
          value: 10,
          unit: 'reps',
          from: radarDay,
          source: 'f',
          protocol: 'carga5kg'),
    ]) {
      final radar = buildPersonalRadar(
          tests: radarTests(),
          asOf: radarDay,
          references: {RadarAxis.pull: ref});
      expect(radar.axis(RadarAxis.pull).reference, isNull);
    }
  });
  test('cambio de referencia escala ambos perfiles; no cambia delta crudo', () {
    final one = buildPersonalRadar(
            tests: radarTests(), references: radarReferences(), asOf: radarDay)
        .axis(RadarAxis.pull);
    final two = buildPersonalRadar(
            tests: radarTests(),
            references: radarReferences(pull: 20),
            asOf: radarDay)
        .axis(RadarAxis.pull);
    expect((one.initialPercent, one.currentPercent), (50, 80));
    expect((two.initialPercent, two.currentPercent), (25, 40));
    expect(one.changePercent, two.changePercent);
  });
  test(
      'política documentada separa histórica de actual; sin política no caduca',
      () {
    final radar = buildPersonalRadar(
        tests: radarTests(),
        references: radarReferences(),
        asOf: DateTime(2026, 11, 10),
        freshness: const RadarFreshnessPolicy(
            maxAgeDays: 14, source: 'Política FICTICIA de prueba'));
    expect(radar.axis(RadarAxis.pull).current, isNull);
    expect(radar.axis(RadarAxis.pull).lastEligible?.value, 8);
    expect(
        radar.axis(RadarAxis.pull).currentIssue, contains('Política FICTICIA'));
    expect(
        buildPersonalRadar(tests: radarTests(), asOf: DateTime(2026, 11, 10))
            .axis(RadarAxis.pull)
            .current
            ?.value,
        8);
    expect(
        () => buildPersonalRadar(
            tests: [],
            asOf: radarDay,
            freshness: const RadarFreshnessPolicy(maxAgeDays: 14, source: '')),
        throwsArgumentError);
  });
  test('inválidos, fechas desconocidas y bilateral mixto conservan payload',
      () {
    for (final value in [-1.0, 1.5, double.nan, double.infinity]) {
      final radar = buildPersonalRadar(tests: [
        knownRadarTest(round: 1, item: 'pullup', value: value, date: radarDay)
      ], asOf: radarDay);
      expect(radar.axis(RadarAxis.pull).current, isNull);
      expect(
          radar.axis(RadarAxis.pull).observations.single.testRows.single.value,
          value.isNaN ? isNaN : value);
    }
    final radar = buildPersonalRadar(tests: [
      const TestResult(round: 1, item: 'pullup', value: 3),
      knownRadarTest(
          round: 1,
          item: 'bulgarian_split_squat',
          side: 'I',
          value: 20,
          date: DateTime(2026, 10, 1)),
      knownRadarTest(
          round: 1,
          item: 'bulgarian_split_squat',
          side: 'D',
          value: 25,
          date: DateTime(2026, 10, 2))
    ], asOf: radarDay);
    expect(radar.axis(RadarAxis.pull).latestObserved, isNull);
    expect(radar.axis(RadarAxis.pull).observations.single.reason,
        contains('Fecha sin registrar'));
    expect(radar.axis(RadarAxis.legs).current, isNull);
    expect(radar.axis(RadarAxis.legs).latestObserved?.reason,
        contains('Fechas distintas'));
  });
  test('Cindy importada/estimada/cortada/30min/Tabata/dudas sigue observada',
      () {
    for (final row in [
      radarCindy(imported: true),
      radarCindy(estimated: true),
      radarCindy(incomplete: true),
      radarCindy(total: 2100),
      radarCindy(total: 1501),
      radarCindy(mode: 'tabata'),
      radarCindy(technique: false),
      radarCindy(day: 11)
    ]) {
      final axis = buildPersonalRadar(tests: [], cindy: [row], asOf: radarDay)
          .axis(RadarAxis.circuit);
      expect(axis.current, isNull);
      expect(axis.observations.single.cindy, same(row));
      expect(axis.observations.single.reason, isNotEmpty);
    }
  });
  test('receta distinta/lastre/variante/partial desconocido no normaliza', () {
    for (final row in [
      radarCindy(extra: null),
      radarCindy(extra: 30),
      radarCindy(sets: [const CindySet(exercise: 'Flexiones', reps: 15)]),
      radarCindy(rounds: 1, extra: 0, sets: [
        const CindySet(exercise: 'Dominadas', reps: 5, loadKg: 5),
        const CindySet(exercise: 'Flexiones', reps: 10),
        const CindySet(exercise: 'Sentadillas', reps: 15)
      ]),
      radarCindy(rounds: 1, extra: 0, sets: [
        const CindySet(exercise: 'Dominadas', reps: 5, variant: 'supina'),
        const CindySet(exercise: 'Flexiones', reps: 10),
        const CindySet(exercise: 'Sentadillas', reps: 15)
      ])
    ]) {
      final axis = buildPersonalRadar(
              tests: [],
              cindy: [row],
              references: radarReferences(),
              asOf: radarDay)
          .axis(RadarAxis.circuit);
      expect(axis.currentPercent, isNull);
      expect(axis.observations.single.value, isNull);
      expect(axis.observations.single.cindy, same(row));
    }
    final missing = buildPersonalRadar(tests: [], asOf: radarDay);
    final zero = buildPersonalRadar(tests: [
      knownRadarTest(round: 1, item: 'pullup', value: 0, date: radarDay)
    ], references: radarReferences(), asOf: radarDay);
    expect(missing.axis(RadarAxis.pull).current, isNull);
    expect(zero.axis(RadarAxis.pull).currentPercent, 0);
  });
  test('primera/última apta por fecha, no mayor T ni máximo', () {
    final radar = buildPersonalRadar(tests: [
      knownRadarTest(
          round: 3, item: 'pullup', value: 10, date: DateTime(2026, 10, 1)),
      knownRadarTest(
          round: 1, item: 'pullup', value: 8, date: DateTime(2026, 10, 9))
    ], asOf: radarDay);
    expect(radar.axis(RadarAxis.pull).firstEligible?.value, 10);
    expect(radar.axis(RadarAxis.pull).current?.value, 8);
  });
  test('bilateral parcial/dudoso posterior y futuro no reemplazan apta', () {
    final radar = buildPersonalRadar(tests: [
      ...radarTests(),
      knownRadarTest(
          round: 3,
          item: 'bulgarian_split_squat',
          side: 'I',
          value: 30,
          date: radarDay),
      knownRadarTest(
          round: 3,
          item: 'pullup',
          value: 99,
          clean: false,
          date: DateTime(2026, 10, 11))
    ], asOf: radarDay);
    expect(radar.axis(RadarAxis.legs).current?.value, 20);
    expect(radar.axis(RadarAxis.legs).latestObserved?.eligible, isFalse);
    expect(radar.axis(RadarAxis.pull).current?.value, 8);
    expect(
        radar.axis(RadarAxis.pull).latestObserved?.reason, contains('futura'));
  });
  test('misma referencia ambos perfiles, >100 crudo y cero observado', () {
    final radar = buildPersonalRadar(tests: [
      knownRadarTest(
          round: 1, item: 'pullup', value: 0, date: DateTime(2026, 10, 1)),
      knownRadarTest(
          round: 2, item: 'pullup', value: 12, date: DateTime(2026, 10, 9))
    ], references: radarReferences(), asOf: radarDay);
    final pull = radar.axis(RadarAxis.pull);
    expect(pull.initialPercent, 0);
    expect(pull.currentPercent, 120);
    expect(pull.changePercent, isNull);
    expect(RadarProfile(radar, initial: false).fractions.first, 1);
    expect(RadarProfile(radar, initial: false).closed, isFalse);
  });
  test('Cindy misma receta con parciales diferentes y ventana real20', () {
    final radar = buildPersonalRadar(tests: [], cindy: [
      radarCindy(id: 's1', day: 1, rounds: 6, extra: 3),
      radarCindy(id: 's2', extra: 15, total: 1400, warmup: 100, cooldown: 100)
    ], references: radarReferences(), asOf: radarDay);
    expect(radar.axis(RadarAxis.circuit).firstEligible?.value, 6.1);
    expect(radar.axis(RadarAxis.circuit).current?.value, 8.5);
    expect(radar.axis(RadarAxis.circuit).currentPercent, 85);
  });
  test('sin referencias crudo, seis ejes aptos cierran sólo con referencias',
      () {
    final noRefs = buildPersonalRadar(
        tests: radarTests(), cindy: [radarCindy()], asOf: radarDay);
    expect(noRefs.axis(RadarAxis.pull).current?.value, 8);
    expect(RadarProfile(noRefs, initial: false).closed, isFalse);
    final full = buildPersonalRadar(
        tests: radarTests(),
        cindy: [radarCindy(id: 'first', day: 1, rounds: 6), radarCindy()],
        references: radarReferences(),
        asOf: radarDay);
    expect(RadarProfile(full, initial: false).closed, isTrue);
    expect(RadarProfile(full, initial: true).closed, isTrue);
  });
}
