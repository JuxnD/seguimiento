import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/chart_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/chart_evidence.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/domain/report/report_stats.dart';
import 'package:seguimiento/data/seed_plan.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late ChartRepository repo;
  setUp(() {
    db = openInMemoryDatabase();
    repo = ChartRepository(db, NutritionRepository(db));
  });
  tearDown(() => db.close());
  test(
      'condiciones declaradas: medida ayunas/noayunas y peso antes/después fútbol',
      () async {
    for (final (day, fasted, time) in [
      (1, true, '07:00'),
      (2, true, '07:05'),
      (3, false, '19:00')
    ]) {
      await db.into(db.measurements).insert(MeasurementsCompanion.insert(
          date: '2026-10-0$day',
          site: MeasureSite.abdomen,
          valueCm: 90,
          fasted: Value(fasted),
          time: Value(time)));
    }
    final measures = await repo.measurements(MeasureSite.abdomen,
        from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 3));
    expect(measures[0].protocol, measures[1].protocol,
        reason: 'Cinco minutos no crean una condición distinta.');
    expect(measures[1].protocol, isNot(measures[2].protocol));
    expect(measures[2].comparable, isFalse);
  });
  test(
      'peso antes/después fútbol y momento desconocido son registros distintos',
      () async {
    for (final (day, moment, fasted) in [
      (1, 'antesFutbol', false),
      (2, 'despuesFutbol', false),
      (3, null, false),
      (4, 'momento inválido', true)
    ]) {
      await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(
          date: '2026-10-0$day',
          kg: 70,
          moment: Value(moment),
          fasted: Value(fasted)));
    }
    final weights = await repo.weights(
        from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 4));
    expect(weights[0].protocol, isNot(weights[1].protocol));
    expect(weights[1].protocol, isNot(weights[2].protocol));
    expect(weights.last.comparable, isFalse);
    expect(weights.last.evidence, contains('no reconocido'));
  });
  test('Cindy20 y30min separadas; warmup/cooldown no cambian ventana real20',
      () async {
    final exercises = ExerciseRepository(db),
        plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    final planId = (await plan.dayFor(DateTime(2026, 10, 1)))!.dayId;
    final training = TrainingRepository(db, exercises);
    for (final (day, total, warmup, cooldown) in [
      (1, 1500, 180, 120),
      (2, 2100, 180, 120),
      (3, 1400, 100, 100)
    ]) {
      await training.save(SessionDraft(
          date: DateTime(2026, 10, day),
          planDayId: planId,
          type: SessionType.resistencia,
          mode: 'cindy',
          roundsDone: 10,
          totalSec: total,
          warmupSec: warmup,
          cooldownSec: cooldown,
          sets: [SetDraft(exercise: 'Flexiones', reps: 10)]));
    }
    final points = await repo.rounds(
        from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 3));
    expect(points[0].protocol, isNot(points[1].protocol));
    expect(points[0].protocol, points[2].protocol);
    expect(points.every((p) => p.comparable), isTrue);
  });
  test('rango en todas las consultas, una medida, límite SQL y última fecha',
      () async {
    for (final date in ['2026-09-01', '2026-10-01', '2026-10-09']) {
      await db
          .into(db.bodyWeights)
          .insert(BodyWeightsCompanion.insert(date: date, kg: 70));
      await db.into(db.measurements).insert(MeasurementsCompanion.insert(
          date: date, site: MeasureSite.abdomen, valueCm: 90));
    }
    for (var i = 1; i <= 240; i++) {
      await db.into(db.sessions).insert(SessionsCompanion.insert(
          date: '2026-10-09',
          type: SessionType.circuito,
          roundsDone: Value(i)));
    }
    await db.into(db.sessions).insert(SessionsCompanion.insert(
        date: '2026-09-01',
        type: SessionType.circuito,
        roundsDone: const Value(999)));
    final from = DateTime(2026, 10, 5), to = DateTime(2026, 10, 10);
    expect(
        (await repo.weights(from: from, to: to)).map((p) => p.date.day), [9]);
    expect(
        (await repo.measurements(MeasureSite.abdomen,
                from: from, to: to, unit: LengthUnit.inch))
            .single
            .value,
        closeTo(90 / 2.54, 0.0001));
    expect(
        await repo.sitesWithHistory(from: from, to: to), [MeasureSite.abdomen]);
    expect(
        await repo.sitesWithHistory(
            from: DateTime(2026, 11), to: DateTime(2026, 11, 2)),
        isEmpty);
    final points = await repo.rounds(from: from, to: to, limit: 3);
    expect(points.map((p) => p.value), [238, 239, 240]);
    expect((await repo.rounds(from: from, to: to)).length, 200);
    expect((await repo.rounds(from: from, to: to, limit: 10000)).length, 200);
    expect(
        (await repo.rounds(
            from: DateTime(2026, 11), to: DateTime(2026, 11, 2))),
        isEmpty);
  });
  test(
      'nutrición nullable y cierre coinciden con informe, observado0 sobrevive',
      () async {
    final nutrition = NutritionRepository(db);
    final meal = await db
        .into(db.meals)
        .insert(MealsCompanion.insert(date: '2026-10-02', slot: MealSlot.otro));
    await db.into(db.mealItems).insert(MealItemsCompanion.insert(
        mealId: meal,
        label: 'Fixture proteína0',
        kcal: 100,
        protein: 0,
        carbs: const Value(25)));
    var days =
        await repo.nutritionDays(DateTime(2026, 10, 1), DateTime(2026, 10, 3));
    expect(days.map((d) => d.value), [null, 0, null]);
    expect(days.map((d) => d.status), [
      ChartDayStatus.missing,
      ChartDayStatus.incomplete,
      ChartDayStatus.missing
    ]);
    await nutrition.setClosed(DateTime(2026, 10, 2), true);
    days =
        await repo.nutritionDays(DateTime(2026, 10, 1), DateTime(2026, 10, 3));
    final report = ReportStats(await ReportRepository(db, nutrition).load(
        DateTime(2026, 10, 1), DateTime(2026, 10, 3),
        withPrevious: false));
    expect(
        days.where((d) => d.status == ChartDayStatus.closed).map((d) => d.date),
        report.closedDays);
    expect(report.avgProtein, 0);
  });
  test(
      'firma real separa dosis/técnica; importada/estimada/cortada/Cindy no son marca',
      () async {
    final exercises = ExerciseRepository(db),
        plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    final planId = (await plan.dayFor(DateTime(2026, 10, 1)))!.dayId;
    final training = TrainingRepository(db, exercises);
    for (var i = 0; i < 6; i++) {
      await training.save(SessionDraft(
          date: DateTime(2026, 10, i + 1),
          planDayId: planId,
          roundsDone: i + 3,
          imported: i == 3,
          roundsEstimated: i == 4,
          incomplete: i == 5,
          sets: [SetDraft(exercise: 'Flexiones', reps: i == 2 ? 20 : 10)]));
    }
    await training.save(SessionDraft(
        date: DateTime(2026, 10, 7),
        planDayId: planId,
        type: SessionType.resistencia,
        mode: 'cindy',
        roundsDone: 10,
        totalSec: 600,
        sets: [SetDraft(exercise: 'Flexiones', reps: 10)]));
    final points = await repo.rounds(
        from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 7));
    expect(points.take(3).every((p) => p.comparable), isTrue);
    expect(points[0].protocol, points[1].protocol);
    expect(points[1].protocol, isNot(points[2].protocol));
    expect(points.skip(3).every((p) => !p.comparable), isTrue);
    expect(points.last.evidence, contains('Cindy menor de20min'));
    expect(points[3].evidence, contains('historial importado'));
  });
  test('metas requieren vigencia, unidad, fuente y cifra finita', () {
    final day = DateTime(2026, 10, 2);
    DatedChartGoal? resolve(DateTime d, String metric) => DatedChartGoal(
        from: DateTime(2026, 10, 2),
        to: DateTime(2026, 10, 3),
        value: 130,
        unit: 'g',
        source: 'Fixture explícita');
    expect(documentedChartGoal(resolve, day, 'proteinMin', 'g')!.value, 130);
    expect(
        documentedChartGoal(resolve, DateTime(2026, 10, 1), 'proteinMin', 'g'),
        isNull);
    expect(documentedChartGoal(resolve, day, 'proteinMin', 'kcal'), isNull);
    expect(documentedChartGoal(null, day, 'proteinMin', 'g'), isNull);
    for (final value in [double.nan, double.infinity, -1.0]) {
      expect(
          documentedChartGoal(
              (d, m) => DatedChartGoal(
                  from: day,
                  to: day,
                  value: value,
                  unit: 'g',
                  source: 'Fixture'),
              day,
              'proteinMin',
              'g'),
          isNull);
    }
    expect(
        documentedChartGoal(
            (d, m) => DatedChartGoal(
                from: day, to: day, value: 130, unit: 'g', source: ' '),
            day,
            'proteinMin',
            'g'),
        isNull);
  });
  test('sin registro no es cero de proteína observado', () async {
    final meal = await db
        .into(db.meals)
        .insert(MealsCompanion.insert(date: '2026-10-02', slot: MealSlot.otro));
    await db.into(db.mealItems).insert(MealItemsCompanion.insert(
        mealId: meal,
        label: 'Fixture proteína0',
        kcal: 100,
        protein: 0,
        carbs: const Value(25)));
    final points =
        await repo.nutritionDaily(DateTime(2026, 10, 1), DateTime(2026, 10, 3));
    expect(points.map((p) => p.date.day), [2]);
    expect(points.single.value, 0,
        reason: 'Ítem registrado con proteína0: cero observado, no ausencia.');
  });
  test('formato y calidad no desaparecen bajo mismo nombre Circuito', () async {
    for (final mode in [null, 'tecnica']) {
      await db.into(db.sessions).insert(SessionsCompanion.insert(
          date: '2026-10-02',
          type: SessionType.circuito,
          roundsDone: const Value(3),
          mode: Value(mode)));
    }
    final points = await repo.rounds();
    expect(points[0].label, isNot(points[1].label));
  });
}
