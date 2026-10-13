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
      const tile = Size(360, 400);
      final requestedAngles = Platform.environment['ILLUSTRATION_035_ANGLES'];
      final angles = requestedAngles != null
          ? requestedAngles.split(',').map(double.parse).toList()
          : name == 'Dominadas' ? [0.0, 35.0, 90.0] : [fig!.initialYaw];
      final samples = name == 'Dominadas'
          ? [for (var i = 0; i < 24; i++) i / 23]
          : fig!.hasMotion
              ? [for (var i = 0; i < fig.frames.length; i++) i / (fig.frames.length - 1)]
              : [0.0, .2, .4, .6, .8, 1.0];
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
          canvas.save();
          Figure3DPainter(fig!, p, yaw: angles[row], pitch: name == 'Dominadas' ? 10 : fig.initialPitch)
              .paint(canvas, const Size(360, 315));
          canvas.restore(); // The production painter clips its figure rectangle.
          final label = TextPainter(
            text: TextSpan(
                text: '$name · p=${p.toStringAsFixed(2)} · yaw=${angles[row]}\n'
                    '${fig.hasMotion ? figureMotionCaption(fig, p) : fig.frames[(p * (fig.frames.length - 1)).round()].caption}',
                style: const TextStyle(color: Colors.white, fontFamily: 'Roboto', fontSize: 12)),
            textDirection: TextDirection.ltr,
            maxLines: 4,
          )..layout(maxWidth: 350);
          label.paint(canvas, const Offset(5, 316));
          label.dispose();
          canvas.restore();
        }
      }
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final image = await picture.toImage(360 * columns, 400 * rows);
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

  final animationOutput = Platform.environment['ILLUSTRATION_035_ANIMATION_OUT'];
  testWidgets('035 actual production timelines at twenty frames per second', (tester) async {
    await loadTestFonts(tester);
    final sourceCommit = Platform.environment['ILLUSTRATION_035_SOURCE_SHA'];
    expect(sourceCommit, matches(RegExp(r'^[a-f0-9]{40}$')));
    final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
    const groups = [
      ['90/90 de cadera'],
      ['Burpees'],
      ['Barca / V-sit', 'V-up'],
      ['Dragon flag', 'Vela'],
      ['Dominadas'],
      ['Aceleración 10–20 m'],
      ['Calentamiento tipo FIFA 11+'],
    ];
    final selectedGroup = int.parse(Platform.environment['ILLUSTRATION_035_CLIP']!);
    expect(selectedGroup, inInclusiveRange(1, groups.length));
    const fps = 20;
    final manifest = <Map<String, Object?>>[];
    for (var group = 0; group < groups.length; group++) {
      if (group + 1 != selectedGroup) continue;
      final figures = [for (final name in groups[group]) catalog.forExercise(name)!];
      final part = group == 6 ? figureMotionParts(figures.single)[2] : null;
      final durations = [
        for (final fig in figures)
          part != null
              ? part.endTime - part.startTime
              : fig.hasMotion
                  ? fig.motion.fold<double>(0, (sum, stage) => sum + stage.seconds)
                  : .6 + 2 * (fig.frames.length - 1) * 3
      ];
      final duration = durations.reduce((a, b) => a > b ? a : b);
      final count = (duration * fps).round();
      final directory = Directory('$animationOutput/${group + 1}')..createSync(recursive: true);
      final samples = <Map<String, Object?>>[];
      for (var frame = 0; frame < count; frame++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawColor(const Color(0xff0b0806), BlendMode.src);
        final frameFigures = <Map<String, Object?>>[];
        for (var column = 0; column < figures.length; column++) {
          final fig = figures[column];
          final seconds = (frame / fps).clamp(0.0, durations[column] - 1e-6).toDouble();
          // Shorter paired demonstrations stop at the end of one actual cycle.
          // No time scaling or copied easing curve is used for the comparison.
          final progress =
              part == null ? figureMotionProgress(fig, seconds) : part.progressAt(fig, part.startTime + seconds);
          final stopped = frame / fps >= durations[column];
          final yaw = fig.name == 'Dominadas' ? 35.0 : fig.initialYaw;
          frameFigures.add({
            'name': fig.name,
            'seconds': seconds,
            'timelineSeconds': seconds + (part?.startTime ?? 0),
            'progress': progress,
            'yaw': yaw,
            'pitch': fig.initialPitch,
            'pausedAtEnd': stopped
          });
          canvas.save();
          canvas.translate(column * 320.0, 0);
          canvas.save();
          Figure3DPainter(fig, progress, yaw: yaw, pitch: fig.initialPitch).paint(canvas, const Size(320, 285));
          canvas.restore();
          final label = TextPainter(
            text: TextSpan(
                text:
                    '${fig.name}${part != null ? ' · Sólo Parte 3' : ''}${stopped ? ' · Pausa al terminar su ciclo' : ''}\n${fig.hasMotion ? figureMotionCaption(fig, progress) : fig.frames[(progress * (fig.frames.length - 1)).round()].caption}',
                style: const TextStyle(color: Colors.white, fontFamily: 'Roboto', fontSize: 12)),
            textDirection: TextDirection.ltr,
            maxLines: 4,
          )..layout(maxWidth: 310);
          label.paint(canvas, const Offset(5, 290));
          label.dispose();
          canvas.restore();
        }
        final picture = recorder.endRecording();
        await tester.runAsync(() async {
          final image = await picture.toImage(320 * figures.length, 360);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${directory.path}/${frame.toString().padLeft(4, '0')}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        picture.dispose();
        samples.add({'frame': frame, 'timestampSeconds': frame / fps, 'figures': frameFigures});
      }
      manifest.add({
        'names': groups[group],
        'clip': group + 1,
        if (part != null) 'selectedPart': 3,
        if (part != null) 'partBounds': [part.start, part.end, part.startTime, part.endTime],
        'fps': fps,
        'frames': count,
        'seconds': duration,
        'path': directory.path,
        'sourceCommit': sourceCommit,
        'samples': samples,
        'timeline': 'figureMotionProgress production, real seconds; shorter paired cycle explicitly paused at end'
      });
    }
    File('$animationOutput/manifest-$selectedGroup.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  }, skip: animationOutput == null);
}
