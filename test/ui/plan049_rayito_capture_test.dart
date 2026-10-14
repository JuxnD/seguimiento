import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/mascot.dart';
import 'package:seguimiento/ui/mascot.dart';

import '../support/test_fonts.dart';

/// Plan 049: captura real de Flutter con las 8 fases y los 4 estados del día
/// de Rayito, para la auditoría que pidió el owner. Escribe
/// build/qa/051/rayito-fonts-v3.png; sólo falla si el dibujo lanza un error o la imagen
/// sale vacía. La aceptación visual es humana.
void main() {
  for (final rayitoSize in [24.0, 40.0, 76.0]) {
    testWidgets('hoja de Rayito: 8 fases y 4 estados a $rayitoSize px',
        (tester) async {
      await loadTestFonts(tester, realDefaultFont: true);
      tester.view.physicalSize = const Size(760, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      Widget cell(MascotPhase p, MascotMood m, String label) => SizedBox(
            width: 180,
            height: 150,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: mascotCarbon, borderRadius: BorderRadius.circular(14)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Rayito(phase: p, mood: m, size: rayitoSize),
                  Text(label,
                      style: const TextStyle(
                          inherit: false,
                          decoration: TextDecoration.none,
                          color: mascotIvory,
                          fontSize: 12,
                          fontFamily: 'Roboto')),
                ],
              ),
            ),
          );
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: mascotIvory,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in MascotPhase.values)
                  cell(
                      p,
                      p == MascotPhase.dormido
                          ? MascotMood.dormido
                          : MascotMood.contento,
                      '${p.label} · ${p.fromDays}+'),
                for (final m in MascotMood.values)
                  cell(MascotPhase.energizado, m, 'Energizado · ${m.name}'),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(10000),
          reason: 'la hoja no puede salir vacía');
      final out = File('build/qa/051/rayito-${rayitoSize.toInt()}px.png')
        ..createSync(recursive: true);
      out.writeAsBytesSync(bytes);
    });
  }
}
