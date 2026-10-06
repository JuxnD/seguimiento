import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/report/missing_data_actions.dart';

void main() {
  final from = DateTime(2026, 10, 5);
  final to = DateTime(2026, 10, 11);

  test('emite acciones tipadas con fecha histórica sin escribir datos', () {
    final input = ReportInput(
      programStart: from,
      rangeStart: from,
      rangeEnd: to,
      today: to,
      meals: [
        MealEntry(date: DateTime(2026, 10, 9), slot: MealSlot.desayuno),
      ],
      steps: {DateTime(2026, 10, 9): 4000},
    );

    final actions = missingDataActions(input);

    expect(
        actions.map((action) => action.kind),
        containsAll([
          ReportActionKind.weighIn,
          ReportActionKind.mealForDay,
          ReportActionKind.stepsForDay,
        ]));
    expect(actions.firstWhere((a) => a.kind == ReportActionKind.weighIn).date,
        DateTime(2026, 10, 11));
    expect(
      actions.firstWhere((a) => a.kind == ReportActionKind.mealForDay).date,
      DateTime(2026, 10, 9),
    );
    expect(
      actions.firstWhere((a) => a.kind == ReportActionKind.mealForDay).mealSlot,
      MealSlot.almuerzo,
    );
    expect(
      actions.firstWhere((a) => a.kind == ReportActionKind.stepsForDay).date,
      DateTime(2026, 10, 8),
    );
  });

  test('respeta pesaje en rango, días cerrados y evita fechas futuras', () {
    final input = ReportInput(
      programStart: from,
      rangeStart: from,
      rangeEnd: DateTime(2026, 10, 20),
      today: DateTime(2026, 10, 8),
      weightsInRange: [WeightEntry(date: DateTime(2026, 10, 6), kg: 70)],
      meals: [MealEntry(date: DateTime(2026, 10, 7), slot: MealSlot.desayuno)],
      closedDays: {dayKey(DateTime(2026, 10, 7))},
    );

    final actions = missingDataActions(input);

    expect(actions.where((a) => a.kind == ReportActionKind.weighIn), isEmpty);
    expect(
        actions.where((a) => a.date.isAfter(DateTime(2026, 10, 8))), isEmpty);
    expect(
      actions.where((a) =>
          a.kind == ReportActionKind.mealForDay &&
          a.date == DateTime(2026, 10, 7)),
      isEmpty,
    );
  });
}
