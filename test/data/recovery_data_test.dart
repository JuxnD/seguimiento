import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/recovery.dart';

import '../support/sqlite_host.dart';

/// Registro de la mañana, peso con momento, carga y planche sobre la base.
void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late DashboardRepository dashboard;
  late BodyRepository body;
  late RecoveryRepository recovery;

  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    body = BodyRepository(db);
    recovery = RecoveryRepository(db);
    await seedIfEmpty(db, plan);
  });

  tearDown(() => db.close());

  test('peso con momento: uno por día salvo "otro"; solo en ayunas cuenta', () async {
    await body.addWeight(d(10, 5), 80.5, moment: WeighMoment.otro, time: '09:00');
    await body.addWeight(d(10, 5), 79.95, moment: WeighMoment.otro, time: '19:30');
    await body.addWeight(d(10, 5), 79.6, moment: WeighMoment.antesDormir);
    await body.addWeight(d(10, 5), 79.5, moment: WeighMoment.antesDormir);
    final rows = await body.weightsOn(d(10, 5));
    expect(rows.map((w) => (w.kg, w.moment, w.fasted)).toSet(), {
      (80.5, 'otro', false),
      (79.95, 'otro', false),
      (79.5, 'antesDormir', false),
    });
  });

  test('día con circuito y fútbol intenso: Hoy dice día completo y avisa la carga', () async {
    await training.save(SessionDraft(
        date: d(10, 5), type: SessionType.circuitoLigero, roundsDone: 5, rpe: 7, totalSec: 1800, warmupSec: 360));
    for (final day in [3, 4, 5]) {
      await training.saveFootball(FootballGamesCompanion.insert(
          date: '2026-10-0$day', minutes: 90, intensity: const Value(8)));
    }
    final today = await dashboard.today(now: d(10, 5));
    expect(today.trained, isTrue);
    expect(today.load.todayCount, 2);
    expect(today.load.warnAnotherSession, isTrue);
  });

  test('molestia en la pierna ayer y día de piernas: plan B', () async {
    await activatePlanV31(db, plan, d(10, 12));
    await recovery.setSoreness(d(10, 13), {'Isquios': 5});
    final wed = await dashboard.today(now: d(10, 14));
    expect(wed.dayType, DayType.piernas);
    expect(wed.planB, isTrue);
  });

  test('pulso alto 3 días seguidos llega a Hoy', () async {
    for (var i = 3; i < 10; i++) {
      await recovery.setRestingHr(d(10, 20 - i), 57);
    }
    for (final day in [18, 19, 20]) {
      await recovery.setRestingHr(d(10, day), 64);
    }
    expect((await dashboard.today(now: d(10, 20))).restingHrWarning, isNotNull);
  });

  test('planche: martes del v3.1 empieza con el bloque; el tuck entra con 3 × 30 s', () async {
    await activatePlanV31(db, plan, d(10, 12));
    final view = (await plan.dayFor(d(10, 13)))!;
    final v3 = await training.blockDay(view, d(10, 13));
    final day = await training.withPlanche(view.day, d(10, 13), v3, enabled: true);
    expect(day.exercises.take(3).map((e) => e.name),
        ['Muñecas (planche)', 'Inclinación de planche', 'Flexión pseudo-planche']);
    expect(day.exercises.any((e) => e.name == 'Tuck planche'), isFalse);
    expect((await training.withPlanche(view.day, d(10, 13), v3, enabled: false)).exercises.first.name,
        'Pino pecho a la pared', reason: 'sin paralelas no cambia nada');

    await training.save(SessionDraft(date: d(10, 13), type: SessionType.trenSuperior, sets: [
      for (var i = 0; i < 3; i++) SetDraft(exercise: 'Inclinación de planche', reps: 30),
    ]));
    final thu = (await plan.dayFor(d(10, 15)))!;
    final withTuck = await training.withPlanche(thu.day, d(10, 15), await training.blockDay(thu, d(10, 15)), enabled: true);
    expect(withTuck.exercises.any((e) => e.name == 'Tuck planche'), isTrue);
  });
}
