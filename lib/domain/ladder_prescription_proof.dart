import 'dart:convert';

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
