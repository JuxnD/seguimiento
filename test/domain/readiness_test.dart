import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/readiness.dart';
import 'package:seguimiento/domain/recovery.dart';

/// Recuperación activa propuesta por la carga (§19.17). Fechas ficticias con
/// la misma forma que el caso del traspaso: sábado, domingo doble y lunes.
void main() {
  // sáb 2, dom 3, lun 4 de marzo de 2030.
  final sat = DateTime(2030, 3, 2);
  final sun = DateTime(2030, 3, 3);
  final mon = DateTime(2030, 3, 4);

  LoadItem game(DateTime d, int min, int effort) => LoadItem(date: d, minutes: min, effort: effort, isFootball: true);
  LoadItem session(DateTime d, int min, int? effort) => LoadItem(date: d, minutes: min, effort: effort);

  final weekend = [game(sat, 60, 5), game(sun, 90, 7), game(sun, 60, 8)];

  /// Mañana completa y tranquila: sin señales propias.
  ReadinessInput calm(List<LoadItem> load, {bool test = false, DateTime? today}) => ReadinessInput(
        today: today ?? mon,
        load: load,
        stairs: 0,
        muscleSoreness: 2,
        ill: false,
        restingHrToday: 60,
        restingHrBaseline: List.filled(14, 60),
        sleepHours: 8,
        testOrAttemptToday: test,
      );

  test('fin de semana de tres partidos: el lunes de test sale amarillo y el test se mueve', () {
    final a = readiness(calm(weekend, test: true));
    expect(a.level, ReadinessLevel.yellow);
    expect(a.action, SuggestedAction.recoveryActive);
    expect(a.load3Days, 1410);
    expect(a.reasons, contains('Carga de anteayer y ayer: 1.410 (sáb 300 · dom 630 · dom 480)'));
    expect(a.reasons, contains('2 partidos entre ayer y hoy'));
    expect(a.moveTestToTomorrow, isTrue);
    expect(a.reasons.join(' '), isNot(contains('48 h')), reason: 'las ventanas son por días, no por horas');
  });

  test('sin test hoy no se propone mover nada', () {
    final a = readiness(calm(weekend));
    expect(a.level, ReadinessLevel.yellow);
    expect(a.moveTestToTomorrow, isFalse);
  });

  test('carga de anteayer y ayer: 899 es verde, 900 es amarillo', () {
    // 90 min × 10 = 900; 899 = 899 min × 1.
    expect(readiness(calm([session(sun, 899, 1)])).level, ReadinessLevel.green);
    expect(readiness(calm([session(sun, 90, 10)])).level, ReadinessLevel.yellow);
    // Lo de hace 3 días ya no entra.
    expect(readiness(calm([session(DateTime(2030, 3, 1), 90, 10)])).level, ReadinessLevel.green);
    // §16.29.2: la sesión de hoy no cambia la decisión de hoy.
    expect(readiness(calm([session(mon, 90, 10)])).level, ReadinessLevel.green);
  });

  test('dos partidos entre ayer y hoy, aunque la carga sea baja', () {
    final a = readiness(calm([game(sun, 20, 3), game(mon, 20, 3)]));
    expect(a.level, ReadinessLevel.yellow);
    expect(a.reasons, ['2 partidos entre ayer y hoy']);
    expect(readiness(calm([game(sat, 20, 3), game(mon, 20, 3)])).level, ReadinessLevel.green,
        reason: 'anteayer queda fuera de "ayer y hoy"');
  });

  group('pulso contra la base', () {
    ReadinessInput hr(int today, {int baseLen = 14}) => ReadinessInput(
          today: mon,
          load: const [],
          stairs: 0,
          muscleSoreness: 0,
          ill: false,
          restingHrToday: today,
          restingHrBaseline: List.filled(baseLen, 60),
          sleepHours: 8,
        );

    test('+4 verde, +5 amarillo, +10 rojo', () {
      expect(readiness(hr(64)).level, ReadinessLevel.green);
      expect(readiness(hr(65)).level, ReadinessLevel.yellow);
      final red = readiness(hr(70));
      expect(red.level, ReadinessLevel.red);
      expect(red.action, SuggestedAction.restOnly);
      expect(red.reasons.first, 'Pulso en reposo 70: +10 sobre tu base (60)');
    });

    test('con menos de 7 lecturas no hay base: no decide y lo dice', () {
      final a = readiness(hr(80, baseLen: 6));
      expect(a.level, ReadinessLevel.green);
      expect(a.confident, isFalse);
      expect(a.missing, ['Pulso: sin base (6 de 7 lecturas)']);
    });
  });

  test('escaleras: 2 verde, 3–4 amarillo, 5 rojo', () {
    ReadinessInput st(int v) => ReadinessInput(
        today: mon, load: const [], stairs: v, muscleSoreness: 0, ill: false,
        restingHrToday: 60, restingHrBaseline: List.filled(14, 60), sleepHours: 8);
    expect(readiness(st(2)).level, ReadinessLevel.green);
    expect(readiness(st(3)).level, ReadinessLevel.yellow);
    expect(readiness(st(4)).level, ReadinessLevel.yellow);
    expect(readiness(st(5)).level, ReadinessLevel.red);
  });

  test('dolor muscular: 5 verde, 6 amarillo', () {
    ReadinessInput so(int v) => ReadinessInput(
        today: mon, load: const [], stairs: 0, muscleSoreness: v, ill: false,
        restingHrToday: 60, restingHrBaseline: List.filled(14, 60), sleepHours: 8);
    expect(readiness(so(5)).level, ReadinessLevel.green);
    expect(readiness(so(6)).level, ReadinessLevel.yellow);
  });

  group('sueño', () {
    ReadinessInput sl(double h, List<LoadItem> load) => ReadinessInput(
        today: mon, load: load, stairs: 0, muscleSoreness: 0, ill: false,
        restingHrToday: 60, restingHrBaseline: List.filled(14, 60), sleepHours: h);

    test('menos de 6 h es amarillo; 6 h no', () {
      expect(readiness(sl(5.9, const [])).level, ReadinessLevel.yellow);
      expect(readiness(sl(6, const [])).level, ReadinessLevel.green);
    });

    test('esfuerzo 8 ayer pide al menos 7 h', () {
      final hard = [session(sun, 30, 8)];
      final a = readiness(sl(6.9, hard));
      expect(a.level, ReadinessLevel.yellow);
      expect(a.reasons, ['Ayer esfuerzo 8 y 6,9 h de sueño']);
      expect(readiness(sl(7, hard)).level, ReadinessLevel.green);
      expect(readiness(sl(6.9, [session(sun, 30, 7)])).level, ReadinessLevel.green);
    });
  });

  test('enfermo o fiebre: rojo, y el rojo manda sobre el amarillo', () {
    final a = readiness(ReadinessInput(
        today: mon, load: weekend, stairs: 0, muscleSoreness: 0, ill: true,
        restingHrToday: 60, restingHrBaseline: List.filled(14, 60), sleepHours: 8));
    expect(a.level, ReadinessLevel.red);
    expect(a.reasons.first, 'Marcaste enfermo, fiebre o dolor agudo');
    expect(a.advice, isNot(contains('activación')), reason: 'el rojo no propone el bloque del amarillo');
  });

  test('sin registro de la mañana: no se declara un verde confiado', () {
    final a = readiness(ReadinessInput(today: mon, load: const []));
    expect(a.level, ReadinessLevel.green);
    expect(a.confident, isFalse);
    expect(a.missing, ['Sueño: sin dato', 'Pulso: sin dato', 'Escaleras: sin dato', 'Dolor muscular: sin dato']);
    expect(a.title, 'Hoy: el plan normal, con datos incompletos');
    expect(a.advice, contains('falta'));
  });

  group('aguda:crónica', () {
    // Días suaves (10 min × 2 = 20) y una última semana fuerte (25 × 10 = 250).
    List<LoadItem> history(int days) => [
          for (var k = days - 1; k >= 0; k--)
            k < 7 ? session(DateTime(2030, 3, 4 - k), 25, 10) : session(DateTime(2030, 3, 4 - k), 10, 2),
        ];

    test('con 20 días de historial no se usa', () {
      final a = readiness(calm(history(20)));
      expect(a.acuteChronic, isNull);
      expect(a.level, ReadinessLevel.green);
    });

    test('con 21 días y una semana muy por encima, amarillo', () {
      // Últimos 3 días: 3 × 250 = 750, por debajo de 900.
      final a = readiness(calm(history(28)));
      expect(a.acuteChronic, greaterThan(1.5));
      expect(a.level, ReadinessLevel.yellow);
      expect(a.reasons.single, startsWith('Carga aguda:crónica'));
    });
  });

  test('aviso de la noche: con la carga de ayer y hoy sobre el umbral', () {
    expect(readinessEveningNotice(weekend, sun), contains('Mañana probablemente toca recuperación activa'));
    expect(readinessEveningNotice([game(sat, 60, 5)], sat), isNull);
  });
}
