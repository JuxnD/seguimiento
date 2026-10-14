import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';

import '../support/sqlite_host.dart';

/// Plan 052, decisión del owner del 14 oct: la racha cuenta «todo registro».
/// Comidas, peso, medidas, sueño, check matinal, molestias y días cerrados la
/// sostienen igual que una sesión; los pasos del reloj sólo el día que llegan
/// a su meta. Sin plan cargado, cada día pide un registro. Se recalcula con
/// lo ya guardado: no hace falta migrar nada. Fechas ficticias.
void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late DashboardRepository dashboard;
  DateTime d(int day) => DateTime(2026, 9, day);
  String k(int day) => '2026-09-${day.toString().padLeft(2, '0')}';

  setUpAll(useHostSqlite);
  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    dashboard = DashboardRepository(
        db, plan, NutritionRepository(db), ProfileRepository(db));
    final setup = SetupDraft(startDate: d(1), stepsTarget: 5000)
      ..clearNutrition();
    expect(await ProfileRepository(db).confirmSetup(setup, now: d(1)), isTrue);
  });
  tearDown(() => db.close());

  Future<void> weekPlan() async {
    // lun–vie entreno, sáb y dom fútbol (descanso para la racha).
    final v = PlanDraft.empty(d(1));
    const types = [
      DayType.circuito,
      DayType.bloques,
      DayType.circuitoLigero,
      DayType.bloques,
      DayType.progresion,
      DayType.futbol,
      DayType.futbol,
    ];
    for (var i = 0; i < 7; i++) {
      v.days[i].type = types[i];
    }
    await plan.saveAsNewVersion(v);
  }

  Future<int> streakOn(DateTime day) async =>
      (await dashboard.today(now: day)).streak;

  test('una semana sólo con comidas, medidas, molestias y día cerrado: racha entera',
      () async {
    await weekPlan();
    await NutritionRepository(db).saveMeal(MealDraft(date: d(21), slot: MealSlot.almuerzo)
      ..items.add(MealItemDraft(label: 'Arroz', macros: const Macros(kcal: 300))));
    await db.into(db.measurements).insert(
        MeasurementsCompanion.insert(date: k(22), site: MeasureSite.values.first, valueCm: 80));
    await db.into(db.sorenessLogs).insert(SorenessLogsCompanion.insert(date: k(23), zone: 'rodilla', level: 2));
    await db.into(db.closedDays).insert(ClosedDaysCompanion.insert(date: k(24)));
    await training.save(SessionDraft(date: d(25), type: SessionType.movilidad, totalSec: 600));
    expect(await streakOn(d(25)), 5);
    expect((await dashboard.today(now: d(25))).trained, isFalse,
        reason: 'la adherencia del plan no cambia');
  });

  test('pasos: cuentan el día que llegan a la meta, no por sólo existir', () async {
    await weekPlan();
    final steps = StepsRepository(db);
    await training.save(SessionDraft(date: d(21), type: SessionType.circuito, roundsDone: 8, rpe: 8));
    await steps.setSteps(d(22), 5200, source: 'healthConnect');
    expect(await streakOn(d(22)), 2, reason: '5200 ≥ meta de 5000');
    await steps.setSteps(d(23), 1900, source: 'healthConnect');
    expect(await streakOn(d(24)), 0,
        reason: 'el miércoles de entreno con 1900 pasos del reloj no es constancia');
  });

  test('sin plan cargado, los días seguidos con registro suman (antes sólo hoy)', () async {
    for (final day in [20, 21, 22]) {
      await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(date: k(day), kg: 80));
    }
    expect(await streakOn(d(22)), 3);
    expect(await streakOn(d(23)), 3, reason: 'hoy todavía no rompe');
    expect(await streakOn(d(24)), 0, reason: 'sin plan, el día vacío corta');
  });
}
