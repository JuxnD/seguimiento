import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';

void main() {
  final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
  final cases = <(String, String)>[
    ('Aceleración 10–20 m', ''),
    ('Sprint lanzado', ''),
    ('Calentamiento tipo FIFA 11+', '1'),
    ('Calentamiento tipo FIFA 11+', '10'),
  ];

  test('running recovers the free leg and counter arm during support instead of sliding a frozen diamond', () {
    for (final item in cases) {
      final fig = catalog.forExercise(item.$1)!;
      final first = fig.motion.indexWhere((s) => s.part == item.$2 && s.kind != 'cut');
      final start = liftSkeleton(fig.skeletonAt(first / fig.motion.length), fig);
      final end = liftSkeleton(fig.skeletonAt((first + .99) / fig.motion.length), fig);
      final freeStart = start.p['farAnkle']! - start.p['hip']!;
      final freeEnd = end.p['farAnkle']! - end.p['hip']!;
      expect((freeEnd - freeStart).length, greaterThan(2), reason: '$item free leg must recover relative to pelvis');
      final armStart = start.p['nearHand']! - start.p['nearShoulder']!;
      final armEnd = end.p['nearHand']! - end.p['nearShoulder']!;
      expect((armEnd - armStart).length, greaterThan(1), reason: '$item counter arm must accompany recovery');
      expect((end.p['nearAnkle']! - start.p['nearAnkle']!).length, lessThan(.05));
    }
  });

  test('running separates extended propulsion from recovered knee and actual flight', () {
    for (final item in cases) {
      final fig = catalog.forExercise(item.$1)!;
      var longestSupport = 0.0;
      var realFlight = false;
      for (var i = 0; i < fig.motion.length; i++) {
        final stage = fig.motion[i];
        if (stage.part != item.$2 || stage.kind == 'cut') continue;
        for (var sample = 0; sample <= 20; sample++) {
          final body = liftSkeleton(fig.skeletonAt((i + sample / 20) / fig.motion.length), fig);
          for (final side in ['near', 'far']) {
            if (body.p['${side}Ankle']!.y.abs() <= 1.05) {
              final length = (body.p['${side}Ankle']! - body.p['${side}Hip']!).length;
              if (length > longestSupport) longestSupport = length;
            }
          }
          if (stage.ground == 'flight' && body.p['nearAnkle']!.y < -2 && body.p['farAnkle']!.y < -2) {
            realFlight = true;
          }
        }
      }
      expect(longestSupport, greaterThan(27), reason: '$item push-off must extend the support leg');
      expect(realFlight, isTrue, reason: '$item must show flight between opposite contacts');
    }
  });
}
