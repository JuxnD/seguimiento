import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/report/period_summary.dart';

void main() {
  final friday = DateTime(2026, 10, 9), saturday = DateTime(2026, 10, 10);
  GoalVersion v(GoalMetric metric, double? value, DateTime? day) =>
      GoalVersion(metric: metric, value: value, effectiveFrom: day, acceptedAt: saturday, origin: GoalOrigin.perfil);
  ReportInput input(GoalHistory history) => ReportInput(
          programStart: friday,
          rangeStart: friday,
          rangeEnd: saturday,
          today: saturday,
          goals: history,
          closedDays: {
            '2026-10-09',
            '2026-10-10'
          },
          meals: [
            for (final day in [friday, saturday])
              MealEntry(
                  date: day,
                  slot: MealSlot.desayuno,
                  items: const [MealItemEntry(label: 'FICTICIO', macros: Macros(kcal: 2400, protein: 140))])
          ]);
  test('proteína130→160 distingue promedio140 de días1/2', () {
    final history = GoalHistory([v(GoalMetric.proteinaMin, 130, friday), v(GoalMetric.proteinaMin, 160, saturday)]);
    final summary = summarizePeriod(input(history));
    expect(summary.avgProtein, 140);
    expect(summary.proteinDaysAtMin, 1);
    expect(summary.proteinGoal!.single, isNull);
    expect(summary.proteinGoal!.segments.map((s) => s.value), [130, 160]);
  });
  test('null explícito de proteína/pasos no es un día fallido ni legado', () {
    final i = ReportInput(programStart: friday, rangeStart: friday, rangeEnd: saturday, today: saturday,
      goals: GoalHistory([v(GoalMetric.proteinaMin,null,friday),v(GoalMetric.pasos,null,friday)]),
      steps:{friday:0}, closedDays:{'2026-10-09'}, meals:input(GoalHistory([])).meals.where((m)=>m.date==friday).toList());
    final summary=summarizePeriod(i);
    expect((summary.proteinDaysAtMin,summary.proteinDaysGoalUnknown,summary.proteinDaysWithoutGoal),(0,0,1));
    expect((summary.weekdaysAtGoal,summary.weekdaysGoalUnknown,summary.weekdaysWithoutGoal),(0,0,1));
    expect(summary.avgProtein,140);
    expect(summary.stepsDays,1);
  });
  test('kcal calendario real propia/heredada/ausente sin fallback cargado', () {
    for (final football in [2800.0, null]) {
      final i = input(GoalHistory([v(GoalMetric.kcal, 2400, friday), v(GoalMetric.kcalFutbol, football, friday)]));
      expect(i.kcalReferenceOn(friday).value, 2400);
      expect(i.kcalReferenceOn(saturday).value, football ?? 2400);
      expect(summarizePeriod(i).kcalGoal!.changed, football != null);
    }
    final missing = input(GoalHistory([]));
    expect(missing.kcalReferenceOn(friday).known, isFalse);
    expect(missing.kcalReferenceOn(friday).value, isNull);
    expect(summarizePeriod(missing).proteinDaysGoalUnknown, 2);
    expect(summarizePeriod(missing).kcalGoal!.single, isNull);
    final legacy = input(GoalHistory([v(GoalMetric.kcal, 2500, null), v(GoalMetric.proteinaMin, 130, null)]));
    expect(legacy.kcalReferenceOn(friday).known, isFalse);
    expect(summarizePeriod(legacy).proteinDaysAtMin, 0);
  });
}
