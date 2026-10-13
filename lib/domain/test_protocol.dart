import 'dart:convert';
import 'dates.dart';
import 'fitness_test.dart';

enum TestProtocolId { v31_12, v32_13 }

class TestScheduleKey {
  const TestScheduleKey(
      {required this.scheme,
      required this.blockStart,
      required this.protocolId,
      required this.round,
      required this.part});
  final String scheme;
  final DateTime blockStart;
  final TestProtocolId protocolId;
  final int round;
  final TestPart part;
  String get prefix =>
      'test_move:$scheme:${dayKey(blockStart)}:${protocolId.name}:$round:${part.name}:';
}

const reversePlankTest = TestItem('reverse_plank_forearm',
    'Plancha inversa sobre antebrazos', TestUnit.seconds);
List<TestItem> protocolItems(TestProtocolId protocol, TestPart part) =>
    part == TestPart.piernas
        ? legTests
        : [
            ...torsoTests,
            if (protocol == TestProtocolId.v32_13) reversePlankTest
          ];

/// Only meaningful dimensions are accepted; a missing condition stays unknown.
String canonicalTestConditions(String item, Map<String, Object?> conditions) {
  final valid = <String>{'variant'};
  if (['pullup', 'dead_hang', 'hanging_leg_raise'].contains(item)) {
    valid.add('grip');
  }
  if ([
    'dips',
    'one_arm_pushup',
    'pike_pushup',
    'pistol_box',
    'reverse_plank_forearm'
  ].contains(item)) {
    valid.addAll(['support', 'heightCm']);
  }
  final canonical = <String, Object?>{};
  for (final key in conditions.keys.toList()..sort()) {
    if (!valid.contains(key)) {
      throw FormatException('Condición no pertinente: $key');
    }
    final value = conditions[key];
    if (key == 'heightCm') {
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('Altura inválida');
      }
      canonical[key] = value.toDouble();
    } else {
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('Condición vacía');
      }
      final text = value.trim();
      if (key == 'grip' && !['prona', 'supina', 'neutro'].contains(text)) {
        throw const FormatException('Agarre inválido');
      }
      canonical[key] = text;
    }
  }
  return jsonEncode(canonical);
}

String testBaselineKey(TestProtocolId protocol, String item, String? side,
        String? conditions) =>
    jsonEncode([protocol.name, item, side, conditions]);

/// Complete bilateral evidence belongs to one recorded attempt and baseline.
bool sameTestConditions(String? a, String? b) => a != null && a == b;

String testConditionsLabel(String? raw) {
  if (raw == null) return 'desconocidas';
  try {
    final values = (jsonDecode(raw) as Map).cast<String, Object?>();
    return values.entries
        .map((e) => switch (e.key) {
              'grip' => 'Agarre: ${e.value}',
              'support' => 'Apoyo: ${e.value}',
              'heightCm' => 'Altura: ${e.value} cm',
              'variant' => 'Variante: ${e.value}',
              _ => 'Condición sin validar',
            })
        .join(' · ');
  } catch (_) {
    return 'sin validar';
  }
}
