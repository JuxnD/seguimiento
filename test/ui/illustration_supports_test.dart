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
}
