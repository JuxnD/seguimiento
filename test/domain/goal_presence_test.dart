import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/report/report_input.dart';

void main() {
  final day = DateTime(2026, 10, 12);
  GoalVersion version(GoalMetric metric, double? value, {DateTime? from}) =>
      GoalVersion(
          metric: metric,
          value: value,
          effectiveFrom: from ?? day,
          acceptedAt: day,
          origin: GoalOrigin.perfil);
  ReportInput input(GoalHistory? history) => ReportInput(
      programStart: day,
      rangeStart: day,
      rangeEnd: day,
      today: day,
      goals: history,
      targets: const Targets(kcalTarget: 2400, proteinMin: 130));

  test('023 historia cargada ausente nunca cae al placeholder de GoalSpan', () {
    final span = GoalSpan.over(GoalHistory([]), GoalMetric.proteinaMin, [day],
        fallback: 130);
    expect((span.segments.length, span.unknownDays), (0, 1));
  });
  test('011 API: cuatro estados de presencia, compatibilidad sólo sin historia',
      () {
    final number = input(GoalHistory([version(GoalMetric.proteinaMin, 140)]))
        .referenceOn(GoalMetric.proteinaMin, day, 130);
    final none = input(GoalHistory([version(GoalMetric.proteinaMin, null)]))
        .referenceOn(GoalMetric.proteinaMin, day, 130);
    final unknown =
        input(GoalHistory([])).referenceOn(GoalMetric.proteinaMin, day, 130);
    final compatibility =
        input(null).referenceOn(GoalMetric.proteinaMin, day, 130);
    expect((
      number.known,
      number.value,
      none.known,
      none.value,
      unknown.known,
      unknown.value,
      compatibility.known,
      compatibility.value
    ), (
      true,
      140,
      true,
      null,
      false,
      null,
      true,
      130
    ));
  });
  test('011 calendario: fútbol propio, herencia, semanalnull y desconocido',
      () {
    final sunday = DateTime(2026, 10, 18);
    for (final c in [
      (2400.0, 2700.0, true, 2700.0),
      (2400.0, null, true, 2400.0),
      (null, null, true, null),
    ]) {
      final at = input(GoalHistory([
        version(GoalMetric.kcal, c.$1),
        version(GoalMetric.kcalFutbol, c.$2)
      ])).kcalReferenceOn(sunday);
      expect((at.known, at.value), (c.$3, c.$4));
    }
    expect(
        input(GoalHistory([version(GoalMetric.kcal, 2400)]))
            .kcalReferenceOn(sunday)
            .known,
        false);
  });
}
