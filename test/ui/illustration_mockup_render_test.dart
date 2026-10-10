import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/features/training/technique_sheet.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import 'package:seguimiento/ui/theme.dart';
import '../support/test_fonts.dart';

void main() {
  final out = Platform.environment['ILLUSTRATION_OUT'];
  final all = Platform.environment['ILLUSTRATION_ALL'] == '1';
  final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
  const examples = {
    'Pino pecho a la pared',
    'Nórdico (isquios)',
    'Pike push-up',
    'Flexión a una mano',
    'Pallof press con banda',
    'Face pull con banda',
    '90/90 de cadera',
    'Peso muerto a una pierna con mochila',
    'Rollout con toalla',
    'Plancha lateral',
    'Elevaciones laterales con banda',
    'V-up'
  };

  testWidgets('mockups del catálogo y visor reales, sin renderer paralelo', (tester) async {
    await loadTestFonts(tester);
    final dir = Directory(out!)..createSync(recursive: true);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final selected = catalog.all.where((f) => all || examples.contains(f.name)).toList();
    final rows = <String>[];
    for (final (index, figure) in selected.indexed) {
      final slug = '${index + 1}';
      for (var frame = 0; frame < figure.frames.length; frame++) {
        final key = GlobalKey();
        await tester.pumpWidget(ProviderScope(
            overrides: [figure3dProvider.overrideWith((ref) async => catalog)],
            child: MaterialApp(
                theme: buildGymTheme(),
                home: Scaffold(
                    body: Center(
                  child: RepaintBoundary(
                      key: key,
                      child: ColoredBox(
                          color: const Color(0xFF0B0806),
                          child: SizedBox(
                              width: 360,
                              height: 380,
                              child: Column(children: [
                                Expanded(
                                    child: CustomPaint(
                                        size: const Size(360, 330),
                                        painter: Figure3DPainter(figure, frame / (figure.frames.length - 1)))),
                                Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(figure.frames[frame].caption,
                                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
                              ])))),
                )))));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${figure.name}/$frame');
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/$slug-$frame.png').writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      rows.add('$slug|${figure.name}|${figure.group}|${figure.frames.length}');
    }
    File('${dir.path}/catalog.tsv').writeAsStringSync(rows.join('\n'));
  }, skip: out == null);

  testWidgets('hoja legible en teléfono con texto grande', (tester) async {
    if (out == null) return;
    await loadTestFonts(tester);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final scale in [1.0, 1.6]) {
      await tester.pumpWidget(ProviderScope(
          overrides: [figure3dProvider.overrideWith((ref) async => catalog)],
          child: MaterialApp(
              theme: buildGymTheme(),
              home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: const Scaffold(body: TechniqueContent(exercise: 'Nórdico (isquios)'))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  }, skip: out == null);
}
