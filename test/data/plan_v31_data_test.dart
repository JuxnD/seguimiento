import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/plan_v3.dart';

import '../support/sqlite_host.dart';

/// Activar el Plan v3.1 sobre la base (§19).
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
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    await seedIfEmpty(db, plan);
  });

  tearDown(() => db.close());

  Future<int> cleanProgression(DateTime date, int rounds) async {
    final id = await training
        .save(SessionDraft(date: date, type: SessionType.progresion, roundsDone: rounds, plannedRounds: rounds));
    await training.setProgressionCriteria(id, techniqueOk: true, fullRange: true, recoveryOk: true);
    return id;
  }

  test('activarlo: semana 1, metas de §19.3 y abdomen el sábado 17', () async {
    await activatePlanV31(db, plan, d(10, 12));

    expect((await plan.dayFor(d(10, 11)))!.scheme, isNull, reason: 'el domingo todavía rige el v2');
    final monday = await dashboard.today(now: d(10, 12));
    expect(monday.dayType, DayType.trenSuperior);
    expect((monday.v3!.isV31, monday.v3!.week, monday.v3!.phase), (true, 1, V3Phase.bloque1));
    expect(monday.v3Suggestion, isNull, reason: 'ya hay v3.1');
    expect(monday.kcalTarget, 2100);
    expect(monday.blockExercises.first, startsWith('Antes, sin fatiga: Pino pecho a la pared'));
    expect((await dashboard.today(now: d(10, 17))).kcalTarget, 2400, reason: 'sábado de fútbol');

    final profile = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();
    expect((profile.proteinMin, profile.proteinMax, profile.kcalTargetFootball), (130, 160, 2400));
    expect(profile.nextMeasurementDate, '2026-10-17');
    expect((profile.measureIntervalDays, profile.measureIntervalMaxDays), (14, 21),
        reason: 'el abdomen cada 2 semanas no es "antes de tiempo" ni alerta en el informe');

    final nordic = await (db.select(db.exercises)..where((t) => t.name.equals('Nórdico (isquios)'))).getSingle();
    expect(nordic.formCues, isNotNull, reason: 'los ejercicios nuevos traen sus claves');
    final pullups = await (db.select(db.exercises)..where((t) => t.name.equals('Dominadas'))).getSingle();
    expect(pullups.tracksLoad, isTrue, reason: 'las dominadas del lunes van con mochila');
  });

  test('un v3 activado para el mismo lunes queda reemplazado por el v3.1', () async {
    await activatePlanV3(db, plan, d(10, 12));
    await activatePlanV31(db, plan, d(10, 12));
    final wednesday = await dashboard.today(now: d(10, 14));
    expect(wednesday.dayType, DayType.piernas, reason: 'en el v3.1 el miércoles es de piernas');
    expect(wednesday.v3!.isV31, isTrue);
  });

  test('el viernes es circuito hasta las 10 limpias; después Cindy de prueba', () async {
    await activatePlanV31(db, plan, d(10, 12));
    final before = await dashboard.today(now: d(10, 16));
    expect(before.dayType, DayType.progresion);
    expect(before.v3!.resistance, isNull);

    await cleanProgression(d(10, 9), 10);
    final after = await dashboard.today(now: d(10, 16));
    expect(after.dayType, DayType.resistencia);
    expect((after.v3!.resistance, after.v3!.cindyTest), (ResistanceMode.cindy, true));
    expect(after.mainExercises.single, startsWith('20 min: 5 dominadas + 10 flexiones + 15 sentadillas'));

    final tabata = await dashboard.today(now: d(10, 23));
    expect(tabata.mainExercises.first, 'Flexiones 8 × 20 s a tope');
  });

  test('10 rondas sin los criterios no cuentan como limpias', () async {
    await training.save(SessionDraft(date: d(10, 9), type: SessionType.progresion, roundsDone: 10, plannedRounds: 10));
    expect(await training.firstCleanTen(), isNull);
    await cleanProgression(d(10, 16), 10);
    expect(await training.firstCleanTen(), d(10, 16));
    expect(await training.firstCleanTen(before: d(10, 16)), isNull);
  });

  test('partido entre semana: el viernes metabólico lo avisa', () async {
    await activatePlanV31(db, plan, d(10, 12));
    await cleanProgression(d(10, 9), 10);
    await training.saveFootball(FootballGamesCompanion.insert(date: '2026-10-14', minutes: 60));
    expect((await dashboard.today(now: d(10, 16))).midweekGame, isTrue);
    expect((await dashboard.today(now: d(10, 23))).midweekGame, isFalse);
  });

  test('RIR por serie y últimas series de fuerza del mismo día de la semana', () async {
    await training.save(SessionDraft(date: d(10, 12), type: SessionType.trenSuperior, sets: [
      for (var i = 0; i < 4; i++) SetDraft(exercise: 'Dominadas', reps: 8, loadKg: 5, rir: 2),
    ]));
    // El jueves (supinas) no cuenta para el lunes.
    await training.save(SessionDraft(date: d(10, 15), type: SessionType.trenSuperior, sets: [
      SetDraft(exercise: 'Dominadas', reps: 6, rir: 1),
    ]));
    // El circuito del viernes tampoco.
    await training.save(SessionDraft(date: d(10, 16), type: SessionType.progresion, roundsDone: 10, sets: [
      SetDraft(exercise: 'Dominadas', reps: 5),
    ]));
    final last = await training.lastStrengthSets('Dominadas', d(10, 19));
    expect(last.map((s) => (s.reps, s.rir, s.loadKg)), List.filled(4, (8, 2, 5.0)));
    expect(await training.lastStrengthSets('Dominadas', d(10, 20)), isEmpty, reason: 'ningún martes antes');
  });

  test('medir en una fecha del v3.1 corre la próxima a la siguiente', () async {
    await activatePlanV31(db, plan, d(10, 12));
    await advanceV31Measurement(db, d(10, 17));
    final profile = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();
    expect(profile.nextMeasurementDate, '2026-10-31');
  });
}
