import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/progress.dart';
import 'package:seguimiento/domain/progress_evidence.dart';

void main() {
  final today = DateTime(2026, 10, 12);
  RoundTimingEvidence timing(
          {TimingBasis basis = TimingBasis.work, int? plan = 7, String? mode, bool incomplete = false}) =>
      RoundTimingEvidence(
          sessionId: 1,
          date: today,
          type: SessionType.circuito,
          basis: basis,
          planDayId: plan,
          exerciseProtocol: 'Flexiones|10|null|null',
          mode: mode,
          durationsSec: [60, 65, 70],
          incomplete: incomplete);
  test('duraciones una vez, protocolo y base explícitos', () {
    expect(timing().meanDurationSec, 65);
    expect(timing().comparableTo(timing()), isTrue);
    for (final other in [
      timing(basis: TimingBasis.lap),
      timing(plan: 8),
      timing(plan: null),
      timing(mode: 'porTiempo'),
      timing(incomplete: true)
    ]) {
      expect(timing().comparableTo(other), isFalse);
    }
  });
  String? hint(List<StrengthSetEvidence> sets, {bool perSide = false}) => strengthProgressionHint(
      evidence: StrengthSessionEvidence(
          sessionId: 1,
          date: DateTime(2026, 10, 5),
          type: SessionType.bloques,
          exercise: 'Flexiones',
          sets: sets),
      date: today,
      repsMin: 10,
      repsMax: 15,
      plannedSets: 1,
      tracksLoad: true,
      perSide: perSide);
  test('mantiene política RIR ausente, bloquea fallo, partición y mezcla', () {
    expect(hint([const StrengthSetEvidence(reps: 15)]), isNotNull);
    for (final s in [
      const StrengthSetEvidence(reps: 15, rir: 0),
      const StrengthSetEvidence(reps: 15, split: true),
      const StrengthSetEvidence(reps: 15, toFailure: true)
    ]) {
      expect(hint([s]), isNull);
    }
    expect(hint([]), isNull);
    expect(hint([const StrengthSetEvidence(reps: 15)], perSide: true), isNull);
    expect(
        hint([
          const StrengthSetEvidence(reps: 15, variant: 'A'),
          const StrengthSetEvidence(reps: 15, variant: 'B')
        ]),
        isNull);
    expect(
        hint([
          const StrengthSetEvidence(reps: 15, loadKg: 5),
          const StrengthSetEvidence(reps: 15, loadKg: 10)
        ]),
        isNull);
  });
  test('observado visible, apto exige fecha, ambos lados y limpio; T3 parcial no oculta T2', () {
    expect(recordedTestDate('2026-02-30'), isNull);
    expect(recordedTestDate('2026-02-29'), isNull);
    expect(recordedTestDate('2024-02-29'), DateTime(2024, 2, 29));
    expect(recordedTestDate('2026-02-01T00:00:00Z'), isNull);
    final rows = [
      TestResult(round: 2, item: 'bulgarian_split_squat', side: 'I', value: 20, date: today),
      TestResult(round: 2, item: 'bulgarian_split_squat', side: 'D', value: 22, date: today),
      TestResult(round: 3, item: 'bulgarian_split_squat', side: 'I', value: 25, date: today),
    ];
    expect(latestEligibleTestRound(rows, 'bulgarian_split_squat', asOf: today), 2);
    expect(eligibleTestValue(rows, 2, 'bulgarian_split_squat', asOf: today), 20);
    expect(eligibleTestValue(rows, 3, 'bulgarian_split_squat', asOf: today), isNull);
    final doubt = [TestResult(round: 1, item: 'pullup', value: 20, clean: false, date: today)];
    expect(testValue(doubt, 1, 'pullup'), 20);
    expect(eligibleTestValue(doubt, 1, 'pullup'), isNull);
    expect(eligibleTestValue(const [TestResult(round: 1, item: 'pullup', value: 20)], 1, 'pullup'), isNull);
    expect(
        eligibleTestValue([
          TestResult(round: 1, item: 'pullup', value: 20, date: today.add(const Duration(days: 1)))
        ], 1, 'pullup', asOf: today),
        isNull);
    expect(
        eligibleTestValue([
          TestResult(round: 1, item: 'pullup', value: 20, date: today.subtract(const Duration(days: 40)))
        ], 1, 'pullup', asOf: today, maxAgeDays: 30),
        isNull);
    expect(
        eligibleTestValue([
          TestResult(round: 1, item: 'pullup', value: 20, date: today),
          TestResult(round: 1, item: 'pullup', value: 20, date: today)
        ], 1, 'pullup'),
        isNull);
    expect(
        eligibleTestValue(
            [TestResult(round: 1, item: 'pullup', value: double.nan, date: today)], 1, 'pullup'),
        isNull);
    expect(latestEligibleTestRound([], 'pullup'), isNull);
  });
}
