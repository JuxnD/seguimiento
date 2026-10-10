import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';

void main() {
  final catalog = Figure3DCatalog.fromJsonString(File(
    Platform.environment['ILLUSTRATION_FIXTURE'] ?? Figure3DCatalog.asset,
  ).readAsStringSync());
  test('vela y dragon mantienen cabeza horizontal junto a los hombros', () {
    for (final fig in catalog.all.where((f) => f.name == 'Vela' || f.name.toLowerCase().contains('dragon flag'))) {
      for (var frame = 0; frame < fig.frames.length; frame++) {
        final body = liftSkeleton(fig.skeletonAt(frame / (fig.frames.length - 1)), fig);
        expect(body.headUp.y.abs(), lessThan(.02), reason: '${fig.name}/$frame: no enseñar apoyo sobre la cabeza');
        expect(body.face.y, lessThan(-.98), reason: '${fig.name}/$frame: cara hacia arriba');
        expect(body.p['head']!.y + fig.dims.headRadius, lessThanOrEqualTo(.05));
        expect(body.p['neck']!.y, inInclusiveRange(-5, -3), reason: '${fig.name}/$frame: hombros junto al suelo');
      }
    }
  });
  test('cuadriceps y piernas en pared mantienen el pie transversal a la tibia', () {
    for (final name in ['Cuádriceps', 'Piernas en la pared']) {
      final fig = catalog.forExercise(name)!;
      for (var frame = 0; frame < fig.frames.length; frame++) {
        final p = liftSkeleton(fig.skeletonAt(frame / (fig.frames.length - 1)), fig).p;
        final shin = (p['nearAnkle']! - p['nearKnee']!).unit;
        final foot = (p['nearToe']! - p['nearAnkle']!).unit;
        expect(shin.dot(foot).abs(), lessThan(.1), reason: '$name/$frame: pie neutral en estas dos posturas');
      }
    }
  });
  test('manos conservan contacto con barra y borde de mesa durante el recorrido', () {
    double distance(V3 point, V3 a, V3 b) {
      final v = b - a;
      final t = ((point - a).dot(v) / v.dot(v)).clamp(0.0, 1.0);
      return (point - (a + v * t)).length;
    }

    V3 vector(Object? j) {
      final a = j as List;
      return V3((a[0] as num).toDouble(), (a[1] as num).toDouble(), (a[2] as num).toDouble());
    }

    final names = [
      'Dominadas',
      'Colgarse de la barra',
      'Colgado pasivo',
      'Fondos en barra',
      'Elevación de piernas colgado',
      'Toes-to-bar',
      'Remo invertido (mesa)',
      'Vela',
      ...catalog.all.where((f) => f.name.toLowerCase().contains('dragon flag')).map((f) => f.name)
    ];
    for (final name in names) {
      final fig = catalog.forExercise(name)!;
      final supports = <(V3, V3)>[];
      if (name == 'Remo invertido (mesa)') {
        final table = fig.props.first;
        final center = vector(table['center']), size = vector(table['size']);
        supports.add(
            (center + V3(-size.x / 2, -size.y / 2, -size.z / 2), center + V3(-size.x / 2, -size.y / 2, size.z / 2)));
      } else {
        for (final prop in fig.props) {
          if (prop['type'] == 'bar') {
            final x = (prop['x'] as num? ?? 0).toDouble(),
                y = (prop['y'] as num).toDouble(),
                half = (prop['half'] as num? ?? 16).toDouble();
            supports.add((V3(x, y, -half), V3(x, y, half)));
          }
          if (prop['type'] == 'tube') {
            final a = vector(prop['a']), b = vector(prop['b']);
            if ((a.y - b.y).abs() < .01) supports.add((a, b));
          }
        }
      }
      expect(supports, isNotEmpty, reason: '$name: equipo con apoyo declarado');
      for (var sample = 0; sample <= 60; sample++) {
        final p = liftSkeleton(fig.skeletonAt(sample / 60), fig).p;
        for (final side in ['near', 'far']) {
          final gap = supports.map((s) => distance(p['${side}Hand']!, s.$1, s.$2)).reduce((a, b) => a < b ? a : b);
          expect(gap, lessThan(.15), reason: '$name/$side en $sample/60: mano separada del equipo');
        }
      }
    }
  });
  test('flexion unilateral mantiene solamente la mano de trabajo apoyada', () {
    final one = catalog.forExercise('Flexión a una mano')!;
    for (var sample = 0; sample <= 60; sample++) {
      final p = liftSkeleton(one.skeletonAt(sample / 60), one).p;
      expect(p['nearHand']!.y, inInclusiveRange(-1, -.5), reason: 'palma de trabajo en el suelo');
      expect(p['farHand']!.y, lessThan(-6), reason: 'brazo libre recogido por detrás del torso');
    }
  });
  test('plancha inversa y pike mantienen palmas apoyadas al cambiar de momento', () {
    for (final name in ['Plancha inversa con patada', 'Pike push-up']) {
      final fig = catalog.forExercise(name)!;
      for (var sample = 0; sample <= 60; sample++) {
        final q = liftSkeleton(fig.skeletonAt(sample / 60), fig).p;
        for (final side in ['near', 'far']) {
          expect(q['${side}Hand']!.y, inInclusiveRange(-1, -.5), reason: '$name: palma en el suelo');
        }
      }
    }
  });

  test('calentamiento conserva apoyos y brazos rectos en 61 muestras', () {
    for (final name in ['Retracciones escapulares', 'Flexiones escapulares', 'Dislocaciones con banda']) {
      final fig = catalog.forExercise(name)!;
      final first = liftSkeleton(fig.skeletonAt(0), fig).p;
      for (var sample = 0; sample <= 60; sample++) {
        final body = liftSkeleton(fig.skeletonAt(sample / 60), fig);
        for (final side in ['near', 'far']) {
          final shoulder = body.p['${side}Shoulder']!, elbow = body.p['${side}Elbow']!, hand = body.p['${side}Hand']!;
          expect((elbow - shoulder).unit.dot((hand - elbow).unit), greaterThan(.999),
              reason: '$name/$sample: codos rectos');
          if (name != 'Dislocaciones con banda') {
            expect((hand - first['${side}Hand']!).length, lessThan(.02), reason: '$name/$sample: apoyo fijo');
          } else {
            expect(body.grips['${side}Hand'], 'handle');
          }
        }
      }
      if (name == 'Dislocaciones con banda') {
        final band = fig.props.singleWhere((prop) => prop['type'] == 'band');
        expect((band['a'], band['b']), ('nearHand', 'farHand'), reason: 'banda sujeta por ambas manos');
        final overhead = liftSkeleton(fig.skeletonAt(.25), fig).p;
        expect(overhead['nearHand']!.y, lessThan(overhead['head']!.y - fig.dims.headRadius));
      }
    }
  });

  test('balanceos distingue pierna móvil, pie fijo y mano en pared lateral', () {
    for (final side in ['I', 'D']) {
      final fig = catalog.forExercise('Balanceos de pierna', side: side)!;
      expect(fig.perSide, isTrue);
      final first = liftSkeleton(fig.skeletonAt(0), fig).p;
      for (var sample = 0; sample <= 60; sample++) {
        final p = liftSkeleton(fig.skeletonAt(sample / 60), fig).p;
        expect((p['farAnkle']! - first['farAnkle']!).length, lessThan(.01));
        expect((p['farHand']! - first['farHand']!).length, lessThan(.01));
        expect(p['farHand']!.z, closeTo(side == 'D' ? 16.5 : -16.5, .01),
            reason: 'centro de palma a0.5u de la cara z=-17');
        expect(p['farToe']!.y, closeTo(-1, .01));
        final shin = (p['nearAnkle']! - p['nearKnee']!).unit, foot = (p['nearToe']! - p['nearAnkle']!).unit;
        expect(shin.dot(foot).abs(), lessThan(.35), reason: 'pie móvil sin inversión extrema');
      }
      expect((liftSkeleton(fig.skeletonAt(1 / 6), fig).p['nearAnkle']! - first['nearAnkle']!).length, greaterThan(10));
    }
  });

  test('puente conserva hombros, cabeza horizontal, palmas y ambos pies', () {
    final fig = catalog.forExercise('Puente de glúteo')!;
    final first = liftSkeleton(fig.skeletonAt(0), fig).p;
    for (var sample = 0; sample <= 60; sample++) {
      final body = liftSkeleton(fig.skeletonAt(sample / 60), fig), p = body.p;
      expect((p['neck']! - first['neck']!).length, lessThan(.01));
      expect(body.headUp.y.abs(), lessThan(.01));
      for (final side in ['near', 'far']) {
        expect((p['${side}Ankle']! - first['${side}Ankle']!).length, lessThan(.01));
        expect(p['${side}Hand']!.y, inInclusiveRange(-1, -.5));
      }
    }
    final top = liftSkeleton(fig.skeletonAt(.5), fig).p;
    final trunk = (top['hip']! - top['neck']!).unit, thigh = (top['nearKnee']! - top['nearHip']!).unit;
    expect(trunk.dot(thigh), greaterThan(.999), reason: 'línea hombro-cadera-rodilla sin arco lumbar');
    expect(top['hip']!.y, lessThan(first['hip']!.y - 4));
  });
}
