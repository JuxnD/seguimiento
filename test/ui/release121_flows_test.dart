import 'dart:async';
import 'dart:io';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/guided_plan_snapshot.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/features/body/ladders_screen.dart';
import 'package:seguimiento/features/body/test_results_screen.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart';
import 'package:seguimiento/features/training/test_mode_screen.dart';
import 'package:seguimiento/features/training/training_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import '../support/sqlite_host.dart';

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

class _Notifications extends NotificationService {
  _Notifications() : super(FlutterLocalNotificationsPlugin());
  @override
  Future<void> init() async {}
  @override
  Future<bool> scheduleRestEnd({required Duration inSeconds, required String nextLabel}) async => true;
  @override
  Future<void> cancelRestEnd() async {}
}

class _Today extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 10, 26);
}

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late Directory dir;
  late PlanRepository plan;
  late TrainingRepository training;
  late ActiveSessionStore store;
  bool closed = false;
  WidgetTester? currentTester;
  setUp(() async {
    closed = false;
    currentTester = null;
    db = openInMemoryDatabase();
    dir = Directory.systemTemp.createTempSync('ui121');
    store = ActiveSessionStore(File('${dir.path}/session.json'));
    plan = PlanRepository(db, ExerciseRepository(db));
    training = TrainingRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, DateTime(2026, 10, 12));
    wakelock.wakelockPlusPlatformInstance = _NoWakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  // Flutter congela timers; Drift y archivos necesitan progresar ambos
  // event loops. Nunca esperar SQLite mientras su zona fake queda detenida.
  Future<T> io<T>(WidgetTester t, Future<T> Function() action) async {
    bool done = false;
    final task = action();
    task.then((_) => done = true, onError: (Object _, StackTrace __) {
      done = true;
    }).ignore();
    for (var i = 0; i < 200 && !done; i++) {
      await t.pump(const Duration(milliseconds: 5));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    }
    if (!done) throw TimeoutException('IO QA no completó tras 200 ciclos');
    return task;
  }

  Future<void> cleanup(WidgetTester t) async {
    if (closed) return;
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 1));
    await t.pump(const Duration(milliseconds: 500));
    await io(t, () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 1));
    await io(t, () => db.close());
    closed = true;
    await t.pump(const Duration(milliseconds: 1));
  }

  tearDown(() async {
    if (!closed) {
      if (currentTester != null) {
        await cleanup(currentTester!);
      } else {
        await db.close();
      }
    }
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {/* Windows conserva el handle hasta que salga flutter_tester. Sólo QA temporal. */}
  });
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await io(t, () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 400));
    await io(t, () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }

  Future<void> pump(WidgetTester t, Widget Function(BuildContext, WidgetRef) child) async {
    currentTester = t;
    t.view.physicalSize = const Size(1500, 6500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWithValue(db),
      todayProvider.overrideWith(_Today.new),
      activeSessionStoreProvider.overrideWithValue(store),
      localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
      notificationServiceProvider.overrideWithValue(_Notifications()),
      latestWeightProvider.overrideWithValue(70),
      profileProvider.overrideWith((ref) => const Stream.empty()),
    ], child: MaterialApp(home: Consumer(builder: (c, ref, _) => child(c, ref)))));
    await settle(t);
  }

  Future<void> openTest(WidgetTester t) async {
    await pump(
        t,
        (c, ref) => Scaffold(
            body: TextButton(
                onPressed: () => Navigator.push(
                    c,
                    MaterialPageRoute(
                        builder: (_) => TestModeScreen(date: DateTime(2026, 10, 12), round: 1, part: TestPart.torso))),
                child: const Text('abrir'))));
    await t.tap(find.text('abrir'));
    await settle(t);
  }

  Finder field(String item, [String side = '']) => find.byKey(ValueKey('test-value-$item-$side'));
  testWidgets('reentrada precarga ambos lados y editar otro campo conserva calidad I/D y fecha', (t) async {
    try {
      final repo = FitnessTestRepository(db);
      await io(
          t,
          () => repo.save(date: DateTime(2026, 10, 12), round: 1, part: TestPart.torso, totalSec: 0, results: const [
                TestResult(round: 1, item: 'one_arm_pushup', side: 'I', value: 5, clean: true),
                TestResult(round: 1, item: 'one_arm_pushup', side: 'D', value: 4, clean: false),
              ]));
      await pump(t, (c, ref) => const TestResultsScreen());
      await t.tap(find.text('T1 torso'));
      await settle(t);
      expect(t.widget<TextField>(field('one_arm_pushup', 'I')).controller!.text, '5.0');
      expect(t.widget<TextField>(field('one_arm_pushup', 'D')).controller!.text, '4.0');
      await t.enterText(field('dips'), '7');
      await t.pump();
      await t.tap(find.text('Guardar test'));
      await settle(t);
      final rows = (await io(t, () => repo.all()));
      expect(rows.firstWhere((r) => r.side == 'I').clean, isTrue);
      expect(rows.firstWhere((r) => r.side == 'D').clean, isFalse);
      expect(rows.firstWhere((r) => r.item == 'dips').value, 7);
      expect(await io(t, () => repo.done(1, TestPart.torso)), isFalse);
      expect((await io(t, () => db.select(db.sessions).get())).single.date, '2026-10-12');
    } finally {
      await cleanup(t);
    }
  });
  testWidgets('validacion muestra error sin guardar ni perder texto; coma segundos guarda parcial', (t) async {
    try {
      await openTest(t);
      await t.enterText(field('pullup'), '1.5');
      await t.pump();
      await t.tap(find.text('Guardar test'));
      await settle(t);
      expect(find.text('Las repeticiones deben ser enteras'), findsOneWidget);
      expect(t.widget<TextField>(field('pullup')).controller!.text, '1.5');
      expect(await io(t, () => FitnessTestRepository(db).all()), isEmpty);
      await t.enterText(field('pullup'), '0');
      await t.enterText(field('hollow_hold'), '12,5');
      await t.pump();
      await t.tap(find.text('Guardar test'));
      await settle(t);
      final rows = (await io(t, () => FitnessTestRepository(db).all()));
      expect(testValue(rows, 1, 'pullup'), 0);
      expect(testValue(rows, 1, 'hollow_hold'), 12.5);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets('caller resume usa snapshot efectivo tras lumbar y recupera evento de BD tras crash', (t) async {
    try {
      final date = DateTime(2026, 10, 19);
      final ladder = LadderRepository(db);
      await io(t, () => ladder.setStep(dragonFlagLadder, 2, DateTime(2026, 10, 12)));
      final view = (await io(t, () => plan.dayFor(date)))!;
      final day = (await io(
          t, () async => training.withV31Blocks(view.day, date, await training.blockDay(view, date), planche: false)));
      final script = buildScript(scriptDayFrom(day));
      final index = script.indexWhere((s) => s is WorkStep && s.exercise == 'Vela');
      final start = clock.now().subtract(const Duration(minutes: 1));
      final snapshot = GuidedSnapshot(
          date: '2026-10-19',
          startedAt: start,
          planDayId: view.dayId,
          phase: GuidedPhase.trabajo,
          index: index,
          effectiveDay: freezeGuidedDay(day));
      await io(t, () => store.save(snapshot));
      await io(t, () => ladder.lumbar(dragonFlagLadder, date, eventKey: 'guided:${start.toIso8601String()}'));
      // Deliberadamente sin lumbar en JSON: crash entre commit de BD y save.
      final loaded = (await io(t, () => ActiveSessionStore(store.file).load()))!;
      await pump(
          t,
          (c, ref) => Scaffold(
              body: TextButton(onPressed: () => resumeActiveSession(c, ref, loaded), child: const Text('retomar'))));
      await t.tap(find.text('retomar'));
      await settle(t);
      await settle(t);
      expect(find.text('Vela'), findsWidgets);
      await io(t, () async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Hecho'));
      await settle(t);
      expect(find.text('Molestia lumbar anotada'), findsOneWidget);
      final persisted = await io(t, () => store.load()) as GuidedSnapshot;
      expect(persisted.lumbar, [dragonFlagLadder.id]);
      expect((await io(t, () => ladder.state(dragonFlagLadder))).step, 1);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets('consumer advice cambia tras guardar editar y borrar sin reiniciar', (t) async {
    try {
      SessionDraft core(int day, int reps) =>
          SessionDraft(date: DateTime(2026, 10, day), type: SessionType.trenSuperior, sets: [
            for (var i = 0; i < 3; i++) SetDraft(exercise: 'Encogimiento inverso', reps: reps),
            for (var i = 0; i < 3; i++) SetDraft(exercise: hollowHold, reps: 40),
          ]);
      await io(t, () => training.save(core(19, 12)));
      await pump(t, (c, ref) => const LaddersScreen());
      expect(find.text('Subir a Vela'), findsNothing);
      final second = core(26, 12);
      await io(t, () => training.save(second));
      await settle(t);
      expect(find.text('Subir a Vela'), findsOneWidget);
      second.sets.first.reps = 1;
      await io(t, () => training.save(second));
      await settle(t);
      expect(find.text('Subir a Vela'), findsNothing);
      second.sets.first.reps = 12;
      await io(t, () => training.save(second));
      await settle(t);
      expect(find.text('Subir a Vela'), findsOneWidget);
      await io(t, () => training.delete(second.id!));
      await settle(t);
      expect(find.text('Subir a Vela'), findsNothing);
    } finally {
      await cleanup(t);
    }
  });

  testWidgets('legado1.20 conserva secuencia e indice sin agregar escalera; guion malformado se descarta', (t) async {
    try {
      final date = DateTime(2026, 10, 19);
      final view = (await io(t, () => plan.dayFor(date)))!;
      final v3 = await io(t, () => training.blockDay(view, date));
      final old = await io(t, () => training.withPlanche(view.day, date, v3, enabled: false));
      final script = buildScript(scriptDayFrom(old));
      final index = script.lastIndexWhere((s) => s is WorkStep);
      final expected = script[index] as WorkStep;
      final legacy = GuidedSnapshot(
          date: '2026-10-19', startedAt: clock.now(), planDayId: view.dayId, phase: GuidedPhase.trabajo, index: index);
      final json = legacy.toJson()..remove('effectiveDay');
      final loaded = ActiveSession.fromJson(json)!;
      await pump(
          t,
          (c, ref) => Scaffold(
              body: TextButton(onPressed: () => resumeActiveSession(c, ref, loaded), child: const Text('legado'))));
      await t.tap(find.text('legado'));
      await settle(t);
      await settle(t);
      expect(find.text(expected.exercise), findsWidgets);
      final current = await io(t, () => store.load()) as GuidedSnapshot;
      expect(current.index, index);
      expect(freezeGuidedDay(thawGuidedDay(current.effectiveDay!)), freezeGuidedDay(old));
    } finally {
      await cleanup(t);
    }
  });
  testWidgets('snapshot con mapa efectivo malformado no tumba la pantalla', (t) async {
    try {
      final view = (await io(t, () => plan.dayFor(DateTime(2026, 10, 19))))!;
      final snapshot = GuidedSnapshot(
          date: '2026-10-19',
          startedAt: clock.now(),
          planDayId: view.dayId,
          phase: GuidedPhase.trabajo,
          index: 0,
          effectiveDay: const {'weekday': 1, 'type': 'nonsense'});
      await io(t, () => store.save(snapshot));
      await pump(
          t,
          (c, ref) => Scaffold(
              body: TextButton(onPressed: () => resumeActiveSession(c, ref, snapshot), child: const Text('corrupto'))));
      await t.tap(find.text('corrupto'));
      await settle(t);
      await settle(t);
      expect(find.text('La sesión guardada tiene un guion inválido; se descarta para poder empezar otra.'),
          findsOneWidget);
      expect(await io(t, () => store.load()), isNull);
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
}
