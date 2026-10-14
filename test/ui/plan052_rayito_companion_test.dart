import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/mascot.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/readiness.dart';
import 'package:seguimiento/features/home/rayito_companion.dart';
import 'package:seguimiento/features/home/readiness_card.dart';
import 'package:seguimiento/ui/mascot.dart';
import 'package:seguimiento/ui/theme.dart';

/// Plan 052: Rayito flotante. Habla al tocarlo, festeja cuando lo guardado
/// suma a la racha, se asoma durante el scroll, se esconde con un toque largo
/// y, encendido, se mueve de verdad. Fechas ficticias.
void main() {
  final mon = DateTime(2030, 3, 4);
  final dash = StateProvider<TodayDashboard>((ref) => _dashboard(mon, 5));
  final level = StateProvider<ReadinessLevel>((ref) => ReadinessLevel.green);

  Future<ProviderContainer> mount(WidgetTester tester,
      {bool peek = false, double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      dashboardProvider.overrideWith((ref) async => ref.watch(dash)),
      readinessViewProvider
          .overrideWith((ref, _) => _readiness(ref.watch(level))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGymTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(
          body: Stack(fit: StackFit.expand, children: [
            const SizedBox.expand(),
            Positioned(
                right: 12, bottom: 12, child: RayitoCompanion(peek: peek)),
          ]),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  RayitoAlive alive(WidgetTester tester) =>
      tester.widget<RayitoAlive>(find.byType(RayitoAlive));

  testWidgets('al tocarlo habla: la frase del día, cuánto falta y qué toca',
      (tester) async {
    await mount(tester);
    expect(alive(tester).phase, MascotPhase.cargado);
    await tester.tap(find.byType(RayitoAlive));
    await tester.pumpAndSettle();
    expect(find.text('Guarda un registro hoy y llegas a 6 días.'),
        findsOneWidget);
    await tester.tap(find.byType(RayitoAlive));
    await tester.pumpAndSettle();
    expect(find.textContaining('Guarda un registro'), findsNothing,
        reason: 'un segundo toque cierra el globo');
    await tester.tap(find.byType(RayitoAlive));
    await tester.pumpAndSettle();
    expect(find.text('Faltan 2 días para el nivel 4.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo guardado que suma a la racha lo hace saltar y festejar',
      (tester) async {
    final container = await mount(tester);
    final hop = alive(tester).hop;
    container.read(dash.notifier).state =
        _dashboard(mon, 6, activeToday: true);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(alive(tester).hop, hop + 1);
    expect(alive(tester).mood, MascotMood.contento);
    expect(find.text('¡Sumaste! 6 días seguidos construyendo tu mejor versión.'),
        findsOneWidget);
    // Subir de nivel lo dice distinto.
    container.read(dash.notifier).state =
        _dashboard(mon, 7, activeToday: true);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('¡Subí al nivel 4! 7 días seguidos.'), findsOneWidget);
  });

  testWidgets('descanso indicado: sereno y sin presionar con cuánto falta',
      (tester) async {
    final container = await mount(tester);
    container.read(level.notifier).state = ReadinessLevel.yellow;
    await tester.pump();
    await tester.pump();
    expect(alive(tester).mood, MascotMood.sereno);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byType(RayitoAlive));
      await tester.pumpAndSettle();
      expect(find.textContaining('Faltan'), findsNothing);
      await tester.tap(find.byType(RayitoAlive));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('toque largo lo esconde y avisa cómo volver', (tester) async {
    final container = await mount(tester);
    await tester.longPress(find.byType(RayitoAlive));
    await tester.pumpAndSettle();
    expect(container.read(rayitoHiddenProvider), isTrue);
    expect(find.text('Rayito se escondió. Vuelve desde Ajustes.'),
        findsOneWidget);
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(container.read(rayitoHiddenProvider), isFalse);
  });

  testWidgets('asomado durante el scroll: no muestra el globo', (tester) async {
    await mount(tester, peek: true);
    await tester.tap(find.byType(RayitoAlive), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Guarda un registro'), findsNothing);
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('360×800 con texto ×$scale: el globo cabe', (tester) async {
      await mount(tester, textScale: scale);
      await tester.tap(find.byType(RayitoAlive));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('encendido se mueve: parpadea, el halo late y salta',
      (tester) async {
    rayitoAnimationsEnabled = true;
    addTearDown(() => rayitoAnimationsEnabled = false);
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: RayitoAlive(
                phase: MascotPhase.energizado, mood: MascotMood.atento))));
    RayitoPainter painter() => tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(RayitoAlive), matching: find.byType(CustomPaint)))
        .painter! as RayitoPainter;
    final seen = <(double, double, double)>{};
    var blinked = false;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final p = painter();
      seen.add((p.glow, p.twinkle, p.look));
      if (p.blink > 0.5) blinked = true;
    }
    expect(seen.length, greaterThan(50), reason: 'cambia cuadro a cuadro');
    expect(blinked, isTrue, reason: 'parpadea en 6 s');
    // Sin animaciones del sistema queda quieto.
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: const Center(
            child: RayitoAlive(
                phase: MascotPhase.energizado, mood: MascotMood.atento))));
    await tester.pump(const Duration(seconds: 1));
    final still = painter();
    await tester.pump(const Duration(seconds: 1));
    expect((painter().glow, painter().twinkle), (still.glow, still.twinkle));
    await tester.pumpWidget(const SizedBox());
  });
}

TodayDashboard _dashboard(DateTime day, int streak,
        {bool activeToday = false}) =>
    TodayDashboard(
      date: day,
      weekIndex: 1,
      dayType: DayType.trenSuperior,
      planVersion: 3,
      planSummary: null,
      mainExercises: const ['Dominadas 3×8'],
      blockExercises: const [],
      targetRounds: null,
      roundsDone: null,
      sessionsToday: 0,
      streak: streak,
      activeToday: activeToday,
      macros: const Macros(),
      proteinMin: 130,
      proteinMax: 160,
      kcalTarget: 2400,
      roundsRecord: null,
      measurement: null,
    );

ReadinessView _readiness(ReadinessLevel level) => ReadinessView(
      advice: ReadinessAdvice(
          level: level, reasons: const [], missing: const [], load3Days: 0),
      trainedAnyway: false,
      recoveryDone: false,
      routines: const {},
      mobilityStreak: 0,
    );
