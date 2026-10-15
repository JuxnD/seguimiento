import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';

void main() {
  final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
  const selected = [
    '90/90 de cadera',
    'Aceleración 10–20 m',
    'Burpees',
    'Calentamiento tipo FIFA 11+',
    'Barca / V-sit',
    'Vela',
    'Dragon flag'
  ];
  test('owner sequences are authored, with finite anatomy throughout every transition', () {
    for (final name in selected) {
      final fig = catalog.forExercise(name)!;
      expect(fig.motion.length, fig.frames.length - 1, reason: name);
      for (var segment = 0; segment < fig.motion.length; segment++) {
        for (var sample = 0; sample <= 60; sample++) {
          final p = (segment + sample / 60) / fig.motion.length;
          final body = liftSkeleton(fig.skeletonAt(p), fig);
          for (final side in ['near', 'far']) {
            for (final spec in [
              ('Shoulder', 'Elbow', 10.0),
              ('Elbow', 'Hand', 9.0),
              ('Hip', 'Knee', 14.0),
              ('Knee', 'Ankle', 14.0)
            ]) {
              final length = (body.p['$side${spec.$1}']! - body.p['$side${spec.$2}']!).length;
              expect(length.isFinite, isTrue, reason: '$name/$segment/$sample/$side');
              expect(length, closeTo(spec.$3, .4), reason: '$name/$segment/$sample/$side${spec.$2}');
            }
          }
        }
      }
    }
  });
  test('authored camera contains every key and intervening anatomical envelope', () {
    final clipped = <String>[];
    for (final name in selected) {
      final fig = catalog.forExercise(name)!;
      for (final size in [const Size(320, 285), const Size(360, 315), const Size(420, 600)]) {
        for (final yaw in {fig.initialYaw, 0.0, 90.0}) {
          final camera = cameraFor(fig, size, yaw: yaw, pitch: fig.initialPitch);
          for (var step = 0; step <= fig.motion.length * 30; step++) {
            final progress = step / (fig.motion.length * 30);
            final body = liftSkeleton(fig.skeletonAt(progress), fig);
            for (final entry in body.p.entries) {
              // Renderer fingers extend 4 units beyond the wrist + .24 capsule;
              // head/limb volumes must fit too, not merely their joint centers.
              final radius = entry.key.endsWith('Hand')
                  ? 4.3
                  : entry.key == 'head'
                      ? fig.dims.headRadius + .6
                      : entry.key.endsWith('Toe') || entry.key.endsWith('Ankle')
                          ? 1.2
                          : 2.5;
              final point = camera.project(entry.value);
              final pad = radius * point.k;
              if (point.offset.dx - pad < 0 ||
                  point.offset.dy - pad < 0 ||
                  point.offset.dx + pad > size.width ||
                  point.offset.dy + pad > size.height) {
                if (clipped.length < 20) {
                  clipped.add('$name $size yaw=$yaw p=$progress ${entry.key}: ${point.offset} pad=$pad');
                }
              }
            }
          }
        }
      }
    }
    expect(clipped, isEmpty);
  });
  test('declared fixed contacts stay fixed in world space, not just pixels', () {
    for (final name in selected) {
      final fig = catalog.forExercise(name)!;
      for (var i = 0; i < fig.motion.length; i++) {
        final stage = fig.motion[i];
        final first = liftSkeleton(fig.skeletonAt(i / fig.motion.length), fig);
        for (final contact in stage.contacts) {
          for (var s = 1; s < 60; s++) {
            final current = liftSkeleton(fig.skeletonAt((i + s / 60) / fig.motion.length), fig);
            expect((current.p[contact]! - first.p[contact]!).length, lessThan(.05), reason: '$name/$i/$contact/$s');
          }
        }
      }
    }
  });
  test('authored non-cut boundaries have continuous world joints on both sides of each key', () {
    final discontinuities = <String>[];
    for (final name in selected) {
      final fig = catalog.forExercise(name)!;
      for (var i = 1; i < fig.motion.length; i++) {
        if (fig.motion[i - 1].kind == 'cut' || fig.motion[i].kind == 'cut') continue;
        // A straight two-link chain approaches its key as sqrt(epsilon), not
        // linearly in geometric progress. Check the limit and the actual
        // playback clock independently; neither allows a finite IK jump.
        Map<String, double>? previous;
        for (final epsilon in [1e-6, 1e-8, 1e-10]) {
          final before = liftSkeleton(fig.skeletonAt((i - epsilon) / fig.motion.length), fig).p;
          final after = liftSkeleton(fig.skeletonAt((i + epsilon) / fig.motion.length), fig).p;
          final distances = <String, double>{};
          for (final joint in before.keys) {
            final distance = (after[joint]! - before[joint]!).length;
            distances[joint] = distance;
            final prior = previous?[joint];
            if (!distance.isFinite ||
                (epsilon == 1e-10 && distance >= .01) ||
                (prior != null && prior > 1e-6 && distance > prior * .2)) {
              discontinuities.add('$name/$i/$joint epsilon=$epsilon: $distance (prior=$prior)');
            }
          }
          previous = distances;
        }
        final time = fig.motion.take(i).fold<double>(0, (sum, stage) => sum + stage.seconds);
        final before = liftSkeleton(fig.skeletonAt(figureMotionProgress(fig, time - 1e-4)), fig).p;
        final after = liftSkeleton(fig.skeletonAt(figureMotionProgress(fig, time + 1e-4)), fig).p;
        for (final joint in before.keys) {
          final distance = (after[joint]! - before[joint]!).length;
          if (!distance.isFinite || distance >= .01) discontinuities.add('$name/$i/$joint playback: $distance');
        }
      }
    }
    expect(discontinuities, isEmpty);
  });
  test('FIFA lateral hops translate the pelvis and lift both feet between grounded landings', () {
    final fig = catalog.forExercise('Calentamiento tipo FIFA 11+')!;
    final first = fig.motion.indexWhere((stage) => stage.part == '9' && stage.kind != 'cut');
    // Auditoría 052: apoyo con pausa, empuje, despegue y vuelo; el cuadro
    // donde empieza «Aterriza…» es el punto más alto del salto.
    final peak = fig.motion.indexWhere((stage) => stage.part == '9' && stage.label.startsWith('Aterriza'));
    expect(peak, greaterThan(first));
    final start = liftSkeleton(fig.skeletonAt(first / fig.motion.length), fig).p;
    final airborne = liftSkeleton(fig.skeletonAt(peak / fig.motion.length), fig).p;
    final landing = liftSkeleton(fig.skeletonAt((peak + 1) / fig.motion.length), fig).p;
    expect((landing['hip']!.z - start['hip']!.z).abs(), greaterThan(8));
    expect(airborne['nearAnkle']!.y, lessThan(-4));
    expect(airborne['farAnkle']!.y, lessThan(-4));
    expect(start['nearAnkle']!.y, closeTo(-1, .05));
    expect(landing['farAnkle']!.y, closeTo(-1, .05));
  });
  test('FIFA lateral steps travel with planted support and a lifted following foot', () {
    final fixture = Platform.environment['ILLUSTRATION_035_STEP_FIXTURE'];
    final figures = fixture == null ? catalog : Figure3DCatalog.fromJsonString(File(fixture).readAsStringSync());
    final fig = figures.forExercise('Calentamiento tipo FIFA 11+')!;
    final indices = [
      for (var i = 0; i < fig.motion.length; i++)
        if (fig.motion[i].part == '3' && fig.motion[i].kind != 'cut') i
    ];
    final poses = [
      for (final i in [...indices, indices.last + 1]) liftSkeleton(fig.skeletonAt(i / fig.motion.length), fig).p
    ];
    double range(String joint) {
      final positions = poses.map((p) => p[joint]!.z).toList()..sort();
      return positions.last - positions.first;
    }

    expect(range('hip'), greaterThan(6));
    expect(range('nearAnkle'), greaterThan(6));
    expect(range('farAnkle'), greaterThan(6));
    for (final joint in ['nearAnkle', 'farAnkle']) {
      expect(poses.any((p) => p[joint]!.y < -4), isTrue, reason: '$joint must lift instead of dragging');
    }
    for (final i in indices) {
      final a = liftSkeleton(fig.skeletonAt(i / fig.motion.length), fig).p;
      final b = liftSkeleton(fig.skeletonAt((i + 1) / fig.motion.length), fig).p;
      final fixed = ['nearAnkle', 'farAnkle']
          .where((joint) => (a[joint]! - b[joint]!).length < .01 && (a[joint]!.y + 1).abs() < .01)
          .toList();
      expect(fixed, isNotEmpty, reason: 'A lateral step keeps at least one planted support');
      for (var s = 0; s <= 20; s++) {
        final p = liftSkeleton(fig.skeletonAt((i + s / 20) / fig.motion.length), fig).p;
        for (final joint in fixed) {
          expect((p[joint]! - a[joint]!).length, lessThan(.01), reason: 'world support $i/$joint/$s');
        }
      }
    }
  });
  test('required supports remain anchored even if stage metadata is removed', () {
    for (final spec in [
      ('Burpees', 1, 'nearHand'),
      ('Burpees', 1, 'farHand'),
      ('Burpees', 2, 'nearHand'),
      ('Burpees', 2, 'farHand'),
      ('Aceleración 10–20 m', 0, 'nearAnkle'),
      ('Aceleración 10–20 m', 4, 'farAnkle'),
      for (var i = 0; i < 8; i++) ('90/90 de cadera', i, 'hip'),
    ]) {
      final fig = catalog.forExercise(spec.$1)!;
      final anchor = liftSkeleton(fig.skeletonAt(spec.$2 / fig.motion.length), fig).p[spec.$3]!;
      for (var sample = 1; sample <= 60; sample++) {
        final body = liftSkeleton(fig.skeletonAt((spec.$2 + sample / 60) / fig.motion.length), fig);
        expect((body.p[spec.$3]! - anchor).length, lessThan(.05), reason: '$spec sample$sample');
      }
    }
  });
  test('burpee flight stays above the floor; it is not grounded back to a jump pose', () {
    final fig = catalog.forExercise('Burpees')!;
    final flight = fig.frames.indexWhere((f) => f.caption.startsWith('Vuelo'));
    final body = liftSkeleton(fig.skeletonAt(flight / (fig.frames.length - 1)), fig);
    expect(body.p['nearAnkle']!.y, lessThan(-5));
    expect(body.p['farAnkle']!.y, lessThan(-5));
  });
  test('running swing foot clears the floor while opposite foot supports', () {
    final fig = catalog.forExercise('Aceleración 10–20 m')!;
    for (final spec in [(0, 'far'), (4, 'near')]) {
      for (var sample = 0; sample <= 60; sample++) {
        final body = liftSkeleton(fig.skeletonAt((spec.$1 + sample / 60) / fig.motion.length), fig);
        expect(body.p['${spec.$2}Ankle']!.y, lessThan(-4));
      }
    }
  });
  test('FIFA exposes ten parts and cuts only between the parts', () {
    final fig = catalog.forExercise('Calentamiento tipo FIFA 11+')!;
    expect(fig.motion.map((s) => s.part).toSet().length, 10);
    expect(fig.motion.where((s) => s.kind == 'cut').length, 10); // nine changes + explicit restart
    for (var i = 0; i < fig.motion.length; i++) {
      if (fig.motion[i].kind != 'cut') continue;
      final a = fig.skeletonAt((i + .1) / fig.motion.length).joints;
      final b = fig.skeletonAt((i + .9) / fig.motion.length).joints;
      expect(b, a, reason: 'No morph between FIFA parts');
    }
    final plank = fig.motion.indexWhere((stage) => stage.part == '4' && stage.kind == 'hold');
    final frontSupport = liftSkeleton(fig.skeletonAt((plank + .5) / fig.motion.length), fig).p;
    expect(frontSupport['nearHand']!.y, closeTo(-.75, .05));
    expect(frontSupport['farHand']!.y, closeTo(-.75, .05));
    final side = fig.motion.indexWhere((stage) => stage.part == '5' && stage.kind == 'hold');
    final sideSupport = liftSkeleton(fig.skeletonAt((side + .5) / fig.motion.length), fig).p;
    expect(sideSupport['nearElbow']!.y, inInclusiveRange(-2, -.5));
    // Toe support uses the existing .6 toe envelope; .9 belongs to ankles.
    expect(sideSupport['nearToe']!.y + jointPad('nearToe', fig.dims), closeTo(0, .05));
    final reference = catalog.forExercise('Plancha lateral')!;
    final referenceSupport = liftSkeleton(reference.skeletonAt(0), reference).p;
    expect((sideSupport['nearToe']! - referenceSupport['nearToe']!).length, lessThan(.01));
  });
  test('authored key boundaries preserve stage pose equipment and inverse time', () {
    final fig = catalog.forExercise('Calentamiento tipo FIFA 11+')!;
    final n = fig.motion.length;
    var time = 0.0;
    for (var i = 0; i < n; i++) {
      final exact = i / n;
      final before = (i - 1e-8) / n;
      final after = (i + 1e-8) / n;
      expect(fig.frameCoordinate(exact), i.toDouble(), reason: 'key $i/$n');
      expect(fig.stageAt(exact), same(fig.motion[i]));
      expect(fig.stageAt(after), same(fig.motion[i]));
      expect(fig.propsAt(exact), fig.frames[i].props ?? fig.props);
      expect(figureMotionTime(fig, exact), closeTo(time, 1e-8));
      if (i > 0) {
        expect(fig.frameCoordinate(before), lessThan(i));
        expect(fig.stageAt(before), same(fig.motion[i - 1]));
        expect(figureMotionTime(fig, before), lessThan(time));
        final priorProps = fig.motion[i - 1].kind == 'cut' ? i - 1 : i;
        expect(fig.propsAt(before), fig.frames[priorProps].props ?? fig.props);
      }
      expect(fig.frameCoordinate(after), greaterThan(i));
      expect(figureMotionTime(fig, after), greaterThan(time));
      final atKey = liftSkeleton(fig.skeletonAt(exact), fig).p;
      final next = liftSkeleton(fig.skeletonAt(after), fig).p;
      for (final joint in atKey.keys) {
        expect((next[joint]! - atKey[joint]!).length, lessThan(.01), reason: '$i/$joint');
      }
      if (fig.motion[i].kind == 'hold' || fig.motion[i].kind == 'cut') {
        expect(fig.skeletonAt((i + .5) / n).joints, fig.skeletonAt(exact).joints);
        expect(fig.propsAt((i + .25) / n), fig.frames[i].props ?? fig.props);
      }
      time += fig.motion[i].seconds;
    }
    expect(fig.frameCoordinate(1), n.toDouble());
    expect(figureMotionTime(fig, 1), closeTo(time, 1e-8));
    // Dominadas tiene recorrido propio desde la auditoría 052.
    final legacy = catalog.forExercise('Colgado pasivo')!;
    expect(legacy.stageAt(.43), isNull);
    expect(legacy.frameCoordinate(.43), .43 * (legacy.frames.length - 1));
  });
  test('authored playback is forward-only within a stride and a hold is still', () {
    final fig = catalog.forExercise('Barca / V-sit')!;
    final hold = fig.motion.indexWhere((s) => s.kind == 'hold');
    expect(
        fig.skeletonAt((hold + .1) / fig.motion.length).joints, fig.skeletonAt((hold + .9) / fig.motion.length).joints);
    final run = catalog.forExercise('Aceleración 10–20 m')!;
    final duration = run.motion.take(3).fold<double>(0, (a, s) => a + s.seconds);
    var x = double.negativeInfinity;
    for (var i = 0; i < 60; i++) {
      final next = run.skeletonAt(figureMotionProgress(run, duration * i / 60)).joints['hip']!.dx;
      expect(next, greaterThanOrEqualTo(x));
      x = next;
    }
  });
}
