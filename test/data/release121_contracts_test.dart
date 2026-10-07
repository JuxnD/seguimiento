import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/guided_plan_snapshot.dart';
import 'package:seguimiento/domain/active_session.dart';
// Regressions A1-A6: six failures reproduced on afaaf86 before fixing.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import '../support/sqlite_host.dart';

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 10, 26);
}

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late LadderRepository ladders;
  late FitnessTestRepository tests;
  DateTime day(int n) => DateTime(2026, 10, n);
  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    ladders = LadderRepository(db);
    tests = FitnessTestRepository(db);
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, day(12));
  });
  tearDown(() => db.close());

  test('A1: una prueba guardada no equivale a test completo', () async {
    await tests.save(
        date: day(12),
        round: 1,
        part: TestPart.torso,
        totalSec: 60,
        results: const [TestResult(round: 1, item: 'pullup', value: 12)]);
    expect(await tests.done(1, TestPart.torso), isFalse, reason: 'Faltan once pruebas: debe poder continuarse el test');
  });

  test('A2: pruebas de piernas no sustituyen la sesión normal', () async {
    final results = <TestResult>[
      for (final item in legTests)
        for (final side in item.perSide ? ['I', 'D'] : <String?>[null])
          TestResult(round: 1, item: item.id, side: side, value: 10),
    ];
    await tests.save(date: day(14), round: 1, part: TestPart.piernas, totalSec: 600, results: results);
    final dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    expect((await dashboard.today(now: day(14))).trained, isFalse,
        reason: 'El traspaso exige la sesión de piernas después de sus pruebas');
  });

  test('A3: valores no finitos no llegan a resultados persistidos', () async {
    final value = double.parse('Infinity');
    try {
      await tests.save(
          date: day(12),
          round: 1,
          part: TestPart.torso,
          totalSec: 60,
          results: [TestResult(round: 1, item: 'pullup', value: value)]);
    } on Exception {
      // Rechazar antes de escribir satisface este contrato.
    }
    expect((await tests.all()).every((r) => r.value.isFinite), isTrue,
        reason: 'La tabla/dosis convierte valores a entero y no puede mostrar infinito');
  });

  test('A4: un solo lado no determina el lado más débil', () {
    expect(testValue(const [TestResult(round: 1, item: 'one_arm_pushup', side: 'I', value: 10)], 1, 'one_arm_pushup'),
        isNull,
        reason: 'El lado D sigue sin medir');
  });

  test('A5: snapshot persistido conserva guion/dosis/indice tras lumbar; nueva sesion baja', () async {
    await ladders.setStep(dragonFlagLadder, 2, day(12));
    final view = (await plan.dayFor(day(19)))!;
    final v3 = await training.blockDay(view, day(19));
    final original = await training.withV31Blocks(view.day, day(19), v3, planche: false);
    final dir = Directory.systemTemp.createTempSync('guided-121');
    try {
      final store = ActiveSessionStore(File('${dir.path}/session.json'));
      final started = day(19).add(const Duration(hours: 7));
      await store.save(GuidedSnapshot(
          date: '2026-10-19',
          startedAt: started,
          planDayId: view.dayId,
          phase: GuidedPhase.trabajo,
          index: 5,
          effectiveDay: freezeGuidedDay(original),
          lumbar: [dragonFlagLadder.id]));
      await ladders.lumbar(dragonFlagLadder, day(19), eventKey: started.toIso8601String());
      final reopened = await ActiveSessionStore(store.file).load() as GuidedSnapshot;
      expect(reopened.index, 5);
      expect(reopened.lumbar, [dragonFlagLadder.id]);
      final resumed = thawGuidedDay(reopened.effectiveDay!);
      expect(resumed.exercises.where((e) => e.block == ladderBlock).map((e) => e.name), ['Vela']);
      expect(freezeGuidedDay(resumed), freezeGuidedDay(original));
      final next = await training.withV31Blocks(view.day, day(19), v3, planche: false);
      expect(
          next.exercises.where((e) => e.block == ladderBlock).map((e) => e.name), ['Encogimiento inverso', hollowHold]);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('A6: la propuesta se refresca al guardar otra sesión válida', () async {
    Future<void> saveCore(int date) => training.save(SessionDraft(
          date: day(date),
          type: SessionType.trenSuperior,
          sets: [
            for (var i = 0; i < 3; i++) SetDraft(exercise: 'Encogimiento inverso', reps: 12),
            for (var i = 0; i < 3; i++) SetDraft(exercise: hollowHold, reps: 40),
          ],
        ));
    await saveCore(19);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      todayProvider.overrideWith(_FixedToday.new),
    ]);
    final subscription = container.listen(ladderAdviceProvider, (_, __) {});
    try {
      expect((await container.read(ladderAdviceProvider.future))[dragonFlagLadder.id]!.canStepUp, isFalse);
      final refreshed = Completer<void>();
      final sub2 = container.listen(ladderAdviceProvider, (_, next) {
        if (next.valueOrNull?[dragonFlagLadder.id]?.canStepUp == true && !refreshed.isCompleted) refreshed.complete();
      });
      await saveCore(26);
      await refreshed.future.timeout(const Duration(seconds: 3));
      sub2.close();
      expect((await ladders.advice(dragonFlagLadder, day(26))).canStepUp, isTrue,
          reason: 'Control positivo de datos: ya cumple las dos sesiones');
      expect((await container.read(ladderAdviceProvider.future))[dragonFlagLadder.id]!.canStepUp, isTrue,
          reason: 'Hoy/Cuerpo deben mostrar el nuevo consejo sin reiniciar');
    } finally {
      subscription.close();
      container.dispose();
    }
  });

  List<TestResult> complete(int round, TestPart part) => [
        for (final t in itemsFor(part))
          for (final side in t.perSide ? ['I', 'D'] : <String?>[null])
            TestResult(round: round, item: t.id, value: 0, side: side),
      ];

  test('Test completo cero sustituye tiron lunes, nunca Cindy viernes', () async {
    await tests.save(
        date: day(12), round: 1, part: TestPart.torso, totalSec: 3600, results: complete(1, TestPart.torso));
    final dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    expect(await tests.status(1, TestPart.torso), TestStatus.complete);
    expect((await dashboard.today(now: day(12))).trained, isTrue);
    await tests.save(
        date: DateTime(2026, 12, 11),
        round: 3,
        part: TestPart.torso,
        totalSec: 3600,
        results: complete(3, TestPart.torso));
    expect((await dashboard.today(now: DateTime(2026, 12, 11))).trained, isFalse);
    final sessions = await db.select(db.sessions).get();
    expect(sessions.every((s) => s.totalSec == 0), isTrue, reason: 'introducir datos no mide esfuerzo');
  });

  for (final testFirst in [true, false]) {
    test('piernas test y entrenamiento en ambos ordenes: testFirst=$testFirst', () async {
      final dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
      Future<void> saveTest() => tests.save(
          date: day(14), round: 1, part: TestPart.piernas, totalSec: 0, results: complete(1, TestPart.piernas));
      Future<void> saveTraining() => training.save(SessionDraft(date: day(14), type: SessionType.piernas));
      if (testFirst) {
        await saveTest();
        expect((await dashboard.today(now: day(14))).trained, isFalse);
        await saveTraining();
      } else {
        await saveTraining();
        await saveTest();
      }
      final after = await dashboard.today(now: day(14));
      expect(after.trained, isTrue);
      expect(after.sessionsToday, 1);
      expect(await tests.dateFor(1, TestPart.piernas), day(14));
      expect(await tests.done(1, TestPart.piernas), isTrue);
    });
  }

  for (final value in [double.nan, double.infinity, double.negativeInfinity, -1.0, 1.5]) {
    test('rechazo atomico reps $value conserva resultado anterior', () async {
      await tests.save(
          date: day(12),
          round: 1,
          part: TestPart.torso,
          totalSec: 0,
          results: const [TestResult(round: 1, item: 'pullup', value: 12)]);
      expect(
          () => tests.save(date: day(12), round: 1, part: TestPart.torso, totalSec: 0, results: [
                const TestResult(round: 1, item: 'dips', value: 5),
                TestResult(round: 1, item: 'pullup', value: value)
              ]),
          throwsFormatException);
      expect((await tests.all()).single.value, 12);
      expect(await db.select(db.sessions).get(), hasLength(1));
    });
  }
  test('rechazo item/lado/ronda/duplicado/vacio; segundos decimales validos', () async {
    for (final rows in [
      <TestResult>[],
      [const TestResult(round: 1, item: 'unknown', value: 2)],
      [const TestResult(round: 1, item: 'pullup', side: 'I', value: 2)],
      [const TestResult(round: 1, item: 'one_arm_pushup', value: 2)],
      [const TestResult(round: 2, item: 'pullup', value: 2)],
      [const TestResult(round: 1, item: 'pullup', value: 2), const TestResult(round: 1, item: 'pullup', value: 3)],
      [const TestResult(round: 1, item: 'broad_jump', value: 200)],
    ]) {
      expect(() => tests.save(date: day(12), round: 1, part: TestPart.torso, totalSec: 0, results: rows),
          throwsFormatException);
    }
    expect(await db.select(db.sessions).get(), isEmpty);
    await tests.save(
        date: day(12),
        round: 1,
        part: TestPart.torso,
        totalSec: 0,
        results: const [TestResult(round: 1, item: 'hollow_hold', value: 12.5)]);
    expect(testValue(await tests.all(), 1, 'hollow_hold'), 12.5);
    expect(formatTestValue(torsoTests.first, double.infinity), 'Inválido');
  });

  test('reset mismo peldaño excluye guia vieja guardada despues y sesiones de antes del cambio', () async {
    final view = (await plan.dayFor(day(19)))!;
    final old = await training.withV31Blocks(view.day, day(19), await training.blockDay(view, day(19)), planche: false);
    final sets = [
      for (var i = 0; i < 3; i++) SetDraft(exercise: 'Encogimiento inverso', reps: 12),
      for (var i = 0; i < 3; i++) SetDraft(exercise: hollowHold, reps: 40)
    ];
    await training.save(SessionDraft(date: day(19), type: SessionType.trenSuperior, sets: sets));
    await ladders.setStep(dragonFlagLadder, 1, day(19));
    await training.save(SessionDraft(
        date: day(19), type: SessionType.trenSuperior, sets: sets, coreEpochs: jsonEncode(old.coreEpochs)));
    expect(await ladders.sessions(await ladders.state(dragonFlagLadder)), isEmpty);
    final current =
        await training.withV31Blocks(view.day, day(19), await training.blockDay(view, day(19)), planche: false);
    await training.save(SessionDraft(
        date: day(19), type: SessionType.trenSuperior, sets: sets, coreEpochs: jsonEncode(current.coreEpochs)));
    expect(await ladders.sessions(await ladders.state(dragonFlagLadder)), hasLength(1));
    expect((await ladders.advice(dragonFlagLadder, day(19))).canStepUp, isFalse);
  });

  test('lumbar durable idempotente con mismo evento y separado por sesion', () async {
    await ladders.setStep(dragonFlagLadder, 3, day(12));
    expect(await ladders.lumbar(dragonFlagLadder, day(19), eventKey: 'session-a'), 2);
    expect(await LadderRepository(db).lumbar(dragonFlagLadder, day(19), eventKey: 'session-a'), 2);
    expect((await ladders.state(dragonFlagLadder)).step, 2);
    expect(await ladders.lumbarFor('session-a'), [dragonFlagLadder.id]);
    expect(await ladders.lumbar(dragonFlagLadder, day(19), eventKey: 'session-b'), 1);
  });
}
