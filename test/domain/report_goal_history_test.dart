import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/alerts.dart';
import 'package:seguimiento/domain/report/period_summary.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/report/report_stats.dart';

/// Plan 009, R2: un informe de un período pasado se mide con la meta que
/// regía esos días. Hoy (19 oct) el mínimo es 160; la semana 12–18 oct comió
/// 145 g con un mínimo vigente de 130.
void main() {
  DateTime d(int day) => DateTime(2026, 10, day);

  GoalVersion v(GoalMetric m, double? value, DateTime? from, {int id = 0}) => GoalVersion(
      id: id, metric: m, value: value, effectiveFrom: from, acceptedAt: from ?? d(1), origin: GoalOrigin.perfil);

  ReportInput week(GoalHistory? goals, {int protein = 145}) => ReportInput(
        programStart: d(1),
        rangeStart: d(12),
        rangeEnd: d(18),
        today: d(19),
        targets: const Targets(proteinMin: 160, proteinMax: 180, kcalTarget: 2600),
        closedDays: const {'2026-10-12', '2026-10-13', '2026-10-14'},
        meals: [
          for (final day in [12, 13, 14])
            MealEntry(date: d(day), slot: MealSlot.almuerzo, items: [
              MealItemEntry(label: 'Comida', macros: Macros(kcal: 2400, protein: protein.toDouble())),
            ]),
        ],
        goals: goals,
      );

  // Lo de siempre: legado 130–160 (no se sabe desde cuándo), conocido desde
  // el 1 oct, y la meta nueva 160–180 desde hoy.
  final changedToday = GoalHistory([
    v(GoalMetric.proteinaMin, 130, null, id: 1),
    v(GoalMetric.proteinaMax, 160, null, id: 2),
    v(GoalMetric.kcal, 2400, null, id: 3),
    v(GoalMetric.proteinaMin, 130, d(1), id: 4),
    v(GoalMetric.proteinaMax, 160, d(1), id: 5),
    v(GoalMetric.kcal, 2400, d(1), id: 6),
    v(GoalMetric.proteinaMin, 160, d(19), id: 7),
    v(GoalMetric.proteinaMax, 180, d(19), id: 8),
    v(GoalMetric.kcal, 2600, d(19), id: 9),
  ]);

  test('145 g con mínimo vigente 130: cumple, sin alerta, y el informe dice 130–160, no 160–180', () {
    final input = week(changedToday);
    final alerts = buildAlerts(ReportStats(input));
    expect(alerts.where((a) => a.startsWith('Proteína')), isEmpty);
    final report = buildReport(input);
    expect(report, contains('(meta 130–160)'));
    expect(report, isNot(contains('160–180')));
    expect(report, contains('kcal promedio: 2.400 (meta 2.400'));
    final s = summarizePeriod(input);
    expect((s.proteinDaysAtMin, s.proteinDaysGoalUnknown, s.proteinGoal!.single), (3, 0, 130));
  });

  test('contraprueba: con el mismo 145 g y mínimo vigente 160 sí alerta', () {
    final strict = GoalHistory([
      v(GoalMetric.proteinaMin, 160, null, id: 1),
      v(GoalMetric.proteinaMin, 160, d(1), id: 2),
    ]);
    final alerts = buildAlerts(ReportStats(week(strict)));
    expect(alerts, contains('Proteína promedio 145 g, bajo el mínimo de 160 g'));
  });

  test('sin historia cargada: la de Targets, como antes', () {
    final alerts = buildAlerts(ReportStats(week(null)));
    expect(alerts, contains('Proteína promedio 145 g, bajo el mínimo de 160 g'));
  });

  test('la meta cambió dentro del período: cada día con la suya y el cambio explícito', () {
    final midweek = GoalHistory([
      v(GoalMetric.proteinaMin, 130, null, id: 1),
      v(GoalMetric.proteinaMin, 130, d(1), id: 2),
      v(GoalMetric.proteinaMin, 160, d(14), id: 3),
    ]);
    final input = week(midweek);
    final alerts = buildAlerts(ReportStats(input));
    final protein = alerts.where((a) => a.startsWith('Proteína')).toList();
    expect(protein, hasLength(1));
    expect(protein.single, startsWith('Proteína bajo el mínimo que regía en 1 de 3 días cerrados (mié 14)'));
    expect(protein.single, contains('130 g → 160 g desde el 14 oct'));
    expect(buildReport(input), contains('mínimo 130 → 160 desde el 14 oct'));
    expect(summarizePeriod(input).proteinDaysAtMin, 2);
  });

  test('legado desconocido: sin alerta concluyente, la incertidumbre dicha', () {
    final legacyOnly = GoalHistory([
      v(GoalMetric.proteinaMin, 160, null, id: 1),
      v(GoalMetric.proteinaMax, 180, null, id: 2),
      v(GoalMetric.kcal, 2600, null, id: 3),
    ]);
    final input = week(legacyOnly);
    final alerts = buildAlerts(ReportStats(input));
    expect(alerts.where((a) => a.contains('bajo el mínimo')), isEmpty);
    expect(alerts, contains('Proteína promedio 145 g: el mínimo que regía esos días no está registrado, sin comparar'));
    final report = buildReport(input);
    expect(report, contains('(meta histórica no registrada)'));
    expect(report, isNot(contains('160')));
    final s = summarizePeriod(input);
    expect((s.proteinDaysAtMin, s.proteinDaysGoalUnknown), (0, 3));
  });

  test('parte del período sin vigencia registrada: se juzga sólo lo conocido', () {
    final partly = GoalHistory([
      v(GoalMetric.proteinaMin, 130, null, id: 1),
      v(GoalMetric.proteinaMin, 150, d(13), id: 2),
    ]);
    final alerts = buildAlerts(ReportStats(week(partly)));
    final protein = alerts.singleWhere((a) => a.startsWith('Proteína'));
    expect(protein, startsWith('Proteína bajo el mínimo que regía en 2 de 2 días cerrados'));
    expect(protein, contains('1 día con meta histórica no registrada'));
  });
}
