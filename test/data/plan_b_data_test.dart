import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

/// Plan B sobre la base real (§16.24, plan 039). El v3.1 ficticio empieza el
/// lunes 4 de marzo de 2030: el miércoles 6 es día de piernas. Estas pruebas
/// compilan contra 85f92c6 (sólo usan `planB` y la base) para reproducir los
/// defectos: el torso, la técnica, una sesión corta y un fútbol corto
/// sumaban a la cadena; las escaleras y la mañana verde no se miraban.
void main() {
  late AppDatabase db;
  late TrainingRepository training;
  late DashboardRepository dashboard;
  late RecoveryRepository recovery;
  final mon = DateTime(2030, 3, 4);
  final wed = DateTime(2030, 3, 6);
  DateTime day(int d) => DateTime(2030, 3, d);

  setUpAll(useHostSqlite);
  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    final plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    recovery = RecoveryRepository(db);
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, mon);
  });
  tearDown(() => db.close());

  Future<void> game(DateTime d, int minutes, int intensity) =>
      training.saveFootball(FootballGamesCompanion.insert(date: dayKey(d), minutes: minutes, intensity: Value(intensity)));

  Future<void> session(DateTime d, SessionType type, {int? rpe, int minutes = 40, String? mode, List<SetDraft>? sets}) =>
      training.save(SessionDraft(date: d, type: type, rpe: rpe, totalSec: minutes * 60, mode: mode, sets: sets));

  test('el miércoles del fixture es de piernas', () async {
    expect((await dashboard.today(now: wed)).dayType, DayType.piernas);
  });

  test('tres días sólo de torso no sacan el Plan B de piernas', () async {
    for (final d in [2, 3, 4, 5]) {
      await session(day(d), SessionType.trenSuperior, rpe: 8);
    }
    expect((await dashboard.today(now: wed)).planB, isFalse, reason: 'el torso tiene su propia cadena');
  });

  test('técnica, sesión corta y fútbol corto no suman a la cadena', () async {
    await game(day(3), 30, 8); // corto: moderado
    await session(day(4), SessionType.circuito, rpe: 7, mode: 'tecnica'); // excluida
    await session(day(5), SessionType.circuito, rpe: 7, minutes: 10); // < 20 min: moderada
    expect((await dashboard.today(now: wed)).planB, isFalse);
  });

  test('tres días de piernas intensos: Plan B con los días listados', () async {
    await game(day(3), 90, 8);
    await session(day(4), SessionType.piernas, rpe: 8);
    await session(day(5), SessionType.circuito, sets: [SetDraft(exercise: 'Sentadillas', reps: 15, rir: 2)]);
    final d = await dashboard.today(now: wed);
    expect(d.planB, isTrue);
  });

  test('con la mañana verde, la cadena sola no saca el Plan B', () async {
    await game(day(3), 90, 8);
    await session(day(4), SessionType.piernas, rpe: 8);
    await session(day(5), SessionType.piernas, rpe: 8);
    for (var i = 1; i <= 8; i++) {
      await recovery.setRestingHr(addDays(wed, -i), 60);
    }
    await recovery.setRestingHr(wed, 61);
    await db.customStatement("update morning_checks set knee_stairs = 1 where date = '2030-03-06'");
    expect((await dashboard.today(now: wed)).planB, isFalse);
  });

  test('escaleras 4 sin cadena: Plan B por la rodilla', () async {
    await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(date: '2030-03-06', kneeStairs: const Value(4)));
    expect((await dashboard.today(now: wed)).planB, isTrue);
  });

  test('enfermo (rojo de 032): manda el descanso, no hay Plan B que proponga entrenar', () async {
    await game(day(3), 90, 8);
    await session(day(4), SessionType.piernas, rpe: 8);
    await session(day(5), SessionType.piernas, rpe: 8);
    await recovery.setReadinessAnswers(wed, muscleSoreness: 0, ill: true);
    expect((await dashboard.today(now: wed)).planB, isFalse);
  });

  test('molestia en otra zona de pierna sigue siendo motivo propio', () async {
    await recovery.setSoreness(day(5), {'Isquios': 5});
    expect((await dashboard.today(now: wed)).planB, isTrue);
  });

  test('tres días con ejercicios de pierna del Plan v3.2 a RIR 2: Plan B', () async {
    for (final (d, name) in [(3, 'Nórdico inverso'), (4, 'Copenhague'), (5, 'Aterrizaje clavado')]) {
      await session(day(d), SessionType.bloques, sets: [SetDraft(exercise: name, reps: 8, rir: 2)]);
    }
    expect((await dashboard.today(now: wed)).planB, isTrue, reason: 'los nombres nuevos de pierna cuentan');
  });
}
