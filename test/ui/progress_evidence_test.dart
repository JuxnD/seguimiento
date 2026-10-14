import 'dart:io';
import 'dart:async';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/features/body/test_results_screen.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart';
import 'package:seguimiento/features/training/test_mode_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import '../support/sqlite_host.dart';

class _Wakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late Directory dir;
  setUp(() {
    db = openInMemoryDatabase();
    dir = Directory.systemTemp.createTempSync('evidence008');
    wakelock.wakelockPlusPlatformInstance = _Wakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  Future<T> io<T>(WidgetTester t, Future<T> Function() action) async {
    bool done = false;
    final task = action();
    task.then((_) => done = true, onError: (Object _, StackTrace __) {
      done = true;
    }).ignore();
    for (var i = 0; i < 200 && !done; i++) {
      await t.pump(const Duration(milliseconds: 5));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)));
    }
    if (!done) throw TimeoutException('QA evidence IO did not complete');
    return task;
  }

  Future<void> mount(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(1500, 6500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          activeSessionStoreProvider.overrideWithValue(
              ActiveSessionStore(File('${dir.path}/session.json'))),
          latestWeightProvider.overrideWithValue(70),
          profileProvider.overrideWith((ref) => const Stream.empty())
        ],
        child: MaterialApp(
            key: UniqueKey(),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => page)),
                        child: const Text('abrir')))))));
    await t.tap(find.text('abrir'));
    await t.pump(const Duration(milliseconds: 400));
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    await io(t, () => db.close());
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {/* temporary QA only */}
  }

  testWidgets(
      'SQLite→Cuerpo: T3 parcial visible conserva dosis T2, dudas no dan dosis',
      (t) async {
    try {
      final repo = FitnessTestRepository(db);
      await io(t, () async {
        await repo.save(
            date: DateTime(2026, 10, 5),
            round: 2,
            part: TestPart.piernas,
            totalSec: 0,
            conditions: const {
              'bulgarian_split_squat': {'variant': 'sin peso'}
            },
            results: const [
              TestResult(
                  round: 2,
                  item: 'bulgarian_split_squat',
                  side: 'I',
                  value: 20),
              TestResult(
                  round: 2, item: 'bulgarian_split_squat', side: 'D', value: 22)
            ]);
        await repo.save(
            date: DateTime(2026, 10, 7),
            round: 3,
            part: TestPart.piernas,
            conditions: const {
              'bulgarian_split_squat': {'variant': 'sin peso'}
            },
            totalSec: 0,
            results: const [
              TestResult(
                  round: 3, item: 'bulgarian_split_squat', side: 'I', value: 25)
            ]);
        await repo.save(
            date: DateTime(2026, 10, 6),
            round: 1,
            part: TestPart.torso,
            totalSec: 0,
            results: const [
              TestResult(round: 1, item: 'pullup', value: 20, clean: false)
            ]);
      });
      await mount(t, const TestResultsScreen());
      final partial = find.textContaining('Búlgara sin peso (I): 25.0');
      // Observe actual async history rendering; do not infer completion from a delay.
      final historyDeadline = DateTime.now().add(const Duration(seconds: 2));
      while (partial.evaluate().isEmpty &&
          DateTime.now().isBefore(historyDeadline)) {
        await t.pump(const Duration(milliseconds: 10));
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      expect(partial, findsOneWidget,
          reason:
              'Actual rendered text: ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}');
      expect(find.textContaining('Sin dosis ni comparación'), findsWidgets);
      expect(
          find.textContaining(
              '14–15 reps por lado (intento1, 2026-10-05, v31_12; condiciones conocidas)'),
          findsOneWidget);
      expect(find.textContaining('Dominadas pronas estrictas: Tope'),
          findsNothing);
    } finally {
      await close(t);
    }
  });
  testWidgets('SQLite→guía: serie manual con fallo no sugiere subir mochila',
      (t) async {
    try {
      final exercises = ExerciseRepository(db);
      final training = TrainingRepository(db, exercises);
      await io(t, () async {
        await training.save(SessionDraft(
            date: DateTime(2026, 10, 5),
            type: SessionType.bloques,
            sets: [
              SetDraft(
                  exercise: 'Flexiones',
                  reps: 15,
                  split: true,
                  splitDetail: '12+3',
                  toFailure: true)
            ]));
        final id = await exercises.idOf('Flexiones');
        await (db.update(db.exercises)..where((x) => x.id.equals(id!)))
            .write(const ExercisesCompanion(tracksLoad: Value(true)));
      });
      await mount(
          t,
          GuidedSessionScreen(
              date: DateTime(2026, 10, 12),
              day: PlanDayDraft(weekday: 1, type: DayType.bloques, exercises: [
                PlanExerciseDraft(
                    name: 'Flexiones', sets: 1, repsMin: 10, repsMax: 15)
              ])));
      final start = find.text('Empezar bloques');
      expect(start, findsOneWidget);
      await t.tap(start);
      await t.pump(const Duration(milliseconds: 400));
      if (find.text('Empezar igual').evaluate().isNotEmpty) {
        await t.tap(find.text('Empezar igual'));
        await t.pump(const Duration(milliseconds: 400));
      }
      expect(find.textContaining('+2–5 kg'), findsNothing);
      expect(find.text('Hecho'), findsOneWidget);
    } finally {
      await close(t);
    }
  });
  testWidgets('nuevo test usa hoy real; editar conserva fecha original',
      (t) async {
    await withClock(Clock.fixed(DateTime(2026, 10, 9)), () async {
      try {
        await mount(
            t,
            TestModeScreen(
                date: DateTime(2026, 12, 11), round: 1, part: TestPart.torso));
        expect(find.text('Fecha del intento: 2026-10-09'), findsOneWidget);
        expect(find.text('Confirmar o cambiar fecha'), findsOneWidget);
        await t.enterText(
            find.byKey(const ValueKey('test-value-pullup-')), '3');
        await t.pump();
        await t.tap(find.text('Guardar test'));
        await t.pump();
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)));
        await t.pump(const Duration(milliseconds: 400));
        final rows = await io(t, () => FitnessTestRepository(db).all());
        expect(rows.single.date, DateTime(2026, 10, 9));
        await mount(
            t,
            TestModeScreen(
                date: DateTime(2026, 12, 11), round: 1, part: TestPart.torso));
        expect(find.text('Fecha del intento: 2026-10-09 (conservada)'),
            findsOneWidget);
        expect(find.text('Confirmar o cambiar fecha'), findsNothing);
      } finally {
        await close(t);
      }
    });
  });
  for (final rawDate in ['desconocida', '2026-02-30']) {
    testWidgets(
        'fecha legacy $rawDate inválida no se reemplaza por hoy al editar',
        (t) async {
      try {
        await io(
            t,
            () => db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
                date: rawDate, round: 1, item: 'pullup', value: 3)));
        await mount(
            t,
            TestModeScreen(
                date: DateTime(2026, 12, 11), round: 1, part: TestPart.torso));
        expect(find.textContaining('Fecha del intento sin confirmar'),
            findsOneWidget);
        final saveButton = find.ancestor(
            of: find.text('Guardar test'),
            matching: find.byWidgetPredicate((w) => w is FilledButton));
        expect(t.widget<FilledButton>(saveButton.first).onPressed, isNull);
        expect(
            (await io(t, () => db.select(db.fitnessTests).get())).single.date,
            rawDate);
      } finally {
        await close(t);
      }
    });
  }
  for (final dates in [
    ('2026-10-05', 'desconocida'),
    ('2026-10-05', '2026-02-30'),
    ('2026-10-05', '2026-10-07'),
    ('2026-10-05', '2027-01-05'),
    ('2027-01-05', '2027-01-05'),
  ]) {
    testWidgets(
        'parte con fechas ${dates.$1}/${dates.$2} exige confirmar todas antes de guardar',
        (t) async {
      await withClock(Clock.fixed(DateTime(2026, 10, 9)), () async {
        try {
          await io(t, () async {
            await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
                date: dates.$1, round: 1, item: 'pullup', value: 3));
            await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
                date: dates.$2, round: 1, item: 'dips', value: 5));
          });
          final originals = await io(t, () => db.select(db.fitnessTests).get());
          await mount(
              t,
              TestModeScreen(
                  date: DateTime(2026, 12, 11),
                  round: 1,
                  part: TestPart.torso));
          expect(find.textContaining('Fecha del intento sin confirmar'),
              findsOneWidget);
          expect(find.textContaining('(conservada)'), findsNothing);
          final saveButton = find.ancestor(
              of: find.text('Guardar test'),
              matching: find.byWidgetPredicate((w) => w is FilledButton));
          expect(t.widget<FilledButton>(saveButton.first).onPressed, isNull);
          await t.enterText(
              find.byKey(const ValueKey('test-value-pullup-')), '4');
          await t.pump();
          expect(t.widget<FilledButton>(saveButton.first).onPressed, isNull);
          expect(
              await io(t, () => db.select(db.fitnessTests).get()), originals);
          await t.tap(find.text('Confirmar o cambiar fecha'));
          await t.pumpAndSettle();
          await t.tap(find.text('Cancel'));
          await t.pumpAndSettle();
          expect(t.widget<FilledButton>(saveButton.first).onPressed, isNull);
          expect(
              await io(t, () => db.select(db.fitnessTests).get()), originals);
          await t.tap(find.text('Confirmar o cambiar fecha'));
          await t.pumpAndSettle();
          await t.tap(find.text('OK'));
          await t.pumpAndSettle();
          expect(
              find.text(
                  'Fecha del intento: 2026-10-09 (confirmada para esta parte)'),
              findsOneWidget);
          expect(t.widget<FilledButton>(saveButton.first).onPressed, isNotNull);
          expect(await io(t, () => db.select(db.fitnessTests).get()), originals,
              reason: 'Elegir fecha sólo cambia el borrador, no SQLite');
          await t.tap(find.text('Guardar test'));
          await t.pump();
          await io(
              t, () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 400));
          final accepted = await io(t, () => db.select(db.fitnessTests).get());
          expect(
              accepted
                  .where((r) => originals.any((o) => o.id == r.id))
                  .toList(),
              originals,
              reason:
                  'Confirmed new attempt preserves every legacy row and date.');
          final attempts =
              await io(t, () => db.select(db.fitnessTestAttempts).get());
          expect(attempts, hasLength(1));
          final attempt = attempts.single;
          expect((attempt.date, attempt.protocolId, attempt.part),
              ('2026-10-09', 'v31_12', 'torso'));
          final fresh =
              accepted.where((r) => r.attemptId == attempt.id).toList();
          expect(fresh, hasLength(2));
          expect(accepted, hasLength(originals.length + 2));
          expect(fresh.map((r) => r.date).toSet(), {'2026-10-09'});
          expect(fresh.firstWhere((r) => r.item == 'pullup').value, 4);
          expect(fresh.firstWhere((r) => r.item == 'dips').value, 5);
        } finally {
          await close(t);
        }
      });
    });
  }
  for (final modes in [
    (null, 'tecnica', false),
    ('tecnica', null, false),
    (null, null, true)
  ]) {
    testWidgets(
        'modo registrado ${modes.$1} → guía ${modes.$2}: subida ${modes.$3}',
        (t) async {
      try {
        final exercises = ExerciseRepository(db);
        final training = TrainingRepository(db, exercises);
        await io(t, () async {
          await training.save(SessionDraft(
              date: DateTime(2026, 10, 5),
              type: SessionType.bloques,
              mode: modes.$1,
              sets: [
                SetDraft(
                    exercise: 'Flexiones',
                    reps: 15,
                    rir: modes.$1 == 'tecnica' ? 4 : 2,
                    loadKg: 5)
              ]));
          final id = await exercises.idOf('Flexiones');
          await (db.update(db.exercises)..where((x) => x.id.equals(id!)))
              .write(const ExercisesCompanion(tracksLoad: Value(true)));
        });
        final original = await io(t, () => db.select(db.sessions).get());
        await mount(
            t,
            GuidedSessionScreen(
                date: DateTime(2026, 10, 12),
                mode: modes.$2,
                day: PlanDayDraft(
                    weekday: 1,
                    type: DayType.bloques,
                    exercises: [
                      PlanExerciseDraft(
                          name: 'Flexiones', sets: 1, repsMin: 10, repsMax: 15)
                    ])));
        await t.tap(find.text('Empezar bloques'));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Calentamiento a medias'), findsOneWidget);
        await t.tap(find.text('Empezar igual'));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Hecho'), findsOneWidget);
        expect(find.textContaining('+2–5 kg'),
            modes.$3 ? findsOneWidget : findsNothing);
        expect(find.text('Carga 5 kg'), findsOneWidget,
            reason: 'Carga observada no se elimina');
        expect(await io(t, () => db.select(db.sessions).get()), original,
            reason: 'No reescribir historia por modo');
      } finally {
        await close(t);
      }
    });
  }
}
