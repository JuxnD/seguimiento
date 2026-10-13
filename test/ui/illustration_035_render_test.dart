import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import '../support/test_fonts.dart';

/// Evidence uses the production painter and production/catalog baseline data.
/// This is an opt-in capture harness, not a second illustration implementation.
void main() {
  final output = Platform.environment['ILLUSTRATION_035_OUT'];
  testWidgets('035 bounded production renderer contact sheets', (tester) async {
    await loadTestFonts(tester);
    final directory = Directory(output!)..createSync(recursive: true);
    final catalog = Figure3DCatalog.fromJsonString(File(
      Platform.environment['ILLUSTRATION_FIXTURE'] ?? Figure3DCatalog.asset,
    ).readAsStringSync());
    final names = Platform.environment['ILLUSTRATION_035_NAMES']?.split(';') ??
        [
          'Dominadas',
          'Elevaciones en straddle',
          'Colgarse de la barra',
          'Colgado pasivo',
          'Barca / V-sit',
          'V-up',
          'Dragon flag',
          'Vela',
          'Curl con banda',
          'Carga abrazada al pecho',
          'Carga de maleta con mochila',
          '90/90 de cadera',
          'Aceleración 10–20 m',
          'Burpees',
          'Calentamiento tipo FIFA 11+',
        ];
    for (final (index, name) in names.indexed) {
      final fig = catalog.forExercise(name);
      expect(fig, isNotNull, reason: name);
      const tile = Size(360, 360);
      final angles = name == 'Dominadas' ? [0.0, 35.0, 90.0] : [fig!.initialYaw];
      final samples = name == 'Dominadas' ? [0.0, .2, .35, .42, .46, .5, .65, .8] : [0.0, .2, .4, .6, .8, 1.0];
      if (name == 'Calentamiento tipo FIFA 11+' && fig!.hasMotion) {
        samples.clear();
        for (var part = 1; part <= 10; part++) {
          final first = fig.motion.indexWhere((s) => s.part == '$part' && s.kind != 'cut');
          expect(first, greaterThanOrEqualTo(0));
          samples.add(first / fig.motion.length);
          samples.add((first + (part == 8 || part == 9 ? 1 : .5)) / fig.motion.length);
        }
      }
      final columns = name == 'Dominadas' ? 8 : 6;
      final rows = (samples.length * angles.length / columns).ceil();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final geometry = <Map<String, Object?>>[];
      canvas.drawColor(const Color(0xff0b0806), BlendMode.src);
      for (var row = 0; row < angles.length; row++) {
        for (var column = 0; column < samples.length; column++) {
          final p = samples[column];
          if (name == 'Dominadas') {
            final body = liftSkeleton(fig!.skeletonAt(p), fig);
            geometry.add({
              'progress': p,
              'yaw': angles[row],
              'joints': {
                for (final entry in body.p.entries) entry.key: [entry.value.x, entry.value.y, entry.value.z]
              },
              'flexors': {
                for (final entry in body.flexor.entries) entry.key: [entry.value.x, entry.value.y, entry.value.z]
              },
              'endDirections': {
                for (final entry in body.endDir.entries) entry.key: [entry.value.x, entry.value.y, entry.value.z]
              },
            });
          }
          canvas.save();
          final cell = row * samples.length + column;
          canvas.translate((cell % columns) * tile.width, (cell ~/ columns) * tile.height);
          Figure3DPainter(fig!, p, yaw: angles[row], pitch: name == 'Dominadas' ? 10 : fig.initialPitch)
              .paint(canvas, const Size(360, 315));
          final label = TextPainter(
            text: TextSpan(
                text: '$name · ${fig.stageAt(p)?.part ?? ''}\np=${p.toStringAsFixed(2)} · yaw=${angles[row]}',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 350);
          label.paint(canvas, const Offset(5, 316));
          label.dispose();
          canvas.restore();
        }
      }
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final image = await picture.toImage(360 * columns, 360 * rows);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${directory.path}/${index + 1}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      picture.dispose();
      if (geometry.isNotEmpty) {
        File('${directory.path}/${index + 1}-geometry.json').writeAsStringSync(jsonEncode(geometry));
      }
    }
    File('${directory.path}/catalog.txt').writeAsStringSync(names.join('\n'));
  }, skip: output == null);
}
