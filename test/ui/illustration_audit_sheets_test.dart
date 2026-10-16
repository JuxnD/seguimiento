import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/catalog_updates.dart';
import 'package:seguimiento/data/exercise_details.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/mobility.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';

import '../support/test_fonts.dart';

/// Auditoría 052 (opt-in con AUDIT_OUT; AUDIT_NAMES=«a;b» filtra): una hoja
/// por figura con sus momentos desde la cámara inicial y de perfil, y los
/// textos de su guía, para revisar a ojo que la figura coincida con ella.
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
    // Las guías del catálogo (Burpees, Plancha lateral…) viven en la base.
    for (final g in exerciseGuides) {
      add(g.name, g.formCues);
    }
    final index = <Map<String, Object?>>[];
    final only = Platform.environment['AUDIT_NAMES']?.split(';').toSet();
    for (final (i, fig) in catalog.all.indexed) {
      if (only != null && !only.contains(fig.name)) continue;
      final detail = exerciseDetail(fig.name);
      final guide = [...?detail?.steps, ...?cues[fig.name]];
      // Animadas: 6 puntos repartidos (incluye lo que se ve entre momentos);
      // fijas: sus momentos.
      // AUDIT_KEYS=1: sólo los momentos clave (hasta 6).
      final keys = Platform.environment['AUDIT_KEYS'] == '1';
      final samples = keys && fig.frames.length > 1
          ? [for (var k = 0; k < fig.frames.length && k < 6; k++) k / (fig.frames.length - 1)]
          : fig.continuous && fig.frames.length > 1
          ? [for (var k = 0; k < 6; k++) k / 5]
          : fig.frames.length == 1
              ? [0.0]
              : [for (var k = 0; k < fig.frames.length && k < 6; k++) k / (fig.frames.length - 1)];
      const tile = Size(260, 300);
      // AUDIT_TOP=1 suma una fila casi cenital (para posturas en el suelo).
      final top = Platform.environment['AUDIT_TOP'] == '1';
      final angles = [fig.initialYaw, fig.initialYaw + 90, if (top) fig.initialYaw];
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
          Figure3DPainter(fig, p, yaw: yaw, pitch: row == 2 ? 70 : fig.initialPitch).paint(canvas, const Size(260, 230));
          canvas.restore();
          final caption = TextPainter(
              text: TextSpan(
                  text: 'p=${p.toStringAsFixed(2)} yaw=${yaw.round()}${row == 2 ? ' desde arriba' : ''}\n'
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
        final image = await picture.toImage((tile.width * 6).round(), (110 + tile.height * angles.length).round());
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
        // Articulaciones en cada muestra (y hacia abajo, suelo en 0): para
        // medir apoyos y cruces sin depender sólo del ojo.
        'joints': [
          for (final p in samples)
            {
              'p': p,
              for (final e in liftSkeleton(fig.skeletonAt(p), fig).p.entries)
                e.key: [for (final v in [e.value.x, e.value.y, e.value.z]) (v * 10).round() / 10],
            }
        ],
      });
    }
    File('${dir.path}/index.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(index));
  }, skip: out == null, timeout: const Timeout(Duration(minutes: 20)));
}
