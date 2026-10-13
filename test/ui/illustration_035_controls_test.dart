import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';

void main() {
  final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
  final figure = catalog.forExercise('Barca / V-sit')!;
  Future<void> open(WidgetTester tester, {bool reduced = false, bool ticking = true}) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(size: const Size(800, 600), disableAnimations: reduced),
            child: TickerMode(enabled: ticking, child: Figure3DFullScreen(figure: figure, initialProgress: .17)))));
  }

  double progress(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<Figure3DPainter>()
      .single
      .progress;
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder.hitTestable());
    await tester.pump();
  }

  test('timeline inverse preserves any selected intermediate pose', () {
    for (final selected in [figure, catalog.forExercise('Dominadas')!]) {
      for (var i = 0; i < 100; i++) {
        final p = i / 100;
        expect(figureMotionProgress(selected, figureMotionTime(selected, p)), closeTo(p, 1e-8));
      }
    }
  });
  testWidgets('inline pause retains the visible intermediate pose', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      Figure3DMoments(figure: figure),
    ]))));
    await tapVisible(tester, find.text('Ver movimiento'));
    await tester.pump(const Duration(milliseconds: 800));
    final moving = progress(tester);
    await tapVisible(tester, find.text('Pausa'));
    await tester.pump(const Duration(seconds: 1));
    expect(progress(tester), closeTo(moving, 1e-8));
    await tapVisible(tester, find.text('Continuar'));
    expect(progress(tester), closeTo(moving, 1e-8));
    await tapVisible(tester, find.text('Ver momentos'));
    expect(find.text('Ver movimiento'), findsOneWidget);
  });
  testWidgets('play starts at selected frame and pause resumes without restarting', (tester) async {
    await open(tester);
    expect(progress(tester), closeTo(.17, 1e-8));
    await tapVisible(tester, find.text('Movimiento'));
    expect(progress(tester), closeTo(.17, 1e-8));
    await tester.pump(const Duration(milliseconds: 450));
    final moving = progress(tester);
    await tapVisible(tester, find.text('Pausa'));
    await tester.pump(const Duration(seconds: 2));
    expect(progress(tester), closeTo(moving, 1e-8));
    await tapVisible(tester, find.text('Movimiento'));
    expect(progress(tester), closeTo(moving, 1e-8));
  });
  testWidgets('scrolling the inline figure away pauses without losing its pose', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                controller: scroll,
                child: Column(children: [Figure3DMoments(figure: figure), const SizedBox(height: 1800)])))));
    await tapVisible(tester, find.text('Ver movimiento'));
    await tester.pump(const Duration(milliseconds: 800));
    scroll.jumpTo(1200);
    await tester.pump();
    final stopped = progress(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(progress(tester), closeTo(stopped, 1e-8));
    scroll.jumpTo(0);
    await tester.pump();
    expect(find.text('Continuar'), findsOneWidget);
    expect(progress(tester), closeTo(stopped, 1e-8));
  });
  testWidgets('reduced motion stops playback and keeps manual frames available', (tester) async {
    await open(tester);
    await tapVisible(tester, find.text('Movimiento'));
    await tester.pump(const Duration(milliseconds: 450));
    await open(tester, reduced: true);
    await tester.pump();
    final stopped = progress(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(progress(tester), stopped);
    expect(tester.widget<ActionChip>(find.widgetWithText(ActionChip, 'Movimiento')).onPressed, isNull);
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Sostén').first);
    expect(progress(tester), isNot(stopped));
  });
  testWidgets('covered route ticker mode pauses and requires explicit resume', (tester) async {
    await open(tester);
    await tapVisible(tester, find.text('Movimiento'));
    await tester.pump(const Duration(milliseconds: 450));
    await open(tester, ticking: false);
    await tester.pump();
    final stopped = progress(tester);
    await tester.pump(const Duration(seconds: 2));
    await open(tester);
    await tester.pump();
    expect(progress(tester), closeTo(stopped, 1e-8));
    expect(find.text('Movimiento'), findsOneWidget);
    expect(find.text('Pausa'), findsNothing);
  });
  testWidgets('changing fullscreen exercise resets playback and retains the requested initial pose', (tester) async {
    await open(tester);
    await tapVisible(tester, find.text('Movimiento'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: TickerMode(
            enabled: true, child: Figure3DFullScreen(figure: catalog.forExercise('Dominadas')!, initialProgress: .35)),
      ),
    ));
    expect(find.text('Pausa'), findsNothing);
    expect(progress(tester), closeTo(.35, 1e-8));
    await tester.pump(const Duration(seconds: 1));
    expect(progress(tester), closeTo(.35, 1e-8));
    Figure3DPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<Figure3DPainter>()
        .single;
    final pullup = catalog.forExercise('Dominadas')!;
    expect(painter().yaw, pullup.initialYaw);
    await tapVisible(tester, find.text('De perfil'));
    expect(painter().yaw, 0);
    await tapVisible(tester, find.text('Vista inicial'));
    expect(painter().yaw, pullup.initialYaw);
    expect(painter().pitch, pullup.initialPitch);
    expect(progress(tester), closeTo(.35, 1e-8));
  });
  testWidgets('FIFA parts and playback remain reachable at phone width and large text', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
      home: Figure3DFullScreen(figure: catalog.forExercise('Calentamiento tipo FIFA 11+')!),
    ));
    expect(tester.takeException(), isNull);
    final selector = find.byType(DropdownButton<int>);
    expect(selector, findsOneWidget);
    expect(tester.widget<DropdownButton<int>>(selector).items, hasLength(10));
    expect(find.text('Parte 1 de 10'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    await tapVisible(tester, selector);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('5: Plancha lateral, por ambos lados').last);
    await tester.pumpAndSettle();
    expect(find.text('Parte 5 de 10'), findsOneWidget);
    final selected = progress(tester);
    expect(selected, greaterThan(0));
    final fifa = catalog.forExercise('Calentamiento tipo FIFA 11+')!;
    expect(fifa.stageAt(selected)!.part, '5');
    expect(fifa.stageAt(selected)!.kind, isNot('cut'));
    await tapVisible(tester, find.text('Movimiento'));
    expect(progress(tester), closeTo(selected, 1e-8));
    await tester.pump(const Duration(milliseconds: 300));
    await tapVisible(tester, find.text('Pausa'));
    final stopped = progress(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(progress(tester), closeTo(stopped, 1e-8));
    await tapVisible(tester, find.text('Movimiento'));
    expect(progress(tester), closeTo(stopped, 1e-8));
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Parte 5 de 10'), findsOneWidget);
    expect(fifa.stageAt(progress(tester))!.part, '5');
    expect(find.text('Pausa'), findsNothing);
    final completed = progress(tester);
    await tapVisible(tester, find.text('Siguiente parte'));
    expect(find.text('Parte 6 de 10'), findsOneWidget);
    expect(progress(tester), greaterThan(completed));
    expect(fifa.stageAt(progress(tester))!.part, '6');
    expect(fifa.stageAt(progress(tester))!.kind, isNot('cut'));
    final nordicStart = fifa.skeletonAt(progress(tester)).joints;
    await tapVisible(tester, find.text('Movimiento'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(fifa.stageAt(progress(tester))!.part, '6');
    expect(fifa.skeletonAt(progress(tester)).joints, isNot(nordicStart));
    await tapVisible(tester, find.text('Pausa'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('inline FIFA reduced motion preserves direct part navigation and painter identity', (tester) async {
    final fifa = catalog.forExercise('Calentamiento tipo FIFA 11+')!;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600), disableAnimations: true),
        child: Scaffold(body: ListView(children: [Figure3DMoments(figure: fifa)])),
      ),
    ));
    expect(find.byType(PageView), findsNothing);
    expect(find.text('Parte 1 de 10'), findsOneWidget);
    final play = find.ancestor(of: find.text('Movimiento'), matching: find.byWidgetPredicate((w) => w is TextButton));
    expect(tester.widget<TextButton>(play).onPressed, isNull);
    await tapVisible(tester, find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('5: Plancha lateral, por ambos lados').last);
    await tester.pumpAndSettle();
    expect(find.text('Parte 5 de 10'), findsOneWidget);
    expect(fifa.stageAt(progress(tester))!.part, '5');
    final selected = progress(tester);
    await tester.pump(const Duration(seconds: 60));
    expect(progress(tester), selected);
    await tapVisible(tester, find.text('Siguiente parte'));
    expect(find.text('Parte 6 de 10'), findsOneWidget);
    final frame = fifa.motion.indexWhere((stage) => stage.part == '6' && stage.kind != 'cut');
    expect(progress(tester), closeTo(frame / fifa.motion.length, 1e-8));
    expect(fifa.stageAt(progress(tester))!.kind, isNot('cut'));
    expect(tester.takeException(), isNull);
  });
}
