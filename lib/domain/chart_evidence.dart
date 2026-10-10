import 'dates.dart';

enum ChartDayStatus { missing, incomplete, closed }

/// Visual truth only: absent record has no value. Arithmetic fillDays unchanged.
class ChartDay {
  const ChartDay(this.date, this.value, this.status, {this.evidence = ''});
  final DateTime date;
  final double? value;
  final ChartDayStatus status;
  final String evidence;
  String get statusLabel => switch (status) {
        ChartDayStatus.missing => 'Sin registro',
        ChartDayStatus.incomplete => 'Registro incompleto',
        ChartDayStatus.closed => 'Día cerrado',
      };
}

/// Optional plan009 boundary; only explicit effective dates, never current profile.
class DatedChartGoal {
  const DatedChartGoal(
      {required this.from,
      required this.to,
      required this.value,
      required this.unit,
      required this.source});
  final DateTime from, to;
  final double value;
  final String unit, source;
  bool covers(DateTime date) =>
      !dateOnly(date).isBefore(dateOnly(from)) &&
      !dateOnly(date).isAfter(dateOnly(to));
}

typedef ChartGoalResolver = DatedChartGoal? Function(
    DateTime date, String metric);

DatedChartGoal? documentedChartGoal(
    ChartGoalResolver? resolver, DateTime date, String metric, String unit) {
  final goal = resolver?.call(date, metric);
  return goal != null &&
          goal.covers(date) &&
          goal.unit == unit &&
          goal.source.trim().isNotEmpty &&
          goal.value.isFinite &&
          goal.value >= 0
      ? goal
      : null;
}
