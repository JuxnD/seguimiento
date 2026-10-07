import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/corrections_29sep.dart' show CorrectionState;
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/history_import.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';

import '../support/sqlite_host.dart';

/// Escaleras de core (§19.10), test de condición (§19.11) y el martes del
/// 6 oct sobre la base.
void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late LadderRepository ladders;
  late DashboardRepository dashboard;

  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    ladders = LadderRepository(db);
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, d(10, 12));
  });

  tearDown(() => db.close());

  Future<PlanDayDraft> dayOf(DateTime date) async {
    final view = (await plan.dayFor(date))!;
    return training.withV31Blocks(view.day, date, await training.blockDay(view, date), planche: false);
  }

  Future<void> coreSession(DateTime date, {int reps = 12, int hollow = 40}) => training.save(SessionDraft(
        date: date,
        type: SessionType.trenSuperior,
        sets: [
          for (var i = 0; i < 3; i++) SetDraft(exercise: 'Encogimiento inverso', reps: reps),
          for (var i = 0; i < 3; i++) SetDraft(exercise: hollowHold, reps: hollow),
        ],
      ));

  test('el lunes trae el peldaño del dragon flag y el jueves el del V-up, antes de lo opcional', () async {
    final monday = (await dayOf(d(10, 19))).exercises;
    final ladder = monday.where((e) => e.block == ladderBlock).map((e) => e.name);
    expect(ladder, ['Encogimiento inverso', hollowHold]);
    expect(monday.firstWhere((e) => e.name == 'Encogimiento inverso').repsMax, 12);

    final thursday = (await dayOf(d(10, 15))).exercises.map((e) => e.name).toList();
    expect(thursday.indexOf('Tuck-up'), lessThan(thursday.indexOf('Progresión de pistol')));
    expect((await dayOf(d(10, 13))).exercises.any((e) => e.block == ladderBlock), isFalse,
        reason: 'el martes no lleva escalera');
  });

  test('peldaño 1 desde el lunes del v3.1; sube tras 2 sesiones limpias y 2 semanas', () async {
    final s = await ladders.state(dragonFlagLadder);
    expect((s.step, s.since), (1, d(10, 12)));
    await coreSession(d(10, 19));
    await coreSession(d(10, 26));
    expect((await ladders.advice(dragonFlagLadder, d(10, 26))).canStepUp, isTrue);
    await ladders.stepUp(dragonFlagLadder, d(10, 26));
    expect((await dayOf(d(11, 2))).exercises.where((e) => e.block == ladderBlock).map((e) => e.name), ['Vela']);
  });

  test('molestia lumbar: baja un peldaño y esa sesión no cuenta como limpia', () async {
    await ladders.setStep(dragonFlagLadder, 3, d(10, 12));
    expect(await ladders.lumbar(dragonFlagLadder, d(10, 19)), 2);
    expect(await ladders.lumbar(vUpLadder, d(10, 15)), 1, reason: 'en el peldaño 1 se queda');
    await ladders.setStep(dragonFlagLadder, 1, d(10, 12));
    await ladders.lumbar(dragonFlagLadder, d(10, 19));
    await coreSession(d(10, 19));
    expect(await ladders.sessions(await ladders.state(dragonFlagLadder)), isEmpty);
  });

  test('día de test: el lunes de la semana 1 en Hoy, y al guardarlo cuenta como entrenado', () async {
    final before = await dashboard.today(now: d(10, 12));
    expect(before.fitnessTest, (round: 1, part: TestPart.torso, done: false));
    expect(before.trained, isFalse);

    await FitnessTestRepository(db).save(
      date: d(10, 12),
      round: 1,
      part: TestPart.torso,
      totalSec: 3600,
      results: const [
        TestResult(round: 1, item: 'pullup', value: 12),
        TestResult(round: 1, item: 'one_arm_pushup', side: 'I', value: 5),
        TestResult(round: 1, item: 'one_arm_pushup', side: 'D', value: 4, clean: false),
      ],
    );
    final after = await dashboard.today(now: d(10, 12));
    expect(after.fitnessTest?.done, isTrue);
    expect(after.trained, isTrue);
    expect((await dashboard.today(now: d(10, 14))).fitnessTest, (round: 1, part: TestPart.piernas, done: false));

    final all = await FitnessTestRepository(db).all();
    expect(all, hasLength(3));
    expect(testValue(all, 1, 'one_arm_pushup'), 4);
  });

  test('el informe no toma el Tabata por aguantes; sí la vela y el hollow', () async {
    final input = await ReportRepository(db, NutritionRepository(db)).load(d(10, 12), d(10, 18));
    expect(input.holdExercises, isNot(contains('Flexiones')));
    expect(input.holdExercises, isNot(contains('Sentadillas')));
    expect(input.holdExercises, containsAll(['Vela', hollowHold, 'Pino pecho a la pared']));
    expect(input.perSideExercises, contains('V-up a una pierna'));
  });

  test('martes del 6 oct: el v3.1 nuevo ya lo trae; uno activado antes se corrige', () async {
    final tuesday = (await dayOf(d(10, 13))).exercises.map((e) => e.name);
    expect(tuesday, containsAll(['Flexión a una mano', 'Flexiones diamante']));
    expect(tuesday, isNot(contains('Flexión arquero')));

    final fix = corrections7Oct.firstWhere((c) => c.id == 'v31-martes-6oct');
    expect(await fix.check(db), CorrectionState.done);

    // Una versión del v3.1 guardada con el martes viejo.
    final old = planV31(d(10, 12));
    old.days[DateTime.tuesday - 1].exercises
      ..removeWhere((e) => e.name == 'Flexión a una mano' || e.name == 'Flexiones diamante')
      ..insert(1, PlanExerciseDraft(name: 'Flexión arquero', sets: 3, repsMin: 4, repsMax: 6, perSide: true));
    await plan.saveAsNewVersion(old);
    expect(await fix.check(db), CorrectionState.pending);

    await fix.apply(db);
    expect(await fix.check(db), CorrectionState.done);
    final fixed = (await plan.dayFor(d(10, 13)))!.day.exercises.map((e) => e.name);
    expect(fixed, contains('Flexión a una mano'));
    expect(fixed, isNot(contains('Flexión arquero')));
  });
}
