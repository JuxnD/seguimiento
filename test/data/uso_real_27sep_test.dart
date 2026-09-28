import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/report_builder.dart';

import '../support/sqlite_host.dart';

/// Defectos que salieron del uso real el domingo 27 sep 2026 (traspaso §16).
void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late DashboardRepository dashboard;

  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    final nutrition = NutritionRepository(db);
    dashboard = DashboardRepository(db, plan, nutrition, ProfileRepository(db));
    await ProfileRepository(db).save(const ProfilesCompanion(startDate: Value('2026-08-26')));

    // Semana del plan real: lun circuito, mar bloques, mié ligero, jue
    // bloques, vie progresión, sáb y dom fútbol.
    final v = PlanDraft.empty(d(8, 26));
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
  });

  tearDown(() => db.close());

  group('§16.1 el fútbol cuenta en Hoy', () {
    test('un partido registrado hoy marca el día como hecho', () async {
      final before = await dashboard.today(now: d(9, 27));
      expect(before.trained, isFalse);

      await training.saveFootball(FootballGamesCompanion.insert(
          date: '2026-09-27', minutes: 90, intensity: const Value(7), knock: const Value(false)));

      final after = await dashboard.today(now: d(9, 27));
      expect(after.trained, isTrue);
      expect(after.footballToday!.minutes, 90);
      expect(after.sessionsToday, 0, reason: 'el partido no se disfraza de sesión');
    });

    test('la racha incluye los días de fútbol', () async {
      await training.save(SessionDraft(date: d(9, 25), type: SessionType.progresion, roundsDone: 8));
      await training.saveFootball(FootballGamesCompanion.insert(date: '2026-09-26', minutes: 60));
      await training.saveFootball(FootballGamesCompanion.insert(date: '2026-09-27', minutes: 90));

      expect((await dashboard.today(now: d(9, 27))).streak, 3);
    });

    test('el informe de la semana 23–29 sep cuenta el partido del domingo', () async {
      await training.saveFootball(FootballGamesCompanion.insert(date: '2026-09-27', minutes: 90));
      final report = ReportRepository(db, NutritionRepository(db));
      final md = buildReport(await report.load(d(9, 23), d(9, 29), today: d(9, 27)));
      expect(md, contains('Fútbol: 1/2'));
      expect(md, contains('| dom 27 sep | 5 | 90 |'));
    });

    test('el partido guarda el día elegido, no el de hoy', () async {
      await training.saveFootball(FootballGamesCompanion.insert(date: dayKey(d(9, 26)), minutes: 70));
      final game = await db.select(db.footballGames).getSingle();
      expect(game.date, '2026-09-26');
    });

    test('tras un domingo intenso o con golpe, el lunes avisa que baje', () async {
      await training.saveFootball(FootballGamesCompanion.insert(date: '2026-09-27', minutes: 90, intensity: const Value(6)));
      expect((await dashboard.today(now: d(9, 28))).hardFootballYesterday, isNull);

      await (db.update(db.footballGames)).write(const FootballGamesCompanion(knock: Value(true)));
      final monday = await dashboard.today(now: d(9, 28));
      expect(monday.hardFootballYesterday, isNotNull);
      expect(monday.dayType, DayType.circuito);
    });
  });

  group('§16.2 récord de 11', () {
    test('un circuito guardado en día de bloques se señala y al corregirlo sale del récord', () async {
      await training.save(SessionDraft(date: d(9, 25), type: SessionType.progresion, roundsDone: 8));
      // Martes 22 sep: día de bloques guardado como circuito de 11 rondas.
      final wrong = await training.save(SessionDraft(date: d(9, 22), type: SessionType.circuito, roundsDone: 11));

      final before = await dashboard.today(now: d(9, 27));
      expect(before.roundsRecord, 11);
      expect(before.recordSuspect!.sessionId, wrong);
      expect(before.recordSuspect!.plannedType, DayType.bloques);

      final draft = await training.load(wrong)
        ..type = SessionType.bloques;
      await training.save(draft);

      final after = await dashboard.today(now: d(9, 27));
      expect(after.roundsRecord, 8);
      expect(after.recordSuspect, isNull);
    });

    test('un récord en día de circuito no se señala', () async {
      await training.save(SessionDraft(date: d(9, 25), type: SessionType.progresion, roundsDone: 8));
      expect((await dashboard.today(now: d(9, 27))).recordSuspect, isNull);
    });
  });

  group('§16.3–16.4 catálogo que crece solo', () {
    late NutritionRepository nutrition;

    setUp(() async {
      nutrition = NutritionRepository(db);
      await seedFoodsIfEmpty(db);
    });

    test('el pan Mipan y los platos que se repiten vienen sembrados', () async {
      final mipan = (await nutrition.foodNamed('pan mipan (unidad 60 g)'))!;
      expect(mipan.kcal, 199);
      expect(mipan.source, MacroSource.etiqueta);
      expect((await nutrition.foodNamed('Avena bebida (vaso 350 g)'))!.portionMacros.kcal, 280);
      expect((await nutrition.foodNamed('Sopa de mondongo + arroz'))!.origin, FoodOrigin.semilla);
    });

    test('el nombre se compara sin mayúsculas, tildes ni espacios de sobra', () async {
      final id = await nutrition.saveFreeEntryFood('Pasta con atún', const Macros(kcal: 700, protein: 40));
      expect((await nutrition.foodNamed('  PASTA con   atun '))!.id, id);
      expect(await nutrition.foodNamed('pasta con pollo'), isNull);
    });

    test('una entrada libre queda como alimento estimado de una porción', () async {
      final id = await nutrition.saveFreeEntryFood('Arepa de huevo', const Macros(kcal: 400, protein: 12, carbs: 40, fat: 20));
      final food = (await nutrition.foodById(id))!;
      expect(food.origin, FoodOrigin.entradaLibre);
      expect(food.source, MacroSource.estimado);
      expect(food.unitLabel, 'porción');
      expect(food.isCustom, isTrue);

      // Registrada ×1,5 sigue contando como estimación en el informe.
      final item = MealItemDraft.fromFood(food, 1.5);
      expect(item.macros.kcal, 600);
      expect(item.sourceVerified, isNull);
    });

    test('actualizar valores reescribe el alimento; guardar como nuevo busca otro nombre', () async {
      final id = await nutrition.saveFreeEntryFood('Mondongo', const Macros(kcal: 600, protein: 30));
      final food = (await nutrition.foodById(id))!;
      await nutrition.saveFreeEntryFood('Mondongo', const Macros(kcal: 650, protein: 34), replacing: food);
      expect((await nutrition.foodById(id))!.kcal, 650);
      expect((await db.select(db.foods).get()).where((f) => f.name == 'Mondongo'), hasLength(1));

      expect(await nutrition.freeFoodName('mondongo'), 'mondongo (2)');
      await nutrition.saveFreeEntryFood('Mondongo (2)', const Macros(kcal: 900, protein: 40));
      expect(await nutrition.freeFoodName('Mondongo'), 'Mondongo (3)');
    });

    test('sugerencias: favoritos, luego personalizados, luego lo sembrado', () async {
      final custom = await nutrition.saveFreeEntryFood('Pasta de la casa', const Macros(kcal: 800, protein: 30));
      final huevo = (await nutrition.foodNamed('Huevo (unidad)'))!;
      await nutrition.setFavorite(huevo.id, true);

      final list = await nutrition.foodsForSuggestions();
      expect(list.first.id, huevo.id);
      expect(list[1].id, custom);
      expect(list.skip(2).every((f) => !f.isCustom && !f.favorite), isTrue);
    });

    test('un alimento se convierte en combo de un toque', () async {
      final food = (await nutrition.foodNamed('Sopa de mondongo + arroz'))!;
      await nutrition.templateFromFood(food);
      final combo = (await nutrition.templates()).firstWhere((t) => t.name == food.name);
      expect(combo.items.single.$1.id, food.id);
      expect(combo.macros.kcal, 650);
    });

    test('dos cifras escritas a mano del mismo plato son la misma', () {
      expect(sameMacros(const Macros(kcal: 880, protein: 38), const Macros(kcal: 880.4, protein: 38)), isTrue);
      expect(sameMacros(const Macros(kcal: 880, protein: 38), const Macros(kcal: 900, protein: 38)), isFalse);
    });
  });

  group('§14 pasos diarios', () {
    test('anotar otra vez el mismo día reemplaza; Hoy muestra la cifra y la meta', () async {
      final steps = StepsRepository(db);
      await steps.setSteps(d(9, 29), 1935);
      await steps.setSteps(d(9, 29), 4200);
      expect(await steps.day(d(9, 29)), 4200);

      final today = await dashboard.today(now: d(9, 29));
      expect(today.stepsToday, 4200);
      expect(today.stepsGoal, 7500);
      expect(today.stepsProgress, closeTo(0.56, 0.01));
      expect((await dashboard.today(now: d(9, 27))).stepsGoal, isNull, reason: 'domingo sin meta');
    });

    test('el informe trae el promedio semanal y lo compara con la semana anterior', () async {
      final steps = StepsRepository(db);
      await steps.setSteps(d(9, 17), 3000); // semana anterior
      await steps.setSteps(d(9, 23), 1935);
      await steps.setSteps(d(9, 24), 8000);
      await steps.setSteps(d(9, 27), 12000);

      final report = ReportRepository(db, NutritionRepository(db));
      final md = buildReport(await report.load(d(9, 23), d(9, 29), today: d(9, 29)));
      expect(md, contains('- Pasos: 7.312/día (3 días registrados) (+4.312 vs semana anterior) · '
          'entre semana 4.968 (meta 7.500, 1/2 días en meta)'));
    });
  });

  group('§13 movilidad', () {
    test('es opcional: no marca Hoy, no sostiene la racha y va aparte en el informe', () async {
      await training.save(SessionDraft(date: d(9, 24), type: SessionType.circuitoLigero, roundsDone: 5, rpe: 6));
      await training.save(SessionDraft(date: d(9, 25), type: SessionType.movilidad, totalSec: 540));
      await training.save(SessionDraft(date: d(9, 26), type: SessionType.movilidad, totalSec: 480));

      final friday = await dashboard.today(now: d(9, 25));
      expect(friday.trained, isFalse, reason: 'el viernes tocaba progresión y no se hizo');
      expect((await dashboard.today(now: d(9, 26))).streak, 0, reason: 'la movilidad no reemplaza una sesión');

      final report = ReportRepository(db, NutritionRepository(db));
      final input = await report.load(d(9, 23), d(9, 29), today: d(9, 29));
      expect(input.sessions.map((s) => s.type), [SessionType.circuitoLigero]);
      final md = buildReport(input);
      expect(md, contains('- Movilidad (opcional): 2 (17 min)'));
      expect(md, isNot(contains('| Movilidad |')));
    });
  });
}
