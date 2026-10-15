import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/exercise_details.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/mobility.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';

import '../support/test_fonts.dart';

/// Auditoría 052 (temporal, no va al repositorio): una hoja por figura con
/// sus momentos desde la cámara inicial y de perfil, y los textos de su guía.
void main() {
  final out = Platform.environment['AUDIT_OUT'];
  testWidgets('auditoría de figuras contra la guía', (tester) async {
    await loadTestFonts(tester);
    final dir = Directory(out!)..createSync(recursive: true);
    final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
    final cues = <String, Set<String>>{};
    void add(String name, Iterable<String> lines) => cues.putIfAbsent(name, () => {}).addAll(lines);
    for (final routine in [mobilityNight, legRecovery, morningActiva(), nightSuelta(withLegs: true), recoveryActive()]) {
      for (final e in routine.exercises) {
        add(e.name, e.formCues);
      }
    }
    for (final e in [...legsModule, ...recoveryActivation]) {
      add(e.name, e.formCues);
    }
    final index = <Map<String, Object?>>[];
    final only = Platform.environment['AUDIT_NAMES']?.split(';').toSet();
    for (final (i, fig) in catalog.all.indexed) {
      if (only != null && !only.contains(fig.name)) continue;
      final detail = exerciseDetail(fig.name);
      final guide = [...?detail?.steps, ...?cues[fig.name]];
      // Animadas: 6 puntos repartidos (incluye lo que se ve entre momentos);
      // fijas: sus momentos.
      final samples = fig.continuous && fig.frames.length > 1
          ? [for (var k = 0; k < 6; k++) k / 5]
          : fig.frames.length == 1
              ? [0.0]
              : [for (var k = 0; k < fig.frames.length && k < 6; k++) k / (fig.frames.length - 1)];
      const tile = Size(260, 300);
      final angles = [fig.initialYaw, fig.initialYaw + 90];
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xff0b0806), BlendMode.src);
      final header = TextPainter(
          text: TextSpan(
              text: '${i + 1}. ${fig.name}\nGUÍA: ${guide.join(' | ')}',
              style: const TextStyle(color: Colors.white, fontFamily: 'Roboto', fontSize: 13)),
          textDirection: TextDirection.ltr,
          maxLines: 6)
        ..layout(maxWidth: tile.width * 6 - 10);
      header.paint(canvas, const Offset(5, 4));
      header.dispose();
      for (final (row, yaw) in angles.indexed) {
        for (final (col, p) in samples.indexed) {
          canvas.save();
          canvas.translate(col * tile.width, 110 + row * tile.height);
          canvas.save();
          Figure3DPainter(fig, p, yaw: yaw, pitch: fig.initialPitch).paint(canvas, const Size(260, 230));
          canvas.restore();
          final caption = TextPainter(
              text: TextSpan(
                  text: 'p=${p.toStringAsFixed(2)} yaw=${yaw.round()}\n'
                      '${fig.hasMotion ? figureMotionCaption(fig, p) : fig.frames[(p * (fig.frames.length - 1)).round()].caption}',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'Roboto', fontSize: 11)),
              textDirection: TextDirection.ltr,
              maxLines: 4)
            ..layout(maxWidth: tile.width - 6);
          caption.paint(canvas, const Offset(3, 232));
          caption.dispose();
          canvas.restore();
        }
      }
      final picture = recorder.endRecording();
      final file = '${(i + 1).toString().padLeft(3, '0')}.png';
      await tester.runAsync(() async {
        final image = await picture.toImage((tile.width * 6).round(), (110 + tile.height * 2).round());
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/$file').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      picture.dispose();
      index.add({
        'file': file,
        'name': fig.name,
        'motion': fig.hasMotion,
        'frames': [for (final f in fig.frames) f.caption],
        'guide': guide,
        'mistakes': detail?.mistakes ?? const [],
      });
    }
    File('${dir.path}/index.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(index));
  }, skip: out == null, timeout: const Timeout(Duration(minutes: 20)));
}
