import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/report_builder.dart';

import '../support/sqlite_host.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository exercises;
  late PlanRepository plan;
  late TrainingRepository training;
  late NutritionRepository nutrition;
  late BodyRepository body;
  late ReportRepository report;

  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);

  setUp(() {
    db = openInMemoryDatabase();
    exercises = ExerciseRepository(db);
    plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    nutrition = NutritionRepository(db);
    body = BodyRepository(db);
    report = ReportRepository(db, nutrition);
  });

  tearDown(() => db.close());

  test('perfil por defecto: el programa arranca el día de la instalación', () async {
    final p = await ProfileRepository(db).get();
    expect(p.startDate, dayKey(DateTime.now()));
    expect(p.proteinMin, 130);
    expect(p.kcalFloor, 2000);
  });

  test('ejercicios: mismo nombre sin importar mayúsculas ni espacios', () async {
    final a = await exercises.getOrCreate('Flexiones');
    final b = await exercises.getOrCreate('  flexiones ');
    expect(a, b);
  });

  test('plan versionado: editar crea versión nueva y la vigente depende de la fecha', () async {
    final v1 = PlanDraft.empty(d(8, 26));
    v1.days[0]
      ..type = DayType.circuito
      ..targetRounds = 7
      ..exercises.add(PlanExerciseDraft(name: 'Flexiones', sets: 4, repsMin: 15));
    v1.days[1].type = DayType.futbol;
    final id1 = await plan.saveAsNewVersion(v1);

    final v2 = await plan.load(id1)
      ..validFrom = d(9, 20);
    v2.days[0].targetRounds = 8;
    final id2 = await plan.saveAsNewVersion(v2);

    expect(id2, isNot(id1));
    expect((await plan.activeVersion(d(9, 14)))!.id, id1);
    expect((await plan.activeVersion(d(9, 21)))!.id, id2);
    final monday = await plan.dayFor(d(9, 21));
    expect(monday!.versionNumber, 2);
    expect(monday.day.targetRounds, 8);
    expect(monday.day.exercises.single.targetLabel, '4×15');
    // v1 no cambió.
    expect((await plan.load(id1)).days[0].targetRounds, 7);
  });

  test('sesión: guardar, recargar con series partidas y vueltas, editar', () async {
    final draft = SessionDraft(
      date: d(9, 18),
      startTime: '15:10',
      totalSec: 1200,
      warmupSec: 540,
      cooldownSec: 180,
      roundsDone: 3,
      rpe: 8,
      limitingExercise: 'flexiones',
      roundMarksSec: [150, 310, 480],
      sets: [
        SetDraft(exercise: 'Flexiones', reps: 15),
        SetDraft(exercise: 'Flexiones', reps: 15, split: true, splitDetail: '12+3'),
        SetDraft(exercise: 'Sentadillas', reps: 20),
      ],
    );
    final id = await training.save(draft);
    final loaded = await training.load(id);
    expect(loaded.sets.length, 3);
    expect(loaded.sets[1].splitDetail, '12+3');
    expect(loaded.roundMarksSec, [150, 310, 480]);
    expect(loaded.limitingExercise, 'flexiones');
    expect(await training.historicalMeanRoundSec(), 160);

    loaded.sets.removeLast();
    await training.save(loaded);
    expect((await training.load(id)).sets.length, 2);
    final list = await training.watchRecent().first;
    expect(list.single.splitSets, 1);
  });

  test('comidas: macros congelados aunque cambie el catálogo; copiar comida', () async {
    final foodId = await nutrition.saveFood(FoodsCompanion.insert(
      name: 'Huevo',
      basis: FoodBasis.unit,
      unitLabel: const Value('huevo'),
      kcal: 72,
      protein: 6.3,
    ));
    final food = (await nutrition.watchFoods().first).single;
    final meal = MealDraft(date: d(9, 18), time: '07:30', slot: MealSlot.desayuno)
      ..items.add(MealItemDraft.fromFood(food, 3))
      ..items.add(MealItemDraft(label: 'Arepa', macros: const Macros(kcal: 200, protein: 4)));
    final mealId = await nutrition.saveMeal(meal);

    await nutrition.saveFood(FoodsCompanion(id: Value(foodId), kcal: const Value(999)));
    final day = await nutrition.watchDay(d(9, 18)).first;
    expect(day.single.macros.kcal, closeTo(216 + 200, 1e-9));

    await nutrition.copyMeal(mealId, d(9, 19));
    expect((await nutrition.watchDay(d(9, 19)).first).single.items.length, 2);

    await nutrition.deleteFood(foodId);
    final after = await nutrition.watchDay(d(9, 18)).first;
    expect(after.single.items.first.foodId, isNull);
    expect(after.single.macros.kcal, closeTo(416, 1e-9));
  });

  test('medidas: una toma por día, reemplazable', () async {
    await body.saveCheckIn(d(8, 26), true, {MeasureSite.abdomen: 86, MeasureSite.cadera: 95});
    await body.saveCheckIn(d(8, 26), true, {MeasureSite.abdomen: 85.5});
    final all = await body.watchCheckIns().first;
    expect(all.single.valuesCm, {MeasureSite.abdomen: 85.5});
    expect(await body.lastCheckInBefore(d(9, 20)), d(8, 26));
  });

  test('informe de extremo a extremo desde la base', () async {
    final v1 = PlanDraft.empty(d(8, 26));
    for (final w in [1, 3, 5]) {
      v1.days[w - 1].type = DayType.circuito;
    }
    v1.days[1].type = DayType.futbol;
    await plan.saveAsNewVersion(v1);

    await training.save(SessionDraft(date: d(9, 9), totalSec: 1200, warmupSec: 540, cooldownSec: 180, roundsDone: 7));
    await training.save(SessionDraft(
      date: d(9, 18),
      startTime: '15:10',
      totalSec: 1200,
      warmupSec: 540,
      cooldownSec: 180,
      roundsDone: 8,
      sets: [SetDraft(exercise: 'Flexiones', reps: 15, split: true, splitDetail: '12+3')],
    ));
    await training.saveFootball(FootballGamesCompanion.insert(date: '2026-09-22', minutes: 60, format: const Value(7)));
    await nutrition.saveMeal(MealDraft(date: d(9, 16), slot: MealSlot.almuerzo)
      ..items.add(MealItemDraft(label: 'Bandeja', macros: const Macros(kcal: 1500, protein: 50))));
    await body.addWeight(d(8, 26), 72.3);
    await body.addWeight(d(9, 18), 71.4);
    await ProfileRepository(db).saveWeekNote(4, 'Semana pesada');

    // La semana 4 depende del inicio del programa: se fija aquí.
    const start = '2026-08-26';
    await ProfileRepository(db).save(const ProfilesCompanion(startDate: Value(start)));
    final w = weekRange(parseDay(start), 4);
    final md = buildReport(await report.load(w.start, w.end, today: d(9, 22)));

    expect(md, contains('# Informe semanal — 16 sep a 22 sep 2026'));
    expect(md, contains('Semana 4 desde inicio (26 ago) · Plan v1'));
    expect(md, contains('- Sesiones: 1/3 · Fútbol: 1/1'));
    expect(md, contains('- Récord de rondas: 8 (anterior: 7)'));
    expect(md, contains('- Flexiones: 12+3 (partida)'));
    expect(md, contains('| mar 22 sep | 7 | 60 |'));
    expect(md, contains('- Peso promedio: 71,4 kg (en ayunas, 1 pesaje) · Δ vs línea base: -0,9 kg'));
    expect(md, contains('Sesiones por debajo del plan: 1 de 3 en los días ya cerrados'));
    expect(md, endsWith('Semana pesada'));
  });

  test('editar una toma y cambiarle la fecha no la duplica', () async {
    await body.saveCheckIn(d(9, 1), true, {MeasureSite.abdomen: 80});
    await body.saveCheckIn(d(9, 2), false, {MeasureSite.abdomen: 79.5}, replacing: d(9, 1));

    final checkIns = await body.watchCheckIns().first;
    expect(checkIns.map((c) => dayKey(c.date)), ['2026-09-02']);
    expect(checkIns.single.valuesCm[MeasureSite.abdomen], 79.5);
  });

  test('guardar la misma fecha al editar reemplaza, no suma', () async {
    await body.saveCheckIn(d(9, 1), true, {MeasureSite.abdomen: 80, MeasureSite.cadera: 95});
    await body.saveCheckIn(d(9, 1), true, {MeasureSite.abdomen: 81}, replacing: d(9, 1));

    final checkIns = await body.watchCheckIns().first;
    expect(checkIns.single.valuesCm, {MeasureSite.abdomen: 81});
  });

  test('récord: las rondas estimadas no cuentan, las de una sesión incompleta sí', () async {
    await training.save(SessionDraft(date: d(9, 1), roundsDone: 7));
    await training.save(SessionDraft(date: d(9, 3), roundsDone: 9, roundsEstimated: true));
    expect(await training.bestRounds(), 7);

    await training.save(SessionDraft(date: d(9, 5), roundsDone: 8, incomplete: true, plannedRounds: 10));
    expect(await training.bestRounds(), 8);

    await ProfileRepository(db).save(const ProfilesCompanion(startDate: Value('2026-09-01')));
    final input = await report.load(d(9, 8), d(9, 14), today: d(9, 14));
    expect(input.previousRoundsRecord, 8);
  });

  test('el plan no se guarda con rangos al revés ni ceros', () {
    final draft = PlanDraft.empty(d(9, 1));
    draft.days[0]
      ..type = DayType.circuito
      ..targetRounds = 6
      ..exercises.add(PlanExerciseDraft(name: 'Flexiones', repsMin: 12, repsMax: 10));
    expect(planDraftProblem(draft), contains('reps mínimas (12) mayores que las máximas (10)'));

    draft.days[0].exercises.single.repsMax = 15;
    expect(planDraftProblem(draft), isNull);

    draft.days[0].targetRounds = 0;
    expect(planDraftProblem(draft), contains('meta de rondas'));

    // Un día de descanso con basura no bloquea: sus ejercicios no se guardan.
    draft.days[0].targetRounds = 6;
    draft.days[6].exercises.add(PlanExerciseDraft(name: 'X', sets: 0));
    expect(planDraftProblem(draft), isNull);
  });

  test('un día del plan se relee por id aunque después haya versiones nuevas', () async {
    final v1 = PlanDraft.empty(d(9, 1));
    v1.days[0]
      ..type = DayType.circuito
      ..targetRounds = 6
      ..exercises.add(PlanExerciseDraft(name: 'Flexiones', repsMin: 10));
    await plan.saveAsNewVersion(v1);
    final monday = await plan.dayFor(d(9, 7));

    final v2 = PlanDraft.empty(d(9, 7));
    v2.days[0]
      ..type = DayType.circuito
      ..targetRounds = 8;
    await plan.saveAsNewVersion(v2);

    final again = await plan.dayById(monday!.dayId);
    expect(again!.day.targetRounds, 6);
    expect(again.day.exercises.single.name, 'Flexiones');
    expect(again.versionNumber, 1);
    expect(await plan.dayById(99999), isNull);
  });
}
