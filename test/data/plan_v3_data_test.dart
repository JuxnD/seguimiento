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

/// Activar el Plan v3 sobre la base (§18).
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

  test('Hoy propone el v3.1 desde el próximo lunes, sin esperar a las 10 limpias (§19)', () async {
    final id = await training
        .save(SessionDraft(date: d(10, 9), type: SessionType.progresion, roundsDone: 9, plannedRounds: 9));
    await training.setProgressionCriteria(id, techniqueOk: true, fullRange: true, recoveryOk: true);
    expect((await dashboard.today(now: d(10, 10))).v3Suggestion, d(10, 12));
    expect((await dashboard.today(now: d(10, 5))).v3Suggestion, d(10, 12), reason: 'un lunes propone el siguiente');
  });

  test('activarlo: el v2 sigue hasta el domingo, el lunes 12 es tren superior A en semana 1', () async {
    await activatePlanV3(db, plan, d(10, 12));

    final sunday = await plan.dayFor(d(10, 11));
    expect(sunday!.scheme, isNull, reason: 'el domingo todavía rige el v2');

    final monday = await dashboard.today(now: d(10, 12));
    expect(monday.dayType, DayType.trenSuperior);
    expect((monday.v3!.week, monday.v3!.phase), (1, V3Phase.acumulacion));
    expect(monday.v3Suggestion, d(10, 19), reason: 'con el v3 viejo, el v3.1 se sigue proponiendo');

    final profile = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();
    expect(profile.nextMeasurementDate, '2026-11-06');

    // Las guías nuevas quedan con su anclaje de banda.
    final facePull =
        await (db.select(db.exercises)..where((t) => t.name.equals('Face pull con banda'))).getSingle();
    expect(facePull.anchor, 'alto');
    expect(facePull.formCues, isNotNull);
  });

  test('editar el v3 a mitad de bloque no reinicia las semanas', () async {
    await activatePlanV3(db, plan, d(10, 12));
    final v3 = (await plan.versions()).last;
    final edited = await plan.load(v3.id)
      ..validFrom = d(10, 26);
    await plan.saveAsNewVersion(edited);

    final view = await plan.dayFor(d(10, 28));
    expect(view!.validFrom, d(10, 12), reason: 'la periodización cuenta desde el primer v3');
    expect(v3WeekIndex(view.validFrom!, d(10, 28)), 3);
  });

  test('semana 4: Hoy avisa la descarga y el miércoles toca Cindy', () async {
    await activatePlanV3(db, plan, d(10, 12));
    final wednesday = await dashboard.today(now: d(11, 4));
    expect(wednesday.dayType, DayType.resistencia);
    expect(wednesday.v3!.reducedVolume, isTrue);
    expect(wednesday.v3!.resistance, ResistanceMode.cindy);
  });

  test('una sesión de Cindy guarda formato y reps sueltas', () async {
    final id = await training.save(SessionDraft(
      date: d(10, 14),
      type: SessionType.resistencia,
      mode: 'cindy',
      roundsDone: 12,
      extraReps: 7,
      sets: [SetDraft(exercise: 'Flexión arquero', reps: 4, variant: 'arquero')],
    ));
    final back = await training.load(id);
    expect((back.mode, back.roundsDone, back.extraReps), ('cindy', 12, 7));
    expect(back.sets.single.variant, 'arquero');
  });
}
