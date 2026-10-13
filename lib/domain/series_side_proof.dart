import 'dart:convert';

/// Reserved, versioned metadata inside coreEpochs; old epoch entries remain strings.
abstract final class SeriesSideProof {
  static const prefix = '_seriesSides:v1:';
  static String key(String exercise) =>
      '$prefix${Uri.encodeComponent(exercise)}';
  static String encode(List<String?> sides) {
    if (sides.isEmpty ||
        sides.length > 512 ||
        sides.any((s) => s != null && s != 'I' && s != 'D')) {
      throw const FormatException('Evidencia de lados inválida');
    }
    return jsonEncode({'version': 1, 'sides': sides});
  }

  static List<String?>? decode(String? raw) {
    if (raw == null) return null;
    try {
      final value = (jsonDecode(raw) as Map).cast<String, Object?>();
      if (value.length != 2 ||
          value['version'] is! int ||
          value['version'] != 1 ||
          value['sides'] is! List) return null;
      final sides = (value['sides'] as List).cast<String?>();
      if (sides.isEmpty ||
          sides.length > 512 ||
          sides.any((s) => s != null && s != 'I' && s != 'D')) return null;
      return sides;
    } catch (_) {
      return null;
    }
  }
}
