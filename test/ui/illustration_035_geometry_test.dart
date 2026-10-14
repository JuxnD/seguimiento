import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';

void main() {
  final catalog = Figure3DCatalog.fromJsonString(
      File(Platform.environment['ILLUSTRATION_FIXTURE'] ?? Figure3DCatalog.asset).readAsStringSync());
  test('carry knees flex forward on both sides throughout the stride', () {
    for (final name in ['Carga abrazada al pecho', 'Carga de maleta con mochila']) {
      final fig = catalog.forExercise(name)!;
      for (var i = 0; i <= 120; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 120), fig);
        for (final side in ['near', 'far']) {
          final line = body.p['${side}Ankle']! - body.p['${side}Hip']!;
          final knee = body.p['${side}Knee']! - body.p['${side}Hip']!;
          expect(line.x * knee.y - line.y * knee.x, lessThanOrEqualTo(.01), reason: '$name/$side/$i');
        }
      }
    }
  });
  test('band curl lifts hands in front of stable elbows', () {
    final fig = catalog.forExercise('Curl con banda')!;
    final initial = liftSkeleton(fig.skeletonAt(0), fig);
    for (var i = 0; i <= 120; i++) {
      final body = liftSkeleton(fig.skeletonAt(i / 120), fig);
      for (final side in ['near', 'far']) {
        final elbow = body.p['${side}Elbow']!;
        expect(body.p['${side}Hand']!.x, greaterThanOrEqualTo(elbow.x - .01));
        expect((elbow - initial.p['${side}Elbow']!).length, lessThan(.01));
      }
    }
  });
  test('pull-up elbow path has no sudden IK-plane flip, in either grip', () {
    for (final grip in ['prona', 'supina']) {
      final fig = catalog.forExercise('Dominadas', grip: grip)!;
      Body3D? previous;
      for (var i = 0; i <= 1200; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 1200), fig);
        for (final side in ['near', 'far']) {
          final elbow = body.p['${side}Elbow']!;
          if (previous != null) {
            expect((elbow - previous.p['${side}Elbow']!).length, lessThan(.3),
                reason: '$grip/$side/sample$i: discontinuity, not camera projection');
          }
          expect((body.p['${side}Hand']! - body.p['${side}Shoulder']!).length, lessThanOrEqualTo(19.01));
        }
        previous = body;
      }
    }
  });
  test('straddle knees remain straight and palms remain on the floor during lift', () {
    final fig = catalog.forExercise('Elevaciones en straddle')!;
    for (var i = 0; i <= 60; i++) {
      final body = liftSkeleton(fig.skeletonAt(i / 60), fig);
      for (final side in ['near', 'far']) {
        final thigh = (body.p['${side}Knee']! - body.p['${side}Hip']!).unit;
        final shin = (body.p['${side}Ankle']! - body.p['${side}Knee']!).unit;
        expect(thigh.dot(shin), greaterThan(.999), reason: 'sample$i/$side');
        expect(body.p['${side}Hand']!.y, closeTo(-.75, .01));
      }
    }
  });
  test('active hang changes the trunk locally, not hands or straight arm lengths', () {
    final active = catalog.forExercise('Colgarse de la barra')!;
    final passive = catalog.forExercise('Colgado pasivo')!;
    for (var i = 0; i <= 60; i++) {
      final a = liftSkeleton(active.skeletonAt(i / 60), active);
      final b = liftSkeleton(passive.skeletonAt(i / 60), passive);
      expect((a.p['neck']! - a.p['hip']!).length, closeTo(18, .01));
      expect((b.p['neck']! - b.p['hip']!).length, closeTo(18, .01));
      expect(a.p['hip']!.y, lessThan(b.p['hip']!.y - .5));
      for (final side in ['near', 'far']) {
        expect((a.p['${side}Hand']! - b.p['${side}Hand']!).length, lessThan(.01));
        expect((a.p['${side}Shoulder']! - b.p['${side}Shoulder']!).length, lessThan(.01));
        final upper = (a.p['${side}Elbow']! - a.p['${side}Shoulder']!).unit;
        final lower = (a.p['${side}Hand']! - a.p['${side}Elbow']!).unit;
        expect(upper.dot(lower), greaterThan(.9));
      }
    }
  });
  test('V-sit entry lifts feet, hold fixes gluteal support and leaves hands free', () {
    final fig = catalog.forExercise('Barca / V-sit')!;
    final entry = liftSkeleton(fig.skeletonAt(0), fig);
    final hold = liftSkeleton(fig.skeletonAt(.5), fig);
    final exit = liftSkeleton(fig.skeletonAt(1), fig);
    expect(hold.p['nearAnkle']!.y, lessThan(entry.p['nearAnkle']!.y - 10));
    expect(exit.p['nearAnkle']!.y, closeTo(entry.p['nearAnkle']!.y, .01));
    for (var i = 0; i <= 60; i++) {
      final body = liftSkeleton(fig.skeletonAt(i / 60), fig);
      expect(body.p['hip']!.y, closeTo(-5, .01));
      for (final side in ['near', 'far']) {
        expect(body.p['${side}Hand']!.y, lessThan(-5));
      }
    }
  });
}
