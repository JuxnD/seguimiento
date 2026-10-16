import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/plan_v3.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/features/home/readiness_card.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 054 (§16.28.1): Hoy en el día de test. Un solo botón «Hacer el
/// test»; la sesión se habilita al terminarlo, moverlo o saltarlo. Y un test
/// vencido ofrece elegir el día. v3.1 desde el lun 12 oct 2026, sin datos
/// personales. Hoy se inyecta (como readiness_home_test); lo guardado se lee
/// de SQLite real.
class _Wed extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 10, 14);
}

void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12), wed = DateTime(2026, 10, 14);
  final wed21 = DateTime(2026, 10, 21);
  final key = TestScheduleKey(
      scheme: v31Scheme,
      blockStart: mon,
      protocolId: TestProtocolId.v31_12,
      round: 1,
      part: TestPart.piernas);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('seguimiento_054'));

  Future<T> drive<T>(WidgetTester tester, Future<T> Function() op) async {
    T? value;
    Object? error;
    var done = false;
    unawaited(op().then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    }));
    for (var i = 0; i < 200 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    if (!done) fail('operación con la base sin terminar tras 200 turnos');
    if (error != null) throw error!;
    return value as T;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  Future<AppDatabase> open(WidgetTester tester) => drive(tester, () async {
        final db = openInMemoryDatabase();
        await asExistingUser(db, since: mon);
        final plan = PlanRepository(db, ExerciseRepository(db));
        await seedIfEmpty(db, plan);
        await activatePlanV31(db, plan, mon, now: mon);
        return db;
      });

  TodayDashboard dashboard(
          {({int round, TestPart part, bool done})? test,
          bool skipped = false,
          EffectiveTest? overdue}) =>
      TodayDashboard(
        date: wed,
        weekIndex: 1,
        dayType: DayType.piernas,
        planVersion: 3,
        planSummary: null,
        mainExercises: const ['Sentadilla búlgara 2×8–12'],
        blockExercises: const [],
        targetRounds: null,
        roundsDone: null,
        sessionsToday: 0,
        streak: 3,
        macros: const Macros(),
        proteinMin: 130,
        proteinMax: 160,
        kcalTarget: 2200,
        roundsRecord: null,
        measurement: null,
        v3: v3Day(mon, wed, scheme: v31Scheme),
        fitnessTest: test,
        fitnessTestStart: test == null ? null : mon,
        testSkipped: skipped,
        overdueTest: overdue,
      );

  Future<void> mount(WidgetTester tester, AppDatabase db, TodayDashboard d) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final view = await drive(tester, () async {
      final repo = ReadinessRepository(db);
      return ReadinessView(
        advice: await repo.readinessOn(wed, testOrAttemptToday: true),
        trainedAnyway: await repo.trainedAnyway(wed),
        recoveryDone: await repo.recoveryDone(wed),
        routines: await repo.routinesOn(wed),
        mobilityStreak: await repo.mobilityStreak(wed),
      );
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localFlagsProvider
            .overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
        todayProvider.overrideWith(_Wed.new),
        dashboardProvider.overrideWith((ref) => d),
        readinessViewProvider.overrideWith((ref, _) => view),
        activeSessionProvider.overrideWith((ref) => null),
        updateCheckProvider
            .overrideWith((ref) => const UpdateCheck(currentVersion: '1.28.0')),
        morningDoneProvider.overrideWith((ref, _) => false),
      ],
      child: MaterialApp(theme: buildGymTheme(), home: const HomeScreen()),
    ));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await drive(tester, db.close);
  }

  const pending = (round: 1, part: TestPart.piernas, done: false);

  testWidgets('test pendiente: va primero y la sesión espera; saltarlo la habilita',
      (tester) => withClock(Clock.fixed(DateTime(2026, 10, 14, 8)), () async {
            final db = await open(tester);
            await mount(tester, db, dashboard(test: pending));
            expect(find.byKey(const ValueKey('hacer-el-test')), findsOneWidget);
            expect(find.byKey(const ValueKey('mover-el-test')), findsOneWidget);
            expect(find.byKey(const ValueKey('saltar-el-test')), findsOneWidget);
            expect(
                find.text(
                    'La sesión de hoy se habilita al terminar, mover o saltar el test.'),
                findsOneWidget);
            expect(find.text('Empezar piernas'), findsNothing,
                reason: 'el 15 oct se hizo la sesión creyendo que era el test');

            await tester.tap(find.byKey(const ValueKey('saltar-el-test')));
            await settle(tester);
            expect(find.text('¿Saltar el test esta vez?'), findsOneWidget);
            await tester.tap(find.text('Cancelar'));
            await settle(tester);
            expect(await drive(tester, () => ReadinessRepository(db).testSkipped(key, wed)),
                isFalse, reason: 'cancelar no guarda nada');
            await tester.tap(find.byKey(const ValueKey('saltar-el-test')));
            await settle(tester);
            await tester.tap(find.text('Saltar esta vez'));
            await settle(tester);
            expect(await drive(tester, () => ReadinessRepository(db).testSkipped(key, wed)),
                isTrue);

            // Con el salto guardado, Hoy vuelve a mostrar la sesión.
            await tester.pumpWidget(const SizedBox());
            await settle(tester);
            await mount(tester, db, dashboard(test: pending, skipped: true));
            expect(find.byKey(const ValueKey('hacer-el-test')), findsNothing);
            expect(find.text('Empezar piernas'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await close(tester, db);
          }));

  testWidgets('test hecho: revisar el test y empezar la sesión',
      (tester) => withClock(Clock.fixed(DateTime(2026, 10, 14, 18)), () async {
            final db = await open(tester);
            await mount(tester, db,
                dashboard(test: (round: 1, part: TestPart.piernas, done: true)));
            expect(find.text('Revisar o editar test'), findsOneWidget);
            expect(find.byKey(const ValueKey('empezar-tras-test')), findsOneWidget);
            expect(find.byKey(const ValueKey('hacer-el-test')), findsNothing);
            await close(tester, db);
          }));

  testWidgets('test vencido: Hoy deja elegir el día y lo mueve',
      (tester) => withClock(Clock.fixed(DateTime(2026, 10, 16, 8)), () async {
            final db = await open(tester);
            final overdue = (await drive(
                    tester,
                    () => ReadinessRepository(db).overdueTests(
                        DateTime(2026, 10, 16),
                        scheme: v31Scheme,
                        blockStart: mon,
                        protocol: TestProtocolId.v31_12)))
                .singleWhere((t) => t.part == TestPart.piernas);
            await mount(tester, db, dashboard(overdue: overdue));
            expect(
                find.text(
                    'Test 1 de piernas pendiente: era el mié 14 oct y no quedó hecho.'),
                findsOneWidget);
            await tester.tap(find.byKey(const ValueKey('test-vencido-elegir-dia')));
            await settle(tester);
            expect(find.text('¿Qué día haces el Test 1 de piernas?'), findsOneWidget);
            expect(find.widgetWithText(ChoiceChip, 'sáb 17 oct · fútbol'),
                findsNothing, reason: 'los días de fútbol no se ofrecen');
            await tester
                .tap(find.widgetWithText(ChoiceChip, 'mié 21 oct · piernas'));
            await settle(tester);
            await tester.tap(find.widgetWithText(FilledButton, 'Mover el test'));
            await settle(tester);
            expect(find.text('Test 1 de piernas: mié 21 oct'), findsOneWidget);
            expect(
                await drive(tester,
                    () => ReadinessRepository(db).currentTestDate(mon, 1, TestPart.piernas)),
                wed21);
            await close(tester, db);
          }));
}
