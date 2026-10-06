import '../dates.dart';
import '../enums.dart';
import 'report_input.dart';

enum ReportActionKind { weighIn, mealForDay, stepsForDay }

/// Destino local tipado. Nunca se deriva de una respuesta o cita de IA.
class ReportAction {
  const ReportAction({required this.kind, required this.date, this.mealSlot});

  final ReportActionKind kind;
  final DateTime date;
  final MealSlot? mealSlot;
}

/// Sugiere a lo sumo una acción por familia y fecha explícita.
List<ReportAction> missingDataActions(ReportInput input) {
  final from = dateOnly(input.rangeStart);
  final to = dateOnly(
      input.rangeEnd.isAfter(input.today) ? input.today : input.rangeEnd);
  if (to.isBefore(from)) return const [];
  final result = <ReportAction>[];

  if (!input.weightsInRange.any((weight) =>
      weight.fasted &&
      !weight.date.isBefore(from) &&
      !weight.date.isAfter(to))) {
    result.add(ReportAction(kind: ReportActionKind.weighIn, date: to));
  }

  final mealsByDay = <String, Set<MealSlot>>{};
  for (final meal in input.meals) {
    mealsByDay.putIfAbsent(dayKey(meal.date), () => {}).add(meal.slot);
  }
  const mainMeals = [MealSlot.desayuno, MealSlot.almuerzo, MealSlot.cena];
  final span = daysBetween(from, to);
  for (var offset = 0; offset <= span; offset++) {
    final date = addDays(to, -offset);
    final key = dayKey(date);
    if (input.closedDays.contains(key)) continue;
    final recorded = mealsByDay[key];
    if (recorded == null || recorded.isEmpty) continue;
    final missing =
        mainMeals.where((slot) => !recorded.contains(slot)).firstOrNull;
    if (missing != null) {
      result.add(ReportAction(
          kind: ReportActionKind.mealForDay, date: date, mealSlot: missing));
      break;
    }
  }

  for (var offset = 0; offset <= span; offset++) {
    final date = addDays(to, -offset);
    if (date.weekday > DateTime.friday || input.steps.containsKey(date)) {
      continue;
    }
    result.add(ReportAction(kind: ReportActionKind.stepsForDay, date: date));
    break;
  }
  return result;
}
