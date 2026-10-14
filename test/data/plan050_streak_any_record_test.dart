import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

/// Plan 050, fixture reutilizado por lectura del slice 1 de 049:
/// la racha de constancia cuenta cualquier registro de
/// actividad del día (§16.24: «cuenta días con cualquier registro»; decisión
/// del owner del 14 oct). Caso real del 12 oct: sin el plan cargado, la sesión
/// se guardó como movilidad en un día de entreno y la racha se perdió.
/// Adherencia («Hoy hecho») sigue siendo sólo entrenamiento. Fechas
/// ficticias de la semana de prueba del plan sembrado.
void main() {
  late AppDatabase db;
  late TrainingRepository training;
  late DashboardRepository dashboard;
  DateTime d(int day) => DateTime(2026, 9, day);

  setUpAll(useHostSqlite);
  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    final plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    dashboard = DashboardRepository(
        db, plan, NutritionRepository(db), ProfileRepository(db));
    final setup = SetupDraft(startDate: d(1), stepsTarget: 5000)
      ..clearNutrition();
    expect(await ProfileRepository(db).confirmSetup(setup, now: d(1)), isTrue);
    // lun circuito, mar bloques, mié ligero, jue bloques, vie progresión,
    // sáb y dom fútbol (descanso para la racha).
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
  });
  tearDown(() => db.close());

  Future<int> streakOn(DateTime day) async =>
      (await dashboard.today(now: day)).streak;

  test(
      'movilidad guardada en un día de entreno mantiene la racha (caso del 12 oct)',
      () async {
    await training.save(SessionDraft(
        date: d(23), type: SessionType.circuitoLigero, roundsDone: 5, rpe: 6));
    await training
        .save(SessionDraft(date: d(24), type: SessionType.bloques, rpe: 7));
    await training.save(
        SessionDraft(date: d(25), type: SessionType.movilidad, totalSec: 900));
    expect(await streakOn(d(25)), 3);
    expect((await dashboard.today(now: d(25))).activeToday, isTrue);
    expect((await dashboard.today(now: d(26))).activeToday, isFalse);
    expect((await dashboard.today(now: d(25))).trained, isFalse,
        reason: 'adherencia del plan: sigue sin contar');
  });

  test(
      'cualquier modo cuenta: rutinas Activa y Suelta, técnica y recuperación a medias',
      () async {
    await training.save(SessionDraft(
        date: d(21),
        type: SessionType.movilidad,
        mode: morningActivaId,
        totalSec: 600));
    await training.save(SessionDraft(
        date: d(22),
        type: SessionType.movilidad,
        mode: nightSueltaId,
        totalSec: 600));
    await training.save(SessionDraft(
        date: d(23),
        type: SessionType.movilidad,
        mode: recoveryActiveId,
        totalSec: 900,
        incomplete: true));
    await training.save(SessionDraft(
        date: d(24), type: SessionType.trenSuperior, mode: 'tecnica', rpe: 4));
    expect(await streakOn(d(24)), 4);
  });

  test('fútbol cuenta y el descanso planificado no rompe', () async {
    await training.save(SessionDraft(
        date: d(25), type: SessionType.progresion, roundsDone: 9, rpe: 8));
    await training.saveFootball(FootballGamesCompanion.insert(
        date: '2026-09-26', minutes: 60, intensity: const Value(7)));
    // Domingo 27 sin nada: es descanso para la racha.
    expect(await streakOn(d(27)), 2);
    expect((await dashboard.today(now: d(26))).activeToday, isTrue);
    expect((await dashboard.today(now: d(27))).activeToday, isFalse);
  });

  test(
      'plan 052: comidas, peso, sueño y check de la mañana también sostienen la racha',
      () async {
    await training.save(SessionDraft(
        date: d(21), type: SessionType.circuito, roundsDone: 8, rpe: 8));
    // Martes 22, día de bloques: sólo registros que no son entreno.
    await db
        .into(db.bodyWeights)
        .insert(BodyWeightsCompanion.insert(date: '2026-09-22', kg: 80));
    await db
        .into(db.sleepLogs)
        .insert(SleepLogsCompanion.insert(date: '2026-09-22', hours: 7.5));
    await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(
        date: '2026-09-22', kneeStairs: const Value(1)));
    expect(await streakOn(d(22)), 2);
    expect((await dashboard.today(now: d(22))).activeToday, isTrue);
    expect((await dashboard.today(now: d(22))).trained, isFalse,
        reason: 'adherencia del plan: sigue siendo sólo entreno');
    // Miércoles 23 sin nada: hoy todavía no rompe.
    expect(await streakOn(d(23)), 2);
    // Jueves 24: el miércoles de entreno quedó vacío y la corta.
    expect(await streakOn(d(24)), 0,
        reason: 'un día de entreno sin ningún registro corta la racha');
  });
}
