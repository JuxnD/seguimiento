import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/progress_metrics.dart';
import 'package:seguimiento/domain/test_protocol.dart';

void main() {
  final cutoff = DateTime(2030, 2, 28);
  test(
      'legacy unknown remains observed; no percentage/dose or invented known baseline',
      () {
    final axis = buildPersonalRadar(tests: [
      TestResult(round: 1, item: 'pullup', value: 8, date: DateTime(2030, 2, 4))
    ], asOf: cutoff)
        .axis(RadarAxis.pull);
    expect(axis.observations.single.value, 8);
    expect(axis.observations.single.eligible, isFalse);
    expect(axis.current, isNull);
    expect(axis.changePercent, isNull);
    expect(axis.observations.single.reason, contains('desconocidas'));
  });
  test('same-round attempts stay separate; first baseline matches latest setup',
      () {
    TestResult row(int id, String grip, double value) => TestResult(
        round: 1,
        item: 'pullup',
        value: value,
        date: DateTime(2030, 2, id + 4),
        attemptId: id,
        protocolId: 'v32_13',
        conditions: canonicalTestConditions('pullup', {'grip': grip}));
    final rows = [row(1, 'prona', 5), row(2, 'prona', 8), row(3, 'supina', 12)];
    final mixed =
        buildPersonalRadar(tests: rows, asOf: cutoff).axis(RadarAxis.pull);
    expect(mixed.observations, hasLength(3));
    expect(mixed.current!.value, 12);
    expect(mixed.firstEligible!.value, 12);
    expect(mixed.changePercent, isNull);
    final compatible =
        buildPersonalRadar(tests: [...rows, row(4, 'prona', 10)], asOf: cutoff)
            .axis(RadarAxis.pull);
    expect(compatible.firstEligible!.value, 5);
    expect(compatible.current!.value, 10);
    expect(compatible.changePercent, 100);
  });
}
