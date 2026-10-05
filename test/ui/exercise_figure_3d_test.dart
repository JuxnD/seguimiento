import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/features/training/technique_sheet.dart';
import 'package:seguimiento/ui/exercise_art.dart';
import 'package:seguimiento/ui/exercise_figure.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';

/// Maniquí 3D: la matemática pura (paso a 3D, proyección, interpolación,
/// orden de pintado) y cómo se presenta en la hoja de técnica.
void main() {
  final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
  final art2d = ExerciseArtCatalog.fromJsonString(File(ExerciseArtCatalog.asset).readAsStringSync());
  const dims = BodyDims();

  double dist(Offset a, Offset b) => (a - b).distance;

  group('datos', () {
    test('los tres ejercicios de la iteración, con inicio, medio y final', () {
      for (final name in ['Pino pecho a la pared', 'Nórdico (isquios)', 'Dominadas']) {
        final fig = catalog.forExercise(name);
        expect(fig, isNotNull, reason: name);
        expect(fig!.frames, hasLength(3));
        expect(fig.regions, isNotEmpty, reason: 'el naranja señala un músculo');
        expect([for (var i = 0; i < 3; i++) momentLabel(fig, i)], ['Inicio', 'Medio', 'Final']);
      }
      expect(catalog.forExercise('  nordico (ISQUIOS) ')?.name, 'Nórdico (isquios)');
      expect(catalog.forExercise('Flexiones'), isNull);
    });

    test('los momentos clave reproducen los apoyos del generador', () {
      for (final fig in catalog.all) {
        for (final (i, f) in fig.frames.indexed) {
          final s = solveKeyPose(f, fig.dims);
          for (final MapEntry(key: name, value: limb) in f.limbs.entries) {
            final pin = limb.pin;
            if (pin == null) continue;
            final end = s.joints[name.replaceAll('Leg', 'Ankle').replaceAll('Arm', 'Hand')]!;
            expect(dist(end, pin), lessThan(0.4), reason: '${fig.name} $i $name');
          }
        }
      }
    });
  });

  group('interpolación', () {
    test('lerpAngle va por el camino corto', () {
      expect(lerpAngle(170, -170, 0.5), closeTo(180, 1e-9));
      expect(lerpAngle(-90, 90, 0), -90);
      expect(lerpAngle(10, 50, 0.25), closeTo(20, 1e-9));
    });

    test('en los extremos coincide con los momentos clave', () {
      for (final fig in catalog.all) {
        for (final (i, f) in fig.frames.indexed) {
          final key = solveKeyPose(f, fig.dims).grounded();
          final at = fig.skeletonAt(fig.frames.length < 2 ? 0 : i / (fig.frames.length - 1));
          for (final e in key.joints.entries) {
            expect(dist(at.joints[e.key]!, e.value), lessThan(0.05), reason: '${fig.name} $i ${e.key}');
          }
        }
      }
    });

    test('a mitad de camino los segmentos conservan su largo', () {
      for (final fig in catalog.all) {
        for (var k = 1; k < 20; k++) {
          final j = fig.skeletonAt(k / 20).joints;
          for (final side in ['near', 'far']) {
            expect(dist(j['hip']!, j['${side}Knee']!), closeTo(dims.thigh, 0.01));
            expect(dist(j['${side}Knee']!, j['${side}Ankle']!), closeTo(dims.shin, 0.01));
            expect(dist(j['${side}Ankle']!, j['${side}Toe']!), closeTo(dims.foot, 0.01));
          }
          expect(dist(j['hip']!, j['neck']!), closeTo(dims.torso, 0.01));
        }
      }
    });

    test('las manos no se sueltan de la barra al animar la dominada', () {
      final fig = catalog.forExercise('Dominadas')!;
      for (var k = 0; k <= 20; k++) {
        final j = fig.skeletonAt(k / 20).joints;
        expect(dist(j['nearHand']!, const Offset(4, -68)), lessThan(0.05), reason: 't=${k / 20}');
      }
    });

    test('en el nórdico la cadera gira alrededor de las rodillas, que no se mueven', () {
      final fig = catalog.forExercise('Nórdico (isquios)')!;
      final knee0 = fig.skeletonAt(0).joints['nearKnee']!;
      for (var k = 0; k <= 20; k++) {
        expect(dist(fig.skeletonAt(k / 20).joints['nearKnee']!, knee0), lessThan(0.05));
      }
    });

    test('nada atraviesa el suelo en ningún punto del recorrido', () {
      for (final fig in catalog.all) {
        for (var k = 0; k <= 40; k++) {
          expect(fig.skeletonAt(k / 40).lowest, lessThanOrEqualTo(0.06), reason: '${fig.name} t=${k / 40}');
        }
      }
      // Colgado de la barra, las puntas de los pies quedan bien arriba del suelo.
      final pull = catalog.forExercise('Dominadas')!;
      for (var k = 0; k <= 20; k++) {
        final j = pull.skeletonAt(k / 20).joints;
        expect(j['nearToe']!.dy, lessThan(-8));
        expect(j['farToe']!.dy, lessThan(-8));
      }
    });

    test('loopProgress va y vuelve con pausas en cada momento', () {
      expect(loopProgress(0, 3), 0);
      expect(loopProgress(0.5, 3), 0, reason: 'pausa inicial');
      expect(loopProgress(0.6 + 1.2 + 0.1, 3), closeTo(0.5, 1e-9), reason: 'pausa en el medio');
      expect(loopProgress(0.6 + 1.8 + 1.2 + 0.1, 3), closeTo(1, 1e-9), reason: 'pausa al final');
      expect(loopProgress(0.6 + 1.2 / 2, 3), closeTo(0.25, 1e-9));
      const cycle = 0.6 + 4 * 1.8;
      expect(loopProgress(cycle - 0.01, 3), closeTo(0, 1e-9), reason: 'vuelve al inicio');
      expect(loopProgress(cycle + 0.3, 3), 0);
    });
  });

  group('paso a 3D', () {
    test('el lado cercano va a +z y el lejano a -z; las manos al ancho del agarre', () {
      final fig = catalog.forExercise('Dominadas')!;
      final b = liftSkeleton(fig.skeletonAt(0), fig);
      expect(b.p['nearShoulder']!.z, BodyDims.shoulderHalf);
      expect(b.p['farShoulder']!.z, -BodyDims.shoulderHalf);
      expect(b.p['nearHip']!.z, BodyDims.hipHalf);
      expect(b.p['nearHand']!.z, fig.gripZ);
      expect(b.p['farHand']!.z, -fig.gripZ);
      expect(b.p['hip']!.z, 0);
    });

    test('las extremidades conservan su largo en 3D y los codos salen hacia afuera', () {
      final fig = catalog.forExercise('Dominadas')!;
      for (var k = 0; k <= 10; k++) {
        final b = liftSkeleton(fig.skeletonAt(k / 10), fig);
        for (final side in ['near', 'far']) {
          final sh = b.p['${side}Shoulder']!, e = b.p['${side}Elbow']!, h = b.p['${side}Hand']!;
          expect((e - sh).length, closeTo(dims.upperArm, 0.02));
          expect((h - e).length, closeTo(dims.forearm, 0.3));
          expect((b.p['${side}Knee']! - b.p['${side}Hip']!).length, closeTo(dims.thigh, 1e-6));
        }
        final mid = k / 10;
        if (mid >= 0.5) {
          expect(b.p['nearElbow']!.z, greaterThan(BodyDims.shoulderHalf), reason: 'codo abierto, t=$mid');
          expect(b.p['farElbow']!.z, lessThan(-BodyDims.shoulderHalf));
        }
      }
    });

    test('ikJoint respeta largos y sale hacia el polo', () {
      const root = V3(0, 0, 0), end = V3(10, 0, 0);
      final m = ikJoint(root, end, 7, 7, const V3(0, -1, 0));
      expect((m - root).length, closeTo(7, 1e-9));
      expect((end - m).length, closeTo(7, 1e-9));
      expect(m.y, lessThan(0));
      expect(m.x, closeTo(5, 1e-9));
    });

    test('la cara flexora del muslo arrodillado mira hacia atrás (isquios)', () {
      final fig = catalog.forExercise('Nórdico (isquios)')!;
      final b = liftSkeleton(fig.skeletonAt(0), fig);
      final f = b.flexor['nearThigh']!;
      expect(f.x, lessThan(-0.9), reason: 'el cuerpo mira a +x; los isquios, a -x');
      expect(b.face.x, greaterThan(0.9), reason: 'la cara mira hacia adelante');
    });

    test('en el pino el pecho y la cara miran a la pared', () {
      final fig = catalog.forExercise('Pino pecho a la pared')!;
      final b = liftSkeleton(fig.skeletonAt(1), fig);
      expect(b.front.x, lessThan(-0.9), reason: 'la pared está en x = 0, a la izquierda');
      expect(b.face.x, lessThan(-0.8));
    });
  });

  group('cámara', () {
    Camera3D cam({double yaw = 0, double pitch = 0}) => Camera3D(
          yawDeg: yaw,
          pitchDeg: pitch,
          center: const V3(10, -20, 0),
          scale: 4,
          size: const Size(400, 300),
        );

    test('el centro cae en el centro de la pantalla y lo cercano se ve más grande', () {
      final c = cam();
      final p = c.project(const V3(10, -20, 0));
      expect(p.offset.dx, closeTo(200, 1e-9));
      expect(p.offset.dy, closeTo(150, 1e-9));
      expect(p.k, closeTo(4, 1e-9));
      final nearP = c.project(const V3(10, -20, 5)), farP = c.project(const V3(10, -20, -5));
      expect(nearP.k, greaterThan(farP.k));
      expect(nearP.z, greaterThan(farP.z));
      // De perfil, +x queda a la derecha y "abajo" (y mayor) abajo.
      expect(c.project(const V3(20, -20, 0)).offset.dx, greaterThan(200));
      expect(c.project(const V3(10, -10, 0)).offset.dy, greaterThan(150));
    });

    test('girar 90° pone el eje x de frente a la cámara', () {
      final c = cam(yaw: 90);
      final p = c.project(const V3(20, -20, 0));
      expect(p.offset.dx, closeTo(200, 1e-6));
      expect(p.z, closeTo(10, 1e-6));
      expect(c.faces(const V3(10, -20, 0), const V3(1, 0, 0)), isTrue);
      expect(c.faces(const V3(10, -20, 0), const V3(-1, 0, 0)), isFalse);
    });

    test('inclinar mira desde arriba: se ve el suelo y la profundidad horizontal no cambia con la altura', () {
      final c = cam(pitch: 20);
      expect(c.faces(const V3(10, 0, 0), const V3(0, -1, 0)), isTrue, reason: 'cara de arriba de algo en el suelo');
      expect(c.depth(const V3(10, -50, 3)), closeTo(c.depth(const V3(10, 0, 3)), 1e-9));
      expect(c.position.y, lessThan(-20));
    });
  });

  group('orden de pintado', () {
    test('de lejos a cerca, y los empates en el orden de llegada', () {
      final parts = [
        DepthPart(2, () {}, 'cerca'),
        DepthPart(-3, () {}, 'lejos'),
        DepthPart(0, () {}, 'torso'),
        DepthPart(0, () {}, 'cabeza'),
      ];
      expect(sortByDepth(parts).map((p) => p.label), ['lejos', 'torso', 'cabeza', 'cerca']);
    });

    test('de perfil, el brazo cercano se pinta después del torso y el lejano antes', () {
      final fig = catalog.forExercise('Pino pecho a la pared')!;
      final b = liftSkeleton(fig.skeletonAt(0.5), fig);
      final c = cameraFor(fig, const Size(360, 260), yaw: 0, pitch: defaultPitch);
      double z(String k) => c.view(b.p[k]!).z;
      final order = sortByDepth([
        DepthPart((z('nearShoulder') + z('nearElbow')) / 2, () {}, 'cerca'),
        DepthPart((z('hip') + z('neck')) / 2, () {}, 'torso'),
        DepthPart((z('farShoulder') + z('farElbow')) / 2, () {}, 'lejos'),
      ]);
      expect(order.map((p) => p.label), ['lejos', 'torso', 'cerca']);
    });
  });

  testWidgets('las tres figuras se pintan sin errores, giradas o no', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final fig in catalog.all) {
      for (final (p, yaw) in const [(0.0, null), (0.5, -60.0), (1.0, 60.0)]) {
        await tester.pumpWidget(Center(
          child: SizedBox(
            width: 340,
            height: 260,
            child: CustomPaint(painter: Figure3DPainter(fig, p, yaw: yaw)),
          ),
        ));
        expect(tester.takeException(), isNull, reason: '${fig.name} $p $yaw');
      }
    }
  });

  group('hoja de técnica', () {
    Future<void> pumpSheet(WidgetTester tester, String exercise) async {
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
        child: MaterialApp(home: Scaffold(body: TechniqueContent(exercise: exercise))),
      ));
      await tester.pump();
    }

    testWidgets('con figura 3D: tres momentos grandes que se pasan de lado', (tester) async {
      await pumpSheet(tester, 'Nórdico (isquios)');
      final fig = catalog.forExercise('Nórdico (isquios)')!;
      final pages = find.byKey(const ValueKey('figura3d-momentos'));
      expect(pages, findsOneWidget);
      final view = tester.widget<PageView>(pages);
      expect((view.childrenDelegate as SliverChildBuilderDelegate).childCount, 3);
      expect(find.byType(ExerciseArtFrames), findsNothing, reason: 'no repite la figura plana');
      expect(find.text('1/3 · ${fig.frames[0].caption}'), findsOneWidget);
      // Casi todo el ancho y ~260 de alto.
      final frame = tester.getSize(find.byKey(const ValueKey('figura3d-0')));
      expect(frame.width, greaterThan(280));
      expect(frame.height, figure3dHeight);
      expect(find.textContaining(fig.muscles), findsOneWidget);

      await tester.drag(pages, const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(find.text('2/3 · ${fig.frames[1].caption}'), findsOneWidget);
      await tester.drag(pages, const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(find.text('3/3 · ${fig.frames[2].caption}'), findsOneWidget);
    });

    testWidgets('"Ver movimiento" anima en el mismo cuadro y vuelve a los momentos', (tester) async {
      await pumpSheet(tester, 'Nórdico (isquios)');
      await tester.tap(find.text('Ver movimiento'));
      await tester.pump();
      expect(find.byKey(const ValueKey('figura3d-momentos')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Ver momentos'));
      await tester.pump();
      expect(find.byKey(const ValueKey('figura3d-momentos')), findsOneWidget);
    });

    testWidgets('tocar un momento lo abre en grande; arrastrar gira y se vuelve de perfil', (tester) async {
      await pumpSheet(tester, 'Dominadas');
      final fig = catalog.forExercise('Dominadas')!;
      await tester.tap(find.byKey(const ValueKey('figura3d-0')));
      await tester.pumpAndSettle();
      expect(find.byType(Figure3DFullScreen), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Inicio'), findsOneWidget);
      expect(find.text('De perfil'), findsNothing);

      await tester.drag(find.byKey(const ValueKey('figura3d-giro')), const Offset(400, 0));
      await tester.pump();
      final painter = tester
          .widgetList<CustomPaint>(
              find.descendant(of: find.byKey(const ValueKey('figura3d-giro')), matching: find.byType(CustomPaint)))
          .map((c) => c.painter)
          .whereType<Figure3DPainter>()
          .single;
      expect(painter.yaw, maxYaw, reason: 'el giro se limita a ±60°');
      expect(find.text('De perfil'), findsOneWidget);

      await tester.tap(find.text('De perfil'));
      await tester.pump();
      expect(find.text('De perfil'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Final'));
      await tester.pumpAndSettle();
      expect(find.text(fig.frames[2].caption), findsOneWidget);
    });

    testWidgets('sin figura 3D, la figura plana de siempre', (tester) async {
      await pumpSheet(tester, 'Flexiones');
      expect(find.byKey(const ValueKey('figura3d-momentos')), findsNothing);
      expect(find.byType(ExerciseArtFrames), findsOneWidget);
      expect(find.text('Ver movimiento'), findsNothing);
    });
  });

  test('el giro máximo es simétrico y la vista inicial cabe en él', () {
    for (final fig in catalog.all) {
      expect(fig.initialYaw.abs(), lessThanOrEqualTo(maxYaw));
      expect(fig.initialPitch, inInclusiveRange(0, 35));
    }
  });
}
