import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/sleep_entry.dart';

/// Horas en cama (§16.19): más allá de 9 h y escritas a mano.
void main() {
  test('los botones llegan a 10 h y traen 9,5', () {
    expect(sleepOptions.last, 10);
    expect(sleepOptions, contains(9.5));
  });

  test('10 h 11 min se entiende de varias formas', () {
    for (final raw in ['10:11', '10h11', '10 h 11 min', '10h 11m']) {
      expect(parseSleepHours(raw), closeTo(10.18, 0.001), reason: raw);
    }
    expect(parseSleepHours('10,2'), 10.2);
    expect(parseSleepHours('10.5'), 10.5);
    expect(parseSleepHours('10 h'), 10);
  });

  test('fuera de 0–16 o sin sentido: no se guarda', () {
    for (final raw in ['', 'mucho', '17', '0', '-2', '10:75']) {
      expect(parseSleepHours(raw), isNull, reason: raw);
    }
  });

  test('un valor escrito no es un botón', () {
    expect(isSleepOption(10.18), isFalse);
    expect(isSleepOption(9.5), isTrue);
    expect(isSleepOption(null), isFalse);
  });

  test('lo escrito se muestra en horas y minutos', () {
    expect(formatSleepHours(10.18), '10 h 11 min');
    expect(formatSleepHours(10), '10 h');
  });
}
