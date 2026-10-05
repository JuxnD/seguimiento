import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/habits.dart';
import 'package:seguimiento/domain/progress.dart';

/// Hábitos del Plan v3.1 (§19.3, §19.6).
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);

  test('huevos enteros: por unidad, por gramos y sin contar las claras', () {
    expect(
      wholeEggs([
        (label: 'Huevo (unidad)', quantity: 3, unit: 'unidad'),
        (label: 'Claras de huevo', quantity: 4, unit: 'unidad'),
        (label: 'Huevos revueltos', quantity: 110, unit: 'g'),
        (label: 'Arepa con huevo', quantity: null, unit: null),
        (label: 'Pan Mipan', quantity: 75, unit: 'g'),
      ]),
      6,
    );
    expect(eggWarnAt, 5);
  });

  test('hidratación: tasa de sudor y cuánto reponer', () {
    final s = sweatReading(beforeKg: 80.4, afterKg: 79.4, fluidMl: 500, minutes: 90)!;
    expect(s.lossKg, closeTo(1.0, 1e-9));
    expect(s.ratePerHourL, closeTo(1.0, 1e-9), reason: '(1 kg + 0,5 L) en 1,5 h');
    expect(s.replaceL, closeTo(1.5, 1e-9));
    expect(sweatReading(beforeKg: 80, afterKg: null, minutes: 60), isNull);
    expect(sweatReading(beforeKg: 80, afterKg: 80.2, minutes: 60)!.replaceL, 0);
  });

  test('sueño: promedio y noches en la meta', () {
    final s = sleepSummary([7, 8, 8.5, 6.5])!;
    expect((s.average, s.nightsAtGoal, s.nights), (7.5, 2, 4));
    expect(sleepSummary(const []), isNull);
  });

  group('regla de las 2 semanas (§19.3)', () {
    List<WeekAverage> weeks(List<double> kg) =>
        [for (final (i, k) in kg.indexed) WeekAverage(d(10, 5 + 7 * i), k, 3)];
    final today = d(10, 27); // martes: la semana del 19 ya está completa

    test('baja más de 0,7 kg/sem: subir', () {
      final r = twoWeekRule(weeks: weeks([80, 79.3, 78.4]), abdomen: const [], today: today);
      expect(r.action, KcalAction.subir);
      expect(r.kgPerWeek, closeTo(0.8, 1e-9));
      expect(r.message, contains('+150–200 kcal'));
    });

    test('baja 0,5 kg/sem: no cambiar', () {
      expect(twoWeekRule(weeks: weeks([80, 79.5, 79]), abdomen: const [], today: today).action, KcalAction.mantener);
    });

    test('casi no baja y la cintura quieta 3 semanas: −150 kcal o +2.000 pasos', () {
      final r = twoWeekRule(
        weeks: weeks([80, 80.1, 79.8]),
        abdomen: [(d(10, 3), 91.4), (d(10, 24), 91.2)],
        today: today,
      );
      expect(r.action, KcalAction.bajar);
      expect(r.message, contains('−150 kcal o +2.000 pasos'));
    });

    test('casi no baja pero la cintura sí: no cambiar', () {
      final r = twoWeekRule(
        weeks: weeks([80, 80.1, 79.8]),
        abdomen: [(d(10, 3), 91.4), (d(10, 24), 90.2)],
        today: today,
      );
      expect(r.action, KcalAction.mantener);
    });

    test('la semana en curso no cuenta y sin la de 2 semanas antes faltan datos', () {
      expect(twoWeekRule(weeks: weeks([80]), abdomen: const [], today: d(10, 8)).action, KcalAction.faltanDatos);
      expect(twoWeekRule(weeks: weeks([80, 79.5]), abdomen: const [], today: today).action, KcalAction.faltanDatos);
    });
  });
}
