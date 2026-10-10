import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/features/training/technique_sheet.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/ui/exercise_art.dart';
import 'package:seguimiento/ui/exercise_figure.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import 'package:seguimiento/ui/theme.dart';
import '../support/test_fonts.dart';

void main() {
  final out = Platform.environment['ILLUSTRATION_OUT'];
  final all = Platform.environment['ILLUSTRATION_ALL'] == '1';
  final names = Platform.environment['ILLUSTRATION_NAMES']?.split(';').toSet();
  final art = ExerciseArtCatalog.fromJsonString(File(ExerciseArtCatalog.asset).readAsStringSync());
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
    final selected = catalog.all.where((f) => names?.contains(f.name) ?? (all || examples.contains(f.name))).toList();
    if (names != null) expect(selected.map((f) => f.name).toSet(), names);
    final rows = <String>[];
    for (final (index, figure) in selected.indexed) {
      final slug = '${index + 1}';
      final samples = <String, double>{
        for (var i = 0; i < figure.frames.length; i++) '$i': i / (figure.frames.length - 1),
        if (names != null) 'intermedio-15': 15 / 60,
        if (names != null) 'intermedio-35': 35 / 60,
        if (names != null && figure.perSide) 'derecho-15': 15 / 60
      };
      for (final sample in samples.entries) {
        final frame = sample.key;
        final rendered = frame.startsWith('derecho') ? catalog.forExercise(figure.name, side: 'D')! : figure;
        final caption = (frame.startsWith('intermedio') || frame.startsWith('derecho'))
            ? '${frame.startsWith('derecho') ? 'Lado derecho · ' : ''}Intermedio ${sample.value.toStringAsFixed(3)}'
            : figure.frames[int.parse(frame)].caption;
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
                              height: 410,
                              child: Column(children: [
                                const Text('Propuesta · no instalada',
                                    style: TextStyle(color: Colors.orange, fontSize: 12)),
                                Text(figure.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Expanded(
                                    child: CustomPaint(
                                        size: const Size(360, 330), painter: Figure3DPainter(rendered, sample.value))),
                                Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(caption,
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
    final exercises = names?.toList() ?? ['Nórdico (isquios)'];
    final dir = Directory(out);
    Future<void> capture(GlobalKey key, String name) async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final (index, exercise) in exercises.indexed) {
      for (final scale in [1.0, 1.6]) {
        final key = GlobalKey();
        await tester.pumpWidget(ProviderScope(
            overrides: [
              figure3dProvider.overrideWith((ref) => catalog),
              exerciseArtProvider.overrideWith((ref) => art),
              exercisePhotoProvider.overrideWith((ref, _) => Stream.value(null)),
              documentsDirProvider.overrideWith((ref) => Directory.systemTemp)
            ],
            child: MaterialApp(
                theme: buildGymTheme(),
                home: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(
                        key: key,
                        child: Scaffold(
                            appBar: AppBar(
                                title: const Text('Propuesta · no instalada',
                                    style: TextStyle(fontSize: 14, fontFamily: 'Roboto'))),
                            body: TechniqueContent(key: ValueKey('$exercise/$scale'), exercise: exercise)))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$exercise/text$scale');
        expect(find.byType(ExerciseFigureView), findsOneWidget);
        await capture(key, 'sheet-${index + 1}-$scale-top');
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$exercise/cues$scale');
        await capture(key, 'sheet-${index + 1}-$scale-cues');
      }
    }
  }, skip: out == null);
}
