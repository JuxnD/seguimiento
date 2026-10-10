import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';

void main() {
  final catalog = Figure3DCatalog.fromJsonString(
      File(Platform.environment['ILLUSTRATION_FIXTURE'] ?? Figure3DCatalog.asset).readAsStringSync());
  test('alcances 3D conservan largos de brazos y piernas en los momentos clave', () {
    final errors = <String>[];
    for (final fig in catalog.all) {
      for (var frame = 0; frame < fig.frames.length; frame++) {
        final body = liftSkeleton(fig.skeletonAt(frame / (fig.frames.length - 1)), fig);
        for (final side in ['near', 'far']) {
          for (final spec in [
            ('Shoulder', 'Elbow', fig.dims.upperArm),
            ('Elbow', 'Hand', fig.dims.forearm),
            ('Hip', 'Knee', fig.dims.thigh),
            ('Knee', 'Ankle', fig.dims.shin),
          ]) {
            final a = body.p['$side${spec.$1}'], b = body.p['$side${spec.$2}'];
            if (a == null || b == null) continue;
            final delta = ((b - a).length - spec.$3).abs();
            if (!delta.isFinite || delta > .4) errors.add('${fig.name}/$frame/$side${spec.$2}: $delta');
          }
        }
      }
    }
    expect(errors, isEmpty, reason: 'No entregar extremidades que no llegan a su apoyo: ${errors.join('; ')}');
  });

  test('elevaciones laterales usan el plano frontal y 90/90 conserva pelvis sentada', () {
    final lateral = catalog.forExercise('Elevaciones laterales con banda')!;
    final body = liftSkeleton(lateral.skeletonAt(.5), lateral);
    expect((body.p['nearHand']!.z - body.p['farHand']!.z).abs(), greaterThan(40));
    expect((body.p['nearHand']!.y - body.p['neck']!.y).abs(), lessThan(1));
    final seated = catalog.forExercise('90/90 de cadera')!;
    expect(seated.skeletonAt(0).joints['hip']!.dy, greaterThan(-6));
    expect(seated.skeletonAt(0).joints['hip']!.dy, lessThan(0));
  });

  test('figura4 apoya el tobillo en la rodilla opuesta; carrera no alcanza sobre la cabeza', () {
    final crossed = catalog.forExercise('Glúteo en figura 4')!;
    final body = liftSkeleton(crossed.skeletonAt(1), crossed);
    expect((body.p['nearAnkle']! - body.p['farKnee']!).length, lessThan(2),
        reason: 'contacto tobillo–rodilla, no cerca del muslo sin apoyar');
    final run = catalog.forExercise('Aceleración 10–20 m')!;
    for (var i = 0; i < run.frames.length; i++) {
      final p = liftSkeleton(run.skeletonAt(i / (run.frames.length - 1)), run).p;
      for (final side in ['near', 'far']) {
        expect(p['${side}Hand']!.y, greaterThan(p['head']!.y + 2), reason: 'mano de carrera por debajo de la cabeza');
      }
    }
  });

  test('la plancha lateral apila hombros; el pike no apoya los codos', () {
    final side = catalog.forExercise('Plancha lateral')!;
    final body = liftSkeleton(side.skeletonAt(0), side);
    expect((body.p['nearShoulder']!.y - body.p['farShoulder']!.y).abs(), greaterThan(7));
    expect(body.front.z.abs(), greaterThan(.9), reason: 'el pecho mira a un lado, no hacia el suelo');
    expect(body.p['nearElbow']!.y, inInclusiveRange(-2, -.5));
    final pike = catalog.forExercise('Pike push-up')!;
    for (final progress in [0.0, .5, 1.0]) {
      final pose = liftSkeleton(pike.skeletonAt(progress), pike);
      expect(pose.p['nearElbow']!.y, lessThan(-3), reason: 'apoyan las manos, no el antebrazo');
      expect(pose.p['farElbow']!.y, lessThan(-3));
    }
  });
}
