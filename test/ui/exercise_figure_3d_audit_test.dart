import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/exercise_details.dart';
import 'package:seguimiento/features/training/technique_sheet.dart';
import 'package:seguimiento/ui/exercise_art.dart';
import 'package:seguimiento/ui/exercise_figure.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/test_fonts.dart';

/// Hallazgos de la auditoría del 5 oct (F01–F04): el pino no atraviesa la
/// pared, la dominada respeta la variante de la sesión, el pie de los
/// momentos cabe con texto grande y ampliar conserva la pose animada.
void main() {
  final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
  final art2d = ExerciseArtCatalog.fromJsonString(File(ExerciseArtCatalog.asset).readAsStringSync());

  group('F01: el pino no atraviesa la pared', () {
    final fig = catalog.forExercise('Pino pecho a la pared')!;
    final wallX = (fig.props.singleWhere((p) => p['type'] == 'wall')['x'] as num).toDouble();

    // Volumen de cada articulación: el centro no basta (zapato, cabeza).
    double pad(String joint) => joint == 'head'
        ? fig.dims.headRadius
        : joint.endsWith('Ankle')
            ? 0.9
            : joint.endsWith('Toe')
                ? 0.6
                : joint.endsWith('Knee')
                    ? 1.3
                    : joint.endsWith('Hand')
                        ? 0.5
                        : 0.0;

    test('el caso de la auditoría: tobillo a 0,75 delante de la cara de la pared', () {
      final ankle = fig.skeletonAt(0.75).joints['nearAnkle']!;
      expect(ankle.dx, greaterThanOrEqualTo(wallX));
    });

    test('ninguna articulación cruza la pared en todo el recorrido (pasos de 0,01)', () {
      for (var k = 0; k <= 100; k++) {
        final s = fig.skeletonAt(k / 100);
        for (final MapEntry(key: name, value: p) in s.joints.entries) {
          expect(p.dx - pad(name), greaterThanOrEqualTo(wallX - 0.05), reason: 't=${k / 100} $name x=${p.dx}');
        }
      }
    });

    test('los pies siguen apoyados en la pared mientras suben (de la L al pino)', () {
      for (var k = 0; k <= 100; k++) {
        final t = k / 100;
        final j = fig.skeletonAt(t).joints;
        for (final side in ['near', 'far']) {
          final toe = j['${side}Toe']!;
          expect(toe.dx - wallX, lessThan(3.0), reason: 'la punta toca la pared, t=$t');
        }
      }
    });

    test('la animación es continua: a 60 fps nada salta de un cuadro al siguiente', () {
      // Se mide en el tiempo de la animación (con su aceleración), que es lo
      // que se ve: al salir de la L la pierna recta sube rápido al principio
      // del tramo, pero el bucle arranca despacio.
      for (final f in catalog.all) {
        var prev = f.skeletonAt(0).joints;
        for (var frame = 1; frame < 60 * 8; frame++) {
          final p = loopProgress(frame / 60, f.frames.length);
          final j = f.skeletonAt(p).joints;
          for (final e in j.entries) {
            expect((e.value - prev[e.key]!).distance, lessThan(1.5), reason: '${f.name} p=$p ${e.key}');
          }
          prev = j;
        }
      }
    });

    test('ninguna figura con pared la atraviesa', () {
      for (final f in catalog.all) {
        for (final wall in f.props.where((p) => p['type'] == 'wall')) {
          final x = (wall['x'] as num).toDouble();
          for (var k = 0; k <= 100; k++) {
            for (final p in f.skeletonAt(k / 100).joints.values) {
              expect(p.dx, greaterThanOrEqualTo(x - 0.05), reason: '${f.name} t=${k / 100}');
            }
          }
        }
      }
    });
  });

  group('F02: la dominada respeta la variante de la sesión', () {
    final pull = catalog.forExercise('Dominadas')!;

    test('la figura 3D es prona con mochila y solo coincide con esa variante', () {
      expect(pull.matches(), isTrue, reason: 'sin contexto (catálogo) se muestra');
      expect(pull.matches(grip: 'prona', loaded: true), isTrue);
      expect(pull.matches(grip: 'Prono', loaded: true), isTrue);
      expect(pull.matches(loaded: true), isTrue, reason: 'agarre sin especificar y con carga');
      expect(pull.matches(grip: 'supina', loaded: true), isFalse);
      expect(pull.matches(grip: 'supina'), isFalse);
      expect(pull.matches(grip: 'prona', loaded: false), isFalse, reason: 'circuito del viernes: sin mochila');
      expect(pull.matches(loaded: false), isFalse);
      // Las demás figuras no dependen de la variante.
      expect(catalog.forExercise('Nórdico (isquios)')!.matches(grip: 'supina', loaded: false), isTrue);
    });

    test('el detalle escrito no da por hecha la mochila si la sesión va sin carga', () {
      final d = exerciseDetail('Dominadas')!;
      expect(d.stepsFor(loaded: false).where((s) => s.toLowerCase().contains('mochila')), isEmpty);
      expect(d.easierFor(loaded: false)?.toLowerCase(), isNot(contains('mochila')));
      // Con carga o sin contexto, el paso de la mochila sigue, dicho como condición.
      final loaded = d.stepsFor(loaded: true);
      expect(loaded.first, startsWith('Si va con mochila'));
      expect(d.stepsFor(), loaded);
    });

    Future<void> pumpSheet(WidgetTester tester, {String? grip, bool? loaded}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          figure3dProvider.overrideWith((ref) => catalog),
          exerciseArtProvider.overrideWith((ref) => art2d),
          exercisePhotoProvider.overrideWith((ref, _) => Stream.value(null)),
          documentsDirProvider.overrideWith((ref) => Directory.systemTemp),
        ],
        child: MaterialApp(
            home: Scaffold(body: TechniqueContent(exercise: 'Dominadas', grip: grip, loaded: loaded))),
      ));
      await tester.pump();
    }

    testWidgets('supina sin carga (jueves): figura plana y nada de mochila', (tester) async {
      await pumpSheet(tester, grip: 'supina', loaded: false);
      expect(find.byKey(const ValueKey('figura3d-momentos')), findsNothing);
      expect(find.byType(ExerciseArtFrames), findsOneWidget);
      expect(find.textContaining('mochila'), findsNothing);
    });

    testWidgets('prona sin carga (circuito): figura plana', (tester) async {
      await pumpSheet(tester, grip: 'prona', loaded: false);
      expect(find.byKey(const ValueKey('figura3d-momentos')), findsNothing);
      expect(find.byType(ExerciseArtFrames), findsOneWidget);
    });

    testWidgets('supina con carga: figura plana (la 3D es prona)', (tester) async {
      await pumpSheet(tester, grip: 'supina', loaded: true);
      expect(find.byKey(const ValueKey('figura3d-momentos')), findsNothing);
      expect(find.byType(ExerciseArtFrames), findsOneWidget);
    });

    testWidgets('prona con mochila (lunes): el maniquí 3D', (tester) async {
      await pumpSheet(tester, grip: 'prona', loaded: true);
      expect(find.byKey(const ValueKey('figura3d-momentos')), findsOneWidget);
      expect(find.byType(ExerciseArtFrames), findsNothing);
      expect(find.textContaining('Si va con mochila'), findsOneWidget);
    });

    testWidgets('sin contexto (catálogo): el maniquí 3D', (tester) async {
      await pumpSheet(tester);
      expect(find.byKey(const ValueKey('figura3d-momentos')), findsOneWidget);
    });
  });

  group('F03 y F04: momentos a 360 px', () {
    Future<void> mount(WidgetTester tester, Figure3D fig, {double scale = 1}) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadTestFonts(tester);
      final theme = buildGymTheme();
      await tester.pumpWidget(MaterialApp(
        theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(
          body: ListView(children: [
            Padding(padding: const EdgeInsets.all(20), child: Figure3DMoments(figure: fig)),
          ]),
        ),
      ));
      await tester.pump();
    }

    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('texto ×$scale: se leen todos los pies sin desbordar', (tester) async {
        for (final fig in catalog.all) {
          await mount(tester, fig, scale: scale);
          for (var i = 0; i < fig.frames.length; i++) {
            if (i > 0) {
              await tester.drag(find.byKey(const ValueKey('figura3d-momentos')), const Offset(-310, 0));
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull, reason: '${fig.name}, escala $scale, momento $i');
            expect(find.text('${i + 1}/${fig.frames.length} · ${fig.frames[i].caption}'), findsOneWidget);
          }
          // Animado, el pie tampoco desborda.
          await tester.tap(find.text('Ver movimiento'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          expect(tester.takeException(), isNull, reason: '${fig.name} animado, escala $scale');
          await tester.tap(find.text('Ver momentos'));
          await tester.pump();
        }
      });
    }

    testWidgets('ampliar una animación conserva el momento que se estaba viendo', (tester) async {
      await mount(tester, catalog.forExercise('Nórdico (isquios)')!);
      await tester.tap(find.text('Ver movimiento'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      final paint = tester.widget<CustomPaint>(find.descendant(
          of: find.byKey(const ValueKey('figura3d-animada')), matching: find.byType(CustomPaint)));
      final progress = (paint.painter! as Figure3DPainter).progress;
      expect(progress, closeTo(0.5, 0.001), reason: 'a los 2 s el bucle está en la pausa del medio');
      await tester.tap(find.byTooltip('Ampliar y girar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final full = tester.widget<Figure3DFullScreen>(find.byType(Figure3DFullScreen));
      expect(full.initialProgress, closeTo(progress, 0.001));
      final shown = tester
          .widgetList<CustomPaint>(
              find.descendant(of: find.byKey(const ValueKey('figura3d-giro')), matching: find.byType(CustomPaint)))
          .map((c) => c.painter)
          .whereType<Figure3DPainter>()
          .single;
      expect(shown.progress, closeTo(progress, 0.001), reason: 'la pantalla completa pinta esa misma pose');
    });

    testWidgets('ampliar en una transición conserva la pose intermedia', (tester) async {
      await mount(tester, catalog.forExercise('Pino pecho a la pared')!);
      await tester.tap(find.text('Ver movimiento'));
      await tester.pump();
      // 0,6 s de pausa y la mitad del primer tramo.
      await tester.pump(const Duration(milliseconds: 1200));
      final paint = tester.widget<CustomPaint>(find.descendant(
          of: find.byKey(const ValueKey('figura3d-animada')), matching: find.byType(CustomPaint)));
      final progress = (paint.painter! as Figure3DPainter).progress;
      expect(progress, inExclusiveRange(0.05, 0.45));
      await tester.tap(find.byTooltip('Ampliar y girar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Figure3DFullScreen>(find.byType(Figure3DFullScreen)).initialProgress,
          closeTo(progress, 0.001));
    });
  });
}
