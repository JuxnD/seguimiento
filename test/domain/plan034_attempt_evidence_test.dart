import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_attempt_evidence.dart';
import 'package:seguimiento/domain/test_protocol.dart';

void main() {
  final cutoff = DateTime(2030, 2, 28);
  TestResult row(int id, double value,
          {String? side,
          String item = 'pullup',
          String? condition,
          String protocol = 'v32_13',
          bool clean = true}) =>
      TestResult(
          round: 1,
          item: item,
          value: value,
          attemptId: id,
          date: DateTime(2030, 2, id + 4),
          side: side,
          protocolId: protocol,
          clean: clean,
          conditions: condition);
  final prona = canonicalTestConditions('pullup', {'grip': 'prona'});
  final supina = canonicalTestConditions('pullup', {'grip': 'supina'});
  test(
      'same round multiple attempts remain individually eligible and compare only exact known baseline',
      () {
    final rows = [
      row(1, 5, condition: prona),
      row(2, 8, condition: prona),
      row(3, 12, condition: supina)
    ];
    final a = observedAttemptValue(rows, 1, 'pullup', asOf: cutoff)!;
    final b = observedAttemptValue(rows, 2, 'pullup', asOf: cutoff)!;
    final c = observedAttemptValue(rows, 3, 'pullup', asOf: cutoff)!;
    expect(comparableAttemptImprovement(a, b), 60);
    expect(comparableAttemptImprovement(a, c), isNull);
    expect(
        eligibleAttempts(rows, 'pullup', asOf: cutoff, conditions: prona)
            .map((e) => e.attemptId),
        [1, 2]);
    expect(
        observedAttemptValue([row(1, 5)], 1, 'pullup', asOf: cutoff), isNull);
    expect(
        observedAttemptValue([row(1, 5, condition: '{}')], 1, 'pullup',
            asOf: cutoff),
        isNull);
    expect(
        observedAttemptValue(
            [row(1, 5, condition: prona, clean: false)], 1, 'pullup',
            asOf: cutoff),
        isNull);
  });
  test('bilateral sides cannot be joined across attempts or unknown setup', () {
    final condition = canonicalTestConditions(
        'bulgarian_split_squat', {'variant': 'mochila'});
    final rows = [
      row(1, 8, item: 'bulgarian_split_squat', side: 'I', condition: condition),
      row(2, 10, item: 'bulgarian_split_squat', side: 'D', condition: condition)
    ];
    expect(observedAttemptValue(rows, 1, 'bulgarian_split_squat', asOf: cutoff),
        isNull);
    final both = [
      rows.first,
      row(1, 10, item: 'bulgarian_split_squat', side: 'D', condition: condition)
    ];
    expect(
        observedAttemptValue(both, 1, 'bulgarian_split_squat', asOf: cutoff)!
            .value,
        8);
    expect(
        observedAttemptValue([...both, both.first], 1, 'bulgarian_split_squat',
            asOf: cutoff),
        isNull);
  });
}
