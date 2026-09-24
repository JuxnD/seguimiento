import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/energy.dart';
import 'package:seguimiento/domain/enums.dart';

void main() {
  test('sin peso no hay estimación', () {
    expect(sessionKcal(type: SessionType.circuito, weightKg: null, workSec: 1200), isNull);
    expect(sessionKcal(type: SessionType.circuito, weightKg: 0, workSec: 1200), isNull);
  });

  test('circuito de 20 min a 70 kg ≈ 187 kcal de trabajo', () {
    // 8,0 MET × 70 kg × 1/3 h = 186,7
    expect(sessionKcal(type: SessionType.circuito, weightKg: 70, workSec: 1200), closeTo(186.7, 0.1));
  });

  test('cada fase suma con su propio MET', () {
    final kcal = sessionKcal(
      type: SessionType.circuito,
      weightKg: 70,
      warmupSec: 360, // 3,5 × 70 × 0,1 = 24,5
      workSec: 1200, // 186,7
      restSec: 180, // 2,0 × 70 × 0,05 = 7
      cooldownSec: 180, // 2,3 × 70 × 0,05 = 8,05
    )!;
    expect(kcal, closeTo(226.2, 0.1));
  });

  test('descansar gasta menos que trabajar el mismo tiempo', () {
    final work = sessionKcal(type: SessionType.bloques, weightKg: 70, workSec: 600)!;
    final rest = sessionKcal(type: SessionType.bloques, weightKg: 70, restSec: 600)!;
    expect(rest, lessThan(work));
  });

  test('un circuito ligero gasta menos que uno vigoroso', () {
    expect(workMet(SessionType.circuitoLigero), lessThan(workMet(SessionType.circuito)));
  });
}
