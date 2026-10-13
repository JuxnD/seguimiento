import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/leg_chain.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/readiness.dart';
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/features/home/readiness_card.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/sqlite_host.dart';

/// Plan 039 en Hoy: la tarjeta dice por qué, con días o valor y fecha; con la
/// mañana verde sólo queda una nota. Fechas ficticias.
class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2030, 3, 6);
}

void main() {
  setUpAll(useHostSqlite);
  final wed = DateTime(2030, 3, 6);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('seguimiento_039_card'));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  Future<void> close(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    var closed = false;
    final closing = db.close().then((_) => closed = true);
    for (var i = 0; i < 20 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(closed, isTrue);
    await closing;
  }

  Future<AppDatabase> mount(
    WidgetTester tester,
    PlanBAdvice advice, {
    Size size = const Size(420, 2400),
    double textScale = 1,
    ReadinessView? readiness,
    ({int round, TestPart part, bool done})? test,
  }) async {
    final db = openInMemoryDatabase();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
        todayProvider.overrideWith(_FixedToday.new),
        dashboardProvider.overrideWith((ref) => TodayDashboard(
              date: wed,
              weekIndex: 1,
              dayType: DayType.piernas,
              planVersion: 3,
              planSummary: null,
              mainExercises: const ['Sentadilla búlgara 3×8'],
              blockExercises: const [],
              targetRounds: null,
              roundsDone: null,
              sessionsToday: 0,
              streak: 3,
              macros: const Macros(),
              proteinMin: 130,
              proteinMax: 160,
              kcalTarget: 2400,
              roundsRecord: null,
              measurement: null,
              planB: advice.show,
              planBAdvice: advice,
              fitnessTest: test,
              fitnessTestStart: test == null ? null : DateTime(2030, 3, 4),
            )),
        if (readiness != null) readinessViewProvider.overrideWith((ref, _) => readiness),
        activeSessionProvider.overrideWith((ref) => null),
        updateCheckProvider.overrideWith((ref) => const UpdateCheck(currentVersion: '1.23.0')),
        morningDoneProvider.overrideWith((ref, _) => true),
      ],
      child: MaterialApp(
        theme: buildGymTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    ));
    await settle(tester);
    return db;
  }

  final three = intenseChains([
    for (final d in [3, 4, 5]) ChainSession(date: DateTime(2030, 3, d), rpe: 8, workMinutes: 90, isFootball: true),
  ], wed)
      .legs;

  testWidgets('la tarjeta lista los motivos con sus días y la rodilla con su fecha', (tester) async {
    final advice = planBAdvice(dayHasLegs: true, legs: three, kneeStairs: 4, kneeStairsDate: wed);
    final db = await mount(tester, advice);
    expect(find.text('Plan B: solo torso'), findsOneWidget);
    expect(
        find.text(
            '• Piernas: 3 días intensos (dom 3 mar fútbol 90 min · lun 4 mar fútbol 90 min · mar 5 mar fútbol 90 min)'),
        findsOneWidget);
    expect(find.text('• Rodilla en escaleras 4/10 (mié 6 mar)'), findsOneWidget);
    expect(find.text('Empezar plan B'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester, db);
  });

  testWidgets('mañana verde: sin tarjeta, sólo la nota', (tester) async {
    final advice = planBAdvice(dayHasLegs: true, legs: three, greenMorning: true);
    final db = await mount(tester, advice);
    expect(find.text('Plan B: solo torso'), findsNothing);
    expect(find.text('Piernas con varios días intensos, pero la mañana salió bien: hoy sin Plan B.'), findsOneWidget);
    await close(tester, db);
  });

  for (final scale in const [1.0, 1.6, 2.0]) {
    testWidgets('teléfono 360×800 con texto ×$scale: tarjeta y acción alcanzables, sin desbordes', (tester) async {
      final unknown = intenseChains([
        for (final d in [3, 5]) ChainSession(date: DateTime(2030, 3, d), rpe: 8, workMinutes: 90, isFootball: true),
        ChainSession(date: DateTime(2030, 3, 4), type: SessionType.bloques, rpe: 8, workMinutes: 40), // sin grupo
        ChainSession(date: DateTime(2030, 3, 2), rpe: 8, workMinutes: 90, isFootball: true),
      ], wed)
          .legs;
      expect((unknown.days, unknown.unknownDays.length), (3, 1));
      final advice = planBAdvice(dayHasLegs: true, legs: unknown);
      final db = await mount(tester, advice, size: const Size(360, 800), textScale: scale);
      final cta = find.text('Empezar plan B');
      await tester.scrollUntilVisible(cta, 120, scrollable: find.byType(Scrollable).first);
      // scrollUntilVisible se detiene en cuanto el texto asoma; se trae
      // completo a la vista como lo haría la persona al seguir bajando.
      await tester.ensureVisible(cta);
      await settle(tester);
      expect(cta.hitTestable(), findsOneWidget);
      expect(find.textContaining('día(s) de la cadena sin datos para clasificar'), findsOneWidget,
          reason: 'la duda se ve, no se esconde');
      expect(find.textContaining('1 sin clasificar'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'sin desbordes con texto ×$scale');
      await close(tester, db);
    });
  }

  testWidgets('rojo de 032: manda el descanso y no hay botón de Plan B para entrenar', (tester) async {
    final advice = planBAdvice(dayHasLegs: true, legs: three);
    const red = ReadinessView(
      advice: ReadinessAdvice(
          level: ReadinessLevel.red, reasons: ['Marcaste enfermo, fiebre o dolor agudo'], missing: [], load3Days: 0),
      trainedAnyway: false,
      recoveryDone: false,
      routines: {},
      mobilityStreak: 0,
    );
    final db = await mount(tester, advice, readiness: red);
    expect(find.text('Hoy: solo descanso'), findsOneWidget);
    expect(find.text('Empezar plan B'), findsNothing);
    expect(find.text('Plan B: solo torso'), findsNothing);
    await close(tester, db);
  });

  testWidgets('día de test: el test va primero y no hay tarjeta de Plan B encima', (tester) async {
    final advice = planBAdvice(dayHasLegs: true, legs: three);
    final db = await mount(tester, advice, test: (round: 1, part: TestPart.piernas, done: false));
    expect(find.text('Abrir o continuar test'), findsOneWidget);
    expect(find.text('Plan B: solo torso'), findsNothing);
    expect(find.text('Empezar plan B'), findsNothing);
    await close(tester, db);
  });
}
