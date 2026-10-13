import 'dart:convert';
import 'dates.dart';

/// A declared reduced prescription is separate from observed performance.
abstract final class LadderPrescriptionProof {
  static const prefix = '_ladderPrescription:v1:';
  static String key(String ladder) => '$prefix$ladder';
  static String maintenance(
          {required String identity,
          required int sets,
          required int minimum,
          required bool perSide}) =>
      jsonEncode({
        'version': 1,
        'identity': identity,
        'mode': 'maintenance',
        'sets': sets,
        'minimum': minimum,
        'perSide': perSide
      });

  /// Descarga v3.2 explícita. El codec histórico maintenance/v1 no cambia.
  static String deload(
          {required String identity,
          required DateTime blockStart,
          required int week,
          required int sets,
          required int minimum,
          required bool perSide,
          required String physicalVariant,
          Map<String, Object?> companionGoals = const {}}) =>
      jsonEncode({
        'version': 2,
        'identity': identity,
        'prescriptionKind': 'deload',
        'scheme': 'v3.2',
        'blockStart': dayKey(blockStart),
        'week': week,
        'sets': sets,
        'minimum': minimum,
        'perSide': perSide,
        'physicalVariant': physicalVariant,
        'companionGoals': companionGoals,
      });

  static ({int sets, int minimum, bool perSide})? decodeDeload(
      String? raw, String identity,
      {required DateTime sessionDate,
      required String? blockStart,
      required String physicalVariant,
      required bool perSide,
      required int expectedSets,
      required int expectedMinimum,
      Map<String, Object?> expectedCompanions = const {}}) {
    if (raw == null || blockStart == null) return null;
    try {
      final p = (jsonDecode(raw) as Map).cast<String, Object?>();
      final start = DateTime.tryParse(blockStart);
      if (p.length != 11 ||
          p['version'] != 2 ||
          p['identity'] != identity ||
          p['prescriptionKind'] != 'deload' ||
          p['scheme'] != 'v3.2' ||
          p['blockStart'] != blockStart ||
          start == null ||
          dayKey(start) != blockStart ||
          daysBetween(start, sessionDate) ~/ 7 + 1 != 6 ||
          daysBetween(start, sessionDate) < 0 ||
          p['week'] != 6 ||
          p['physicalVariant'] != physicalVariant ||
          p['perSide'] != perSide ||
          p['sets'] != expectedSets ||
          p['minimum'] != expectedMinimum ||
          jsonEncode(p['companionGoals']) != jsonEncode(expectedCompanions) ||
          p['sets'] is! int ||
          p['minimum'] is! int) return null;
      final sets = p['sets'] as int, minimum = p['minimum'] as int;
      if (sets < 1 || sets > 100 || minimum < 1 || minimum > 3600) return null;
      return (sets: sets, minimum: minimum, perSide: perSide);
    } catch (_) {
      return null;
    }
  }

  static ({int sets, int minimum, bool perSide})? decode(
      String? raw, String identity) {
    if (raw == null) return null;
    try {
      final p = (jsonDecode(raw) as Map).cast<String, Object?>();
      if (p.length != 6 ||
          p['version'] != 1 ||
          p['identity'] != identity ||
          p['mode'] != 'maintenance' ||
          p['sets'] is! int ||
          p['minimum'] is! int ||
          p['perSide'] is! bool) return null;
      final sets = p['sets'] as int, minimum = p['minimum'] as int;
      if (sets < 1 || sets > 100 || minimum < 1 || minimum > 3600) return null;
      return (sets: sets, minimum: minimum, perSide: p['perSide'] as bool);
    } catch (_) {
      return null;
    }
  }
}
