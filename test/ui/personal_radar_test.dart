import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/domain/progress_metrics.dart';
import 'package:seguimiento/features/report/personal_radar_widget.dart';
import 'package:seguimiento/ui/theme.dart';
import '../support/radar_fixture.dart';
import '../support/radar_sql_fixture.dart';
import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

void main() {
  setUpAll(useHostSqlite);
  Future<void> show(WidgetTester tester, PersonalRadar radar,
      {double scale = 1,
      ValueChanged<RadarAxis>? register,
      ValueChanged<RadarAxis>? configure,
      ValueChanged<RadarAxis>? select}) async {
    await loadTestFonts(tester);
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = buildGymTheme();
    final screen = MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
            inputDecorationTheme: theme.inputDecorationTheme
                .copyWith(labelStyle: const TextStyle(fontFamily: 'Roboto'))),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: RepaintBoundary(
            key: const Key('radar-shot'),
            child: Scaffold(
                appBar: AppBar(
                    title: const Text('Datos FICTICIOS',
                        style: TextStyle(fontFamily: 'Roboto', fontSize: 14))),
                body: SingleChildScrollView(
                    child: PersonalRadarWidget(
                        radar: radar,
                        onRegister: register,
                        onConfigure: configure,
                        onAxisSelected: select)))));
    await tester.pumpWidget(screen);
    await tester.pumpAndSettle();
  }

  RadarPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<RadarPainter>()
      .single;
  Future<void> shot(WidgetTester tester, String name) async {
    final target = Platform.environment['RADAR_018_OUT'];
    if (target == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('radar-shot')));
    await tester.runAsync(() async {
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory(target)..createSync(recursive: true);
      File('${folder.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      final radar = tester
          .widget<PersonalRadarWidget>(find.byType(PersonalRadarWidget))
          .radar;
      File('${folder.path}/$name.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'synthetic': true,
        'asOf': radar.asOf.toIso8601String(),
        'axes': [
          for (final axis in radar.axes)
            {
              'axis': axis.axis.name,
              'unit': axis.axis.unit,
              'referenceId': axis.reference?.id,
              'reference': axis.reference?.value,
              'referenceSource': axis.reference?.source,
              'referenceFrom': axis.reference?.from.toIso8601String(),
              'referenceUntil': axis.reference?.until?.toIso8601String(),
              'initialValue': axis.firstEligible?.value,
              'currentValue': axis.current?.value,
              'initialPercent': axis.initialPercent,
              'currentPercent': axis.currentPercent,
              'observations': [
                for (final o in axis.observations)
                  {
                    'sourceKey': o.sourceKey,
                    'protocol': o.protocol,
                    'value': o.value,
                    'date': o.date?.toIso8601String(),
                    'eligible': o.eligible,
                    'quality': o.quality,
                    'reason': o.reason,
                    'raw': o.raw,
                    'tests': [
                      for (final r in o.testRows)
                        {
                          'item': r.item,
                          'round': r.round,
                          'side': r.side,
                          'value':
                              r.value.isFinite ? r.value : r.value.toString(),
                          'clean': r.clean,
                          'date': r.date?.toIso8601String()
                        }
                    ],
                    if (o.cindy != null)
                      'cindy': {
                        'id': o.cindy!.id,
                        'rounds': o.cindy!.rounds,
                        'extraReps': o.cindy!.extraReps,
                        'totalSec': o.cindy!.totalSec,
                        'warmupSec': o.cindy!.warmupSec,
                        'cooldownSec': o.cindy!.cooldownSec,
                        'imported': o.cindy!.imported,
                        'estimated': o.cindy!.estimated,
                        'incomplete': o.cindy!.incomplete,
                        'techniqueOk': o.cindy!.techniqueOk,
                        'fullRange': o.cindy!.fullRange,
                        'sets': [
                          for (final s in o.cindy!.sets)
                            {
                              'exercise': s.exercise,
                              'reps': s.reps,
                              'variant': s.variant,
                              'loadKg': s.loadKg,
                              'split': s.split,
                              'toFailure': s.toFailure
                            }
                        ]
                      }
                  }
              ]
            }
        ]
      }));
      picture.dispose();
    });
  }

  Future<void> verifyPaintedDot(WidgetTester tester) async {
    final graph = find.byKey(const Key('radar-canvas'));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('radar-shot')));
    final graphOrigin = tester.getTopLeft(graph) -
        tester.getTopLeft(find.byKey(const Key('radar-shot')));
    // Fixture pull=12/reference10: true point saturates at100 on axis1.
    final pixel =
        (graphOrigin + RadarPainter.axisPoint(tester.getSize(graph), 0, 1)) * 2;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final offset = (pixel.dy.round() * image.width + pixel.dx.round()) * 4;
        expect(raw!.buffer.asUint8List().sublist(offset, offset + 4),
            [0xf0, 0x8a, 0x34, 0xff],
            reason:
                'El punto real debe estar pintado, no sólo presente en el DTO.');
        final size = tester.getSize(graph), bytes = raw.buffer.asUint8List();
        bool hasColorNear(Offset logical, bool initial) {
          final p = (graphOrigin + logical) * 2;
          for (var dx = -2; dx <= 2; dx++) {
            for (var dy = -2; dy <= 2; dy++) {
              final at =
                  ((p.dy.round() + dy) * image.width + p.dx.round() + dx) * 4;
              final r = bytes[at], g = bytes[at + 1], b = bytes[at + 2];
              if (initial
                  ? r < 120 && g > 180 && b > 130
                  : r > 210 && g > 90 && g < 180 && b < 90) {
                return true;
              }
            }
          }
          return false;
        }

        // Both witnesses are farther than the4dp vertex circles. A painter
        // with points only cannot satisfy these actual raster assertions.
        final nowA = RadarPainter.axisPoint(size, 0, 1),
            nowB = RadarPainter.axisPoint(size, 1, 2 / 3);
        expect(hasColorNear((nowA + nowB) / 2, false), isTrue,
            reason: 'Tramo naranja entre vértices.');
        final oldA = RadarPainter.axisPoint(size, 0, .5),
            oldB = RadarPainter.axisPoint(size, 1, .5);
        expect(
            hasColorNear(
                oldA + (oldB - oldA) * (12 / (oldB - oldA).distance), true),
            isTrue,
            reason:
                'Tramo turquesa discontinuo a12dp del vértice, fuera del círculo.');
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets('cero real frente a ausentes y callbacks sin escritura/rutas',
      (tester) async {
    RadarAxis? registered, configured;
    final radar = buildPersonalRadar(tests: [], asOf: radarDay);
    await show(tester, radar,
        register: (a) => registered = a,
        configure: (a) => configured = a,
        scale: 2);
    expect(painter(tester).current.fractions, everyElement(isNull));
    expect(painter(tester).current.closed, isFalse);
    expect(find.textContaining('Sin registros de pruebas'), findsOneWidget);
    await tester.ensureVisible(find.text('Registrar Tirón'));
    await tester.tap(find.text('Registrar Tirón'));
    await tester.pumpAndSettle();
    expect(registered, RadarAxis.pull);
    await tester.ensureVisible(find.text('Definir referencia de Tirón'));
    await tester.tap(find.text('Definir referencia de Tirón'));
    await tester.pumpAndSettle();
    expect(configured, RadarAxis.pull);
    expect(tester.takeException(), isNull);
    await shot(tester, 'sin-datos-360-texto2');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('dos ejes no rellenan huecos y sin refs mantiene crudo',
      (tester) async {
    final tests = radarTests()
        .where((r) => ['pullup', 'pushup'].contains(r.item))
        .toList();
    await show(
        tester,
        buildPersonalRadar(
            tests: tests, references: radarReferences(), asOf: radarDay),
        scale: 1.6);
    expect(painter(tester).current.fractions.where((v) => v != null).length, 2);
    expect(painter(tester).current.closed, isFalse);
    expect(find.textContaining('2 de 6 ejes'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('radar-canvas')));
    await shot(tester, 'dos-ejes-360-texto16');
    await show(tester, buildPersonalRadar(tests: tests, asOf: radarDay));
    expect(painter(tester).current.fractions, everyElement(isNull));
    expect(find.textContaining('Última apta: 8 reps'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('SQLite→008→núcleo→UI conserva dudas/fecha/bilateral',
      (tester) async {
    final db = openInMemoryDatabase();
    try {
      for (final r in [
        ...radarTests(),
        knownRadarTest(
            round: 3, item: 'pullup', value: 12, clean: false, date: radarDay)
      ]) {
        await insertRadarTestSql(db, r);
      }
      final rows = await FitnessTestRepository(db).all();
      final radar = buildPersonalRadar(
          tests: rows, references: radarReferences(), asOf: radarDay);
      await show(tester, radar, scale: 1.6);
      expect(find.textContaining('Última apta: 8 reps'), findsOneWidget);
      expect(find.textContaining('Último intento observado: 12 reps'),
          findsOneWidget);
      expect(find.textContaining('Técnica declarada con dudas'), findsWidgets);
      expect(radar.axis(RadarAxis.legs).current?.value, 20);
      await tester.ensureVisible(find.byKey(const Key('radar-axis-pull')));
      await tester.tap(find.byKey(const Key('radar-axis-pull')));
      await tester.pumpAndSettle();
      expect(find.text('Evidencia de Tirón'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await db.close();
    }
  });
  testWidgets('touch canvas, teclado, semántica y mostrar inicio',
      (tester) async {
    RadarAxis? chosen;
    final semantics = tester.ensureSemantics();
    try {
      final radar = buildPersonalRadar(
          tests: radarTests(),
          cindy: [radarCindy()],
          references: radarReferences(),
          asOf: radarDay);
      await show(tester, radar, select: (a) => chosen = a);
      final graph = find.byKey(const Key('radar-canvas'));
      await tester.ensureVisible(graph);
      await tester.pumpAndSettle();
      final size = tester.getSize(graph), origin = tester.getTopLeft(graph);
      await tester.tapAt(origin + RadarPainter.axisPoint(size, 2, 1.4));
      await tester.pumpAndSettle();
      expect(chosen, RadarAxis.core);
      expect(find.text('Evidencia de Core'), findsOneWidget);
      final button = find.byKey(const Key('radar-axis-pull'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(button).getSemanticsData().label,
          contains('Tirón'));
      final label = find.descendant(of: button, matching: find.byType(Text));
      Focus.of(tester.element(label)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chosen, RadarAxis.pull);
      final toggle = find.byType(SwitchListTile);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(painter(tester).showInitial, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });
  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets('renderer real360 texto$scale, >100 conserva crudo',
        (tester) async {
      final tests = [
        ...radarTests().where((r) => r.item != 'pullup'),
        knownRadarTest(
            round: 1, item: 'pullup', value: 5, date: DateTime(2026, 10, 1)),
        knownRadarTest(
            round: 2, item: 'pullup', value: 12, date: DateTime(2026, 10, 9))
      ];
      final radar = buildPersonalRadar(
          tests: tests,
          cindy: [radarCindy(id: 'first', day: 1, rounds: 6), radarCindy()],
          references: radarReferences(),
          asOf: radarDay);
      await show(tester, radar, scale: scale);
      expect(painter(tester).current.closed, isTrue);
      expect(painter(tester).initial.closed, isTrue);
      expect(
          find.textContaining('Actual hacia referencia: 120%'), findsOneWidget);
      expect(find.textContaining('Última apta: 12 reps'), findsOneWidget);
      final graph = find.byKey(const Key('radar-canvas'));
      await tester.ensureVisible(graph);
      await tester.pumpAndSettle();
      await verifyPaintedDot(tester);
      expect(
          painter(tester).axisLabels(tester.getSize(graph)),
          scale >= 2
              ? ['1', '2', '3', '4', '5', '6']
              : ['Tirón', 'Empuje', 'Core', 'Piernas', 'Salto', 'Circuito']);
      await shot(tester, 'completo-360-texto$scale');
      await tester.ensureVisible(find.byKey(const Key('radar-axis-circuit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('widget muestra valor/ref común y tap evidencia sin rutas',
      (tester) async {
    final radar = buildPersonalRadar(
        tests: radarTests(),
        cindy: [radarCindy()],
        references: radarReferences(),
        asOf: radarDay);
    await tester.pumpWidget(MaterialApp(
        theme: buildGymTheme(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: PersonalRadarWidget(radar: radar)))));
    expect(find.textContaining('8 reps'), findsWidgets);
    expect(find.textContaining('Referencia común: 10 reps'), findsWidgets);
    expect(find.textContaining('Referencia FICTICIA aceptada'), findsWidgets);
    expect(radar.axis(RadarAxis.pull).reference!.id, 'fixture-pull');
    expect(find.byKey(const Key('radar-axis-pull')), findsOneWidget);
  });
}
