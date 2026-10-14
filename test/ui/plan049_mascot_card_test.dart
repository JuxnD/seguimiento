import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/rayito_widget_bridge.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/mascot.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/readiness.dart';
import 'package:seguimiento/features/home/mascot_card.dart';
import 'package:seguimiento/features/home/readiness_card.dart';
import 'package:seguimiento/ui/mascot.dart';
import 'package:seguimiento/ui/theme.dart';

/// Plan 049: la tarjeta de Rayito en Hoy. Fase por la racha, cara por el día
/// y el siguiente paso dicho con datos; legible en un teléfono con texto
/// grande. Fechas ficticias.
class _Recorder extends RayitoWidgetBridge {
  _Recorder() : super(android: false);
  final sent = <RayitoWidgetData>[];
  @override
  Future<bool> update(RayitoWidgetData data) async {
    sent.add(data);
    return true;
  }
}

void main() {
  final mon = DateTime(2030, 3, 4);

  TodayDashboard dashboard(
          {required int streak,
          bool activeToday = false,
          DayType type = DayType.trenSuperior}) =>
      TodayDashboard(
        date: mon,
        weekIndex: 1,
        dayType: type,
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

  ReadinessView readiness(ReadinessLevel level, {bool trainedAnyway = false}) =>
      ReadinessView(
        advice: ReadinessAdvice(
            level: level, reasons: const [], missing: const [], load3Days: 0),
        trainedAnyway: trainedAnyway,
        recoveryDone: false,
        routines: const {},
        mobilityStreak: 0,
      );

  Future<void> mount(WidgetTester tester, TodayDashboard d,
      {ReadinessLevel level = ReadinessLevel.green,
      double textScale = 1,
      Size size = const Size(420, 900),
      _Recorder? widgetBridge}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        readinessViewProvider.overrideWith((ref, _) => readiness(level)),
        rayitoWidgetBridgeProvider
            .overrideWithValue(widgetBridge ?? _Recorder()),
      ],
      child: MaterialApp(
        theme: buildGymTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: ListView(children: [MascotCard(dashboard: d)])),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  RayitoPainter painter(WidgetTester tester) => tester
      .widget<CustomPaint>(find.descendant(
          of: find.byType(Rayito), matching: find.byType(CustomPaint)))
      .painter! as RayitoPainter;

  testWidgets('5 días y hoy registrado: Cargado, contento y cuánto falta',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, dashboard(streak: 5, activeToday: true));
    // Plan 052: el nombre es sólo «Rayito»; la fase se dice como nivel y la
    // frase del día la dice el compañero flotante, no la tarjeta.
    expect(find.text('Rayito'), findsOneWidget);
    expect(find.text('Nivel 3 de 8 · 5 días de racha'), findsOneWidget);
    expect(find.text('Faltan 2 días para el nivel 4.'), findsOneWidget);
    expect(find.textContaining('Cargado'), findsNothing);
    expect(
        find.text(
            'Hoy ya sumaste. 5 días seguidos construyendo tu mejor versión.'),
        findsNothing);
    expect((painter(tester).phase, painter(tester).mood),
        (MascotPhase.cargado, MascotMood.contento));
    expect(
        find.bySemanticsLabel(
            'Rayito, Nivel 3 de 8, 5 días de racha'),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('sin racha: dormido y a un día de despertar', (tester) async {
    await mount(tester, dashboard(streak: 0));
    expect(find.text('Rayito'), findsOneWidget);
    expect(find.text('Nivel 1 de 8 · Sin racha todavía'), findsOneWidget);
    expect(find.text('Un día más y sube al nivel 2.'), findsOneWidget);
    expect(painter(tester).mood, MascotMood.dormido);
  });

  testWidgets('amarillo de 032 sin registro hoy: sereno, no presiona',
      (tester) async {
    await mount(tester, dashboard(streak: 9), level: ReadinessLevel.yellow);
    expect(painter(tester).mood, MascotMood.sereno);
    expect(find.textContaining('Faltan'), findsNothing, reason: 'no presiona');
    expect(painter(tester).phase, MascotPhase.energizado);
  });

  testWidgets('Leyenda no promete una fase siguiente', (tester) async {
    await mount(tester, dashboard(streak: 75, activeToday: true));
    expect(find.text('Nivel 8 de 8 · 75 días de racha'), findsOneWidget);
    expect(find.textContaining('Faltan'), findsNothing);
    expect(find.textContaining('Un día más'), findsNothing);
  });

  testWidgets(
      'rojo sólo descanso: widget y ánimo sin rutina ni cuenta pendiente',
      (tester) async {
    final bridge = _Recorder();
    await mount(tester, dashboard(streak: 6),
        level: ReadinessLevel.red, widgetBridge: bridge);
    expect(bridge.sent.last.today, 'Descanso');
    expect(painter(tester).mood, MascotMood.sereno);
    expect(find.textContaining('Un día más'), findsNothing);
    expect(find.textContaining('Registra'), findsNothing);
    expect(find.textContaining('suave'), findsNothing);
  });

  testWidgets(
      'descanso planificado sereno; fútbol programado mantiene su nombre',
      (tester) async {
    final bridge = _Recorder();
    await mount(tester, dashboard(streak: 6, type: DayType.descanso),
        widgetBridge: bridge);
    expect(painter(tester).mood, MascotMood.sereno);
    expect(bridge.sent.last.today, 'Descanso');
    expect(find.textContaining('Un día más'), findsNothing);
    await mount(tester, dashboard(streak: 6, type: DayType.futbol),
        widgetBridge: bridge);
    expect(bridge.sent.last.today, 'Fútbol');
    expect(painter(tester).mood, MascotMood.atento);
  });

  testWidgets(
      'el widget de inicio recibe lo mismo que la tarjeta, una sola vez',
      (tester) async {
    final bridge = _Recorder();
    await mount(tester, dashboard(streak: 5, activeToday: true),
        widgetBridge: bridge);
    await tester.pump();
    expect(bridge.sent, hasLength(1));
    expect(
        bridge.sent.single,
        RayitoWidgetData(
            phase: MascotPhase.cargado,
            mood: MascotMood.contento,
            streak: 5,
            today: 'Tren superior',
            date: mon));
  });

  for (final scale in const [1.0, 1.6, 2.0]) {
    testWidgets('teléfono 360×800 con texto ×$scale: sin desbordes',
        (tester) async {
      await mount(tester, dashboard(streak: 21, activeToday: false),
          textScale: scale, size: const Size(360, 800));
      expect(find.text('Nivel 6 de 8 · 21 días de racha'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
