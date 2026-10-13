import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/exercise_details.dart';
import 'package:seguimiento/domain/enums.dart';

void main() {
  test('all seven days retain a guide and a separate nonempty purpose', () {
    final plan = planV32(DateTime(2030, 2, 4));
    expect(plan.days.map((d) => d.weekday), [1, 2, 3, 4, 5, 6, 7]);
    expect(plan.days.last.type, DayType.futbol);
    final missing = [
      for (final day in plan.days)
        for (final e in day.exercises)
          if (e.purpose == null ||
              e.purpose!.trim().isEmpty ||
              exerciseDetail(e.name) == null)
            '${day.weekday}:${e.name}'
    ];
    expect(missing, isEmpty,
        reason:
            'Every inherited and new exercise needs the shared content reference.');
    final wed = plan.days[2].exercises;
    expect(wed.singleWhere((e) => e.name == 'Sprint lanzado').restSec, 120);
    expect(wed.singleWhere((e) => e.name == 'Salto vertical').sets, 3);
    expect(wed.singleWhere((e) => e.name == 'Salto vertical').repsMin, 3);
    expect(
        plan.days[1].exercises
            .singleWhere((e) => e.name == 'Copenhague')
            .physicalVariantKey,
        'copenhagen_short');
    expect(plan.days[4].targetRounds, 6);
    expect(plan.days[4].exercises.any((e) => e.block == 'tabata'), isFalse);
  });
}
