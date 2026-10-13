import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/plan_v32.dart';
import 'package:seguimiento/domain/fitness_test.dart';

void main() {
  test(
      'signed pike allowed; same negative is rejected for other units and regular reps',
      () {
    expect(benchmarkError('seated_pike', -8, null, null), isNull);
    for (final item in ['pancake', 'deep_squat']) {
      expect(benchmarkError(item, -8, null, null), isNotNull);
    }
    expect(benchmarkError('knee_to_wall', -8, null, 'I'), isNotNull);
    expect(
        testValue([const TestResult(round: 1, item: 'pullup', value: -8)], 1,
            'pullup'),
        isNull);
    expect(benchmarkError('seated_pike', double.nan, null, null), isNotNull);
  });
  test(
      'shoulder boolean false is known and null unknown; numeric substitution invalid',
      () {
    expect(benchmarkError('shoulder_wall', null, false, null), isNull);
    expect(benchmarkError('shoulder_wall', null, null, null), isNotNull);
    expect(benchmarkError('shoulder_wall', 0, false, null), isNotNull);
  });
  test('benchmarks recur every28days without calendar month rounding', () {
    final start = DateTime(2030, 2, 4);
    expect(mobilityBenchmarkDue(start, start.add(const Duration(days: 2))),
        isTrue);
    expect(mobilityBenchmarkDue(start, start.add(const Duration(days: 29))),
        isFalse);
    expect(mobilityBenchmarkDue(start, start.add(const Duration(days: 30))),
        isTrue);
    expect(mobilityBenchmarkDue(start, start.add(const Duration(days: 58))),
        isTrue);
  });
  test(
      'knee thresholds and dominant rest; consecutive three days cannot cross gaps',
      () {
    expect(kneeTrainingMode(2), KneeTrainingMode.normal);
    for (final value in [3, 4]) {
      expect(kneeTrainingMode(value), KneeTrainingMode.noImpact);
    }
    expect(kneeTrainingMode(5), KneeTrainingMode.isometricsOnly);
    expect(kneeTrainingMode(5, restOnly: true), KneeTrainingMode.rest);
    final today = DateTime(2030, 2, 28);
    expect(
        kneeThreeDayAlert(
            today, {'2030-02-28': 3, '2030-02-27': 4, '2030-02-26': 3}),
        isTrue);
    expect(
        kneeThreeDayAlert(today, {
          '2030-02-28': 3,
          '2030-02-27': null,
          '2030-02-26': 3,
          '2030-02-25': 4
        }),
        isFalse);
    expect(
        kneeThreeDayAlert(
            today, {'2030-02-28': 3, '2030-02-27': 0, '2030-02-26': 3}),
        isFalse);
  });
}
