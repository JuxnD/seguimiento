import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/alerts.dart';
import 'package:seguimiento/domain/report/period_summary.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/report/report_stats.dart';

import '../support/sqlite_host.dart';

/// Oráculos de la revisión R2 de Codex (285eaf4, seguimiento-009-review-r2),
/// adoptados sin cambios de aserción con el arreglo de 009: fixtures
/// ficticios sobre SQLite y los lectores reales. Rojos en 49051e3.
void main() {
  late AppDatabase db;
  late GoalRepository goals;
  late NutritionRepository nutrition;
  DateTime d(int day) => DateTime(2026, 10, day);

  setUpAll(useHostSqlite);
  setUp(() {
    db = openInMemoryDatabase();
    goals = GoalRepository(db);
    nutrition = NutritionRepository(db);
  });
  tearDown(() => db.close());

  Future<ReportInput> week({int currentMin = 130, int? changedOn, bool unknown = false}) async {
    await db.delete(db.goalVersions).go();
    await seedGoalVersions(db, effectiveFrom: unknown ? null : d(1),
        origin: unknown ? GoalOrigin.legado : GoalOrigin.inicio, now: unknown ? d(20) : d(1));
    if (currentMin != 130) {
      await goals.updateProfile(ProfilesCompanion(proteinMin: Value(currentMin)),
          origin: GoalOrigin.perfil, now: d(changedOn!));
    }
    for (var date = d(12); !date.isAfter(d(18)); date = addDays(date, 1)) {
      await nutrition.saveMeal(MealDraft(date: date, slot: MealSlot.cena, items: [
        MealItemDraft(label: 'Registro ficticio R2',
            macros: const Macros(kcal: 2500, protein: 145, carbs: 300, fat: 80)),
      ]));
      await nutrition.setClosed(date, true);
    }
    return ReportRepository(db, nutrition).load(d(12), d(18), today: d(21), withPrevious: false);
  }

  List<String> proteinAlerts(ReportInput input) =>
      buildAlerts(ReportStats(input)).where((s) => s.startsWith('Proteína promedio')).toList();
  String proteinLine(ReportInput input) =>
      buildReport(input).split('\n').firstWhere((s) => s.startsWith('- Proteína promedio:'));

  test('R2 control: 145 g con mínimo vigente 130 no queda bajo mínimo', () async {
    final input = await week();
    final summary = summarizePeriod(input);
    expect((summary.closedDays, summary.avgProtein, summary.proteinDaysAtMin, summary.proteinDaysGoalUnknown),
        (7, 145, 7, 0));
    expect(proteinAlerts(input), isEmpty);
    expect(proteinLine(input), contains('(meta 130–160)'));
  });

  test('R2 control: 145 g con mínimo vigente 160 sí queda bajo mínimo', () async {
    final input = await week(currentMin: 160, changedOn: 11);
    final summary = summarizePeriod(input);
    expect((summary.closedDays, summary.avgProtein, summary.proteinDaysAtMin, summary.proteinDaysGoalUnknown),
        (7, 145, 0, 0));
    expect(proteinAlerts(input), ['Proteína promedio 145 g, bajo el mínimo de 160 g']);
    expect(proteinLine(input), contains('(meta 160–160)'));
  });

  test('R2 historia: 145 g cumplieron 130 aunque el mínimo actual sea 160', () async {
    final input = await week(currentMin: 160, changedOn: 20);
    final summary = summarizePeriod(input);
    expect((summary.closedDays, summary.avgProtein, summary.proteinDaysAtMin, summary.proteinDaysGoalUnknown),
        (7, 145, 7, 0), reason: 'la meta documentada de cada día era130');
    final warnings = proteinAlerts(input);
    final line = proteinLine(input);
    // ignore: avoid_print
    print('R2 histórico: $warnings | $line');
    expect({'warnings': warnings, 'summaryUsesCurrentMeta': line.contains('(meta 160–160)')},
        {'warnings': <String>[], 'summaryUsesCurrentMeta': false},
        reason: 'alerta y texto del informe deben respetar las metas históricas');
  });

  test('R2 desconocido: 145 g no prueban incumplir una meta histórica sin fecha', () async {
    final input = await week(currentMin: 160, changedOn: 21, unknown: true);
    final summary = summarizePeriod(input);
    expect((summary.closedDays, summary.avgProtein, summary.proteinDaysAtMin, summary.proteinDaysGoalUnknown),
        (7, 145, 0, 7), reason: 'la migración20oct no conoce metas de12–18oct');
    final warnings = proteinAlerts(input);
    final line = proteinLine(input);
    // ignore: avoid_print
    print('R2 desconocido: $warnings | $line');
    expect({'warnings': warnings, 'summaryUsesCurrentMeta': line.contains('(meta 160–160)')},
        {'warnings': <String>[], 'summaryUsesCurrentMeta': false},
        reason: 'meta desconocida exige abstenerse, no aplicar el mínimo actual');
  });
}
