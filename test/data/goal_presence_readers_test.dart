import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/domain/ai_report_sources.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/report/period_summary.dart';
import 'package:seguimiento/domain/report/alerts.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_stats.dart';

import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late ProfileRepository profile;
  late NutritionRepository nutrition;
  final day = DateTime(2026, 10, 12);
  setUp(() async {
    db = openInMemoryDatabase();
    profile = ProfileRepository(db);
    nutrition = NutritionRepository(db);
    await profile.confirmSetup(SetupDraft(startDate: day), now: day);
    for (var i = 0; i < 2; i++) {
      final date = day.add(Duration(days: i));
      await nutrition
          .saveMeal(MealDraft(date: date, slot: MealSlot.cena, items: [
        MealItemDraft(
            label: 'Plato ficticio',
            macros: const Macros(kcal: 901, protein: 31, carbs: 90, fat: 20)),
      ]));
      await nutrition.setClosed(date, true);
    }
  });
  tearDown(() => db.close());

  test('definir igual al placeholder y quitar conserva la fecha y los macros', () async {
    final goals = GoalRepository(db);
    final originalMeals = await db.select(db.mealItems).get();
    await goals.setPersonalGoals({GoalMetric.proteinaMin: 130}, now: day.add(const Duration(days: 1)));
    final beforeRemove = await goals.history();
    expect((beforeRemove.on(GoalMetric.proteinaMin, day)!.value,
        beforeRemove.on(GoalMetric.proteinaMin, day.add(const Duration(days: 1)))!.value), (null, 130));
    await goals.setPersonalGoals({GoalMetric.proteinaMin: null}, now: day.add(const Duration(days: 2)));
    final h = await goals.history();
    expect((h.on(GoalMetric.proteinaMin, day.add(const Duration(days: 1)))!.value,
        h.on(GoalMetric.proteinaMin, day.add(const Duration(days: 2)))!.value), (130, null));
    expect(await db.select(db.mealItems).get(), originalMeals);
    final input = await ReportRepository(db, nutrition).load(day, day.add(const Duration(days: 1)),
        today: day.add(const Duration(days: 2)), withPrevious: false);
    final summary = summarizePeriod(input);
    expect((summary.avgProtein, summary.proteinDaysWithoutGoal, summary.proteinDaysGoalUnknown), (31, 1, 0));
    expect(buildAlerts(ReportStats(input)).singleWhere((a) => a.startsWith('Proteína bajo')),
        contains('1 de 1 día cerrado'));
  });

  test('piso definido mañana y retirado después no reclasifica el día sin piso', () async {
    final goals = GoalRepository(db);
    await goals.setPersonalGoals({GoalMetric.kcalFloor: 950}, now: day.add(const Duration(days: 1)));
    await goals.setPersonalGoals({GoalMetric.kcalFloor: null}, now: day.add(const Duration(days: 2)));
    final input = await ReportRepository(db, nutrition).load(day, day.add(const Duration(days: 1)),
        today: day.add(const Duration(days: 2)), withPrevious: false);
    final stats = ReportStats(input);
    expect(stats.daysBelowFloor, [day.add(const Duration(days: 1))]);
    expect(stats.floorOn(day).value, null);
    expect(stats.floorOn(day.add(const Duration(days: 1))).value, 950);
    expect(stats.floorOn(day.add(const Duration(days: 2))).value, null);
  });

  test('altura no acepta metas; fallo SQLite revierte altura y todas las decisiones', () async {
    final goals = GoalRepository(db);
    await goals.setPersonalGoals({}, profileChanges: const ProfilesCompanion(heightCm: Value(171)), now: day);
    expect((await goals.history()).versions, hasLength(6));
    await db.customStatement('CREATE TRIGGER qa_abort_floor BEFORE INSERT ON goal_versions '
        "WHEN NEW.metric='kcalFloor' BEGIN SELECT RAISE(ABORT,'QA failure'); END");
    await expectLater(goals.setPersonalGoals({GoalMetric.proteinaMin: 130, GoalMetric.kcalFloor: 950},
        profileChanges: const ProfilesCompanion(heightCm: Value(180)), now: day), throwsA(anything));
    expect((await profile.get()).heightCm, 171);
    expect((await goals.history()).versions, hasLength(6));
    expect((await goals.history()).on(GoalMetric.proteinaMin, day)!.value, null);
  });

  test('historia cargada sin proteína es desconocida, cero pasos observado sigue registrado', () async {
    await (db.delete(db.goalVersions)..where((t) => t.metric.equals(GoalMetric.proteinaMin.name))).go();
    await StepsRepository(db).setSteps(day, 0);
    final input = await ReportRepository(db, nutrition).load(day, day.add(const Duration(days: 1)),
        today: day.add(const Duration(days: 2)), withPrevious: false);
    final s = summarizePeriod(input);
    expect((s.proteinDaysGoalUnknown, s.proteinDaysWithoutGoal), (2, 0));
    expect((s.stepsDays, s.stepsTotal), (1, 0));
    final text = buildReport(input);
    // Mínimo desconocido y máximo conocido-null son estados diferentes;
    // el informe conserva ambos en vez de un rótulo genérico para el rango.
    expect(text, contains('mínimo histórica no registrada, máximo sin meta'));
    expect(text, isNot(contains('bajo el mínimo de 130')));
    expect(input.steps.containsKey(day.add(const Duration(days: 1))), false);
  });

  test(
      '023 rojo real: Más adelante no ofrece las proyecciones internas como objetivos en Hoy',
      () async {
    final exercises = ExerciseRepository(db);
    final dashboard = await DashboardRepository(
            db, PlanRepository(db, exercises), nutrition, profile)
        .today(now: day);
    expect(dashboard.macros.kcal, 901);
    expect(dashboard.macros.protein, 31);
    expect({
      'protein': dashboard.proteinMin,
      'kcal': dashboard.kcalTarget
    }, {
      'protein': null,
      'kcal': null
    }, reason: 'alta aceptó known-null, no130/2400');
  });

  test('023 rojo real: informe y nueva fuente IA no inventan piso nutricional',
      () async {
    final input = await ReportRepository(db, nutrition).load(
        day, day.add(const Duration(days: 1)),
        today: day.add(const Duration(days: 2)), withPrevious: false);
    final stats = ReportStats(input);
    final report = buildReport(input);
    final payload = reportQuestionSources(input: input, report: report).single;
    expect(payload.text, report,
        reason: 'se comprueba el texto real usado como fuente del envío');
    expect(stats.avgKcal, 901);
    expect(stats.avgProtein, 31);
    expect({
      'belowFloor': stats.daysBelowFloor.length,
      'falseFloorLabel': payload.text.contains('Días bajo 2.000 kcal'),
      'floorAlerts': buildAlerts(stats)
          .where((s) => s.contains('días seguidos bajo'))
          .toList()
    }, {
      'belowFloor': 0,
      'falseFloorLabel': false,
      'floorAlerts': <String>[]
    });
  });
}
