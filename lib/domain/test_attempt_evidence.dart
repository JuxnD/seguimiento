import 'dart:convert';
import 'fitness_test.dart';
import 'test_protocol.dart';
import 'dates.dart';

class TestAttemptEvidence {
  const TestAttemptEvidence(
      {required this.attemptId,
      required this.protocol,
      required this.item,
      required this.conditions,
      required this.date,
      required this.value});
  final int attemptId;
  final String protocol, item, conditions;
  final DateTime date;
  final double value;
  String get baseline => jsonEncode([protocol, item, conditions]);
}

/// A bilateral result belongs to one attempt with one known measurement setup.
TestAttemptEvidence? observedAttemptValue(
    List<TestResult> results, int attemptId, String item,
    {required DateTime asOf, int? maxAgeDays}) {
  final rows =
      results.where((r) => r.attemptId == attemptId && r.item == item).toList();
  if (rows.isEmpty ||
      rows.map((r) => r.protocolId).toSet().length != 1 ||
      rows.map((r) => r.round).toSet().length != 1 ||
      rows.first.conditions == null ||
      rows.any((r) => r.conditions != rows.first.conditions)) return null;
  final conditions = rows.first.conditions!;
  final protocol = TestProtocolId.values
      .where((p) => p.name == rows.first.protocolId)
      .firstOrNull;
  if (protocol == null ||
      ![...protocolItems(protocol, TestPart.torso), ...legTests]
          .any((t) => t.id == item)) return null;
  try {
    final map = (jsonDecode(conditions) as Map).cast<String, Object?>();
    if (map.isEmpty || canonicalTestConditions(item, map) != conditions) {
      return null;
    }
  } catch (_) {
    return null;
  }
  final value = eligibleTestValue(rows, rows.first.round, item,
      asOf: asOf, maxAgeDays: maxAgeDays);
  if (value == null) return null;
  return TestAttemptEvidence(
      attemptId: attemptId,
      protocol: rows.first.protocolId,
      item: item,
      conditions: conditions,
      date: rows.first.date!,
      value: value);
}

List<TestAttemptEvidence> eligibleAttempts(
    List<TestResult> results, String item,
    {required DateTime asOf,
    String? protocol,
    String? conditions,
    int? maxAgeDays}) {
  final evidence = <TestAttemptEvidence>[];
  for (final id in results
      .where((r) => r.item == item)
      .map((r) => r.attemptId)
      .whereType<int>()
      .toSet()) {
    final entry = observedAttemptValue(results, id, item,
        asOf: asOf, maxAgeDays: maxAgeDays);
    if (entry != null &&
        (protocol == null || entry.protocol == protocol) &&
        (conditions == null || entry.conditions == conditions)) {
      evidence.add(entry);
    }
  }
  evidence.sort((a, b) {
    final date = dateOnly(a.date).compareTo(dateOnly(b.date));
    return date == 0 ? a.attemptId.compareTo(b.attemptId) : date;
  });
  return evidence;
}

double? comparableAttemptImprovement(
        TestAttemptEvidence first, TestAttemptEvidence later) =>
    first.baseline == later.baseline &&
            first.attemptId != later.attemptId &&
            !later.date.isBefore(first.date)
        ? improvement(first.value, later.value)
        : null;
