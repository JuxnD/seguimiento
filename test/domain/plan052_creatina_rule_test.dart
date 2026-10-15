import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/habits.dart';
import 'package:seguimiento/domain/progress.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/supplements.dart';

/// Plan 052 (§16.27.5): en las 4 semanas de la creatina la regla de las 2
/// semanas (§19.3) no lee como grasa un peso que sube; decide la cintura.
/// Fechas ficticias.
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);
  // Lunes 5, 12 y 19 de octubre; el martes 27 la semana del 19 ya cerró.
  List<WeekAverage> weeks(List<double> kg) =>
      [for (final (i, k) in kg.indexed) WeekAverage(d(10, 5 + 7 * i), k, 3)];
  final today = d(10, 27);
  final rising = weeks([80, 80.4, 80.8]); // sube 0,4 kg/sem
  final waistDown = [(d(10, 3), 92.4), (d(10, 24), 91.2)];
  final waistStill = [(d(10, 3), 91.4), (d(10, 24), 91.2)];

  test('dentro de las 4 semanas, peso que sube y cintura que baja: no cambiar', () {
    final r = twoWeekRule(weeks: rising, abdomen: waistDown, today: today, creatineStart: d(10, 15));
    expect(r.action, KcalAction.mantener);
    expect(r.creatine, isTrue);
    expect(r.message, contains('agua intramuscular'));
    expect(r.message, contains('Decide la cintura'));
  });

  test('dentro de las 4 semanas y sin abdomen: no se concluye nada del peso', () {
    final r = twoWeekRule(weeks: rising, abdomen: const [], today: today, creatineStart: d(10, 15));
    expect(r.action, KcalAction.mantener);
    expect(r.creatine, isTrue);
    expect(r.message, contains('falta una medida reciente de abdomen'));
  });

  test('dentro de las 4 semanas, la cintura quieta decide el ajuste', () {
    final r = twoWeekRule(weeks: rising, abdomen: waistStill, today: today, creatineStart: d(10, 15));
    expect(r.action, KcalAction.bajar);
    expect(r.creatine, isTrue);
    expect(r.message, contains('−150 kcal o +2.000 pasos'));
  });

  test('fuera de las 4 semanas la regla es la de siempre', () {
    final r = twoWeekRule(weeks: rising, abdomen: waistStill, today: today, creatineStart: d(9, 1));
    final plain = twoWeekRule(weeks: rising, abdomen: waistStill, today: today);
    expect((r.action, r.message, r.creatine), (plain.action, plain.message, false));
  });

  test('una bajada rápida se lee igual aun con creatina', () {
    final r = twoWeekRule(weeks: weeks([80, 79.3, 78.4]), abdomen: const [], today: today, creatineStart: d(10, 15));
    expect(r.action, KcalAction.subir);
    expect(r.creatine, isFalse);
  });

  test('informe: constancia del rango y nota del agua', () {
    final report = buildReport(ReportInput(
      programStart: d(9, 1),
      rangeStart: d(10, 12),
      rangeEnd: d(10, 18),
      today: d(10, 18),
      supplements: [
        SupplementEntry(name: 'Creatina', start: d(10, 15), logs: const {'2026-10-15', '2026-10-17'}),
        const SupplementEntry(name: 'Omega 3'),
      ],
    ));
    expect(report, contains('- Creatina: 2 de 4 días'));
    expect(report, contains('$creatineWaterNote (15 oct – 11 nov)'));
    expect(report, isNot(contains('Omega 3')), reason: 'sin inicio no hay constancia');
  });

  test('informe: después de las 4 semanas no hay nota del agua', () {
    final report = buildReport(ReportInput(
      programStart: d(9, 1),
      rangeStart: d(11, 16),
      rangeEnd: d(11, 22),
      today: d(11, 22),
      supplements: [SupplementEntry(name: 'Creatina', start: d(10, 15), logs: const {'2026-11-16'})],
    ));
    expect(report, contains('- Creatina: 1 de 7 días'));
    expect(report, isNot(contains(creatineWaterNote)));
  });
}
