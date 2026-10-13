import 'dart:convert';
import 'fitness_test.dart' show recordedTestDate;

class AccessoryQualityProof {
  const AccessoryQualityProof(
      {required this.identity,
      this.variantConfirmed,
      this.pause2Confirmed,
      this.relaxed,
      this.alarmFree,
      this.alarm,
      this.achillesCheckedOn});
  final String identity;
  final bool? variantConfirmed, relaxed, alarmFree;
  final bool? pause2Confirmed;
  final String? alarm;
  final String? achillesCheckedOn;
  DateTime? get achillesCheckedDate =>
      achillesCheckedOn == null ? null : recordedTestDate(achillesCheckedOn!);
  static const alarmsByLadder = <String, String>{
    'copenhagen': 'groin_over_3',
    'seated_soleus': 'achilles_next_morning',
    'band_external_rotation': 'shoulder_pinch',
    'support_hold': 'inner_elbow',
    'flying_sprint': 'hamstring_pinch',
  };
  static const prefix = '_accessoryQuality:v1:';
  static String key(String ladder) => '$prefix$ladder';
  String encode() => jsonEncode({
        'version': 1,
        'identity': identity,
        'variantConfirmed': variantConfirmed,
        'pause2Confirmed': pause2Confirmed,
        'relaxed': relaxed,
        'alarmFree': alarmFree,
        'alarm': alarm,
        if (achillesCheckedOn != null) 'achillesCheckedOn': achillesCheckedOn
      });
  static AccessoryQualityProof? decode(String? raw) {
    if (raw == null) return null;
    try {
      final p = (jsonDecode(raw) as Map).cast<String, Object?>();
      const requiredKeys = {
        'version',
        'identity',
        'variantConfirmed',
        'pause2Confirmed',
        'relaxed',
        'alarmFree',
        'alarm'
      };
      if (!p.keys.toSet().containsAll(requiredKeys) ||
          p.keys.any(
              (k) => !requiredKeys.contains(k) && k != 'achillesCheckedOn') ||
          (p['achillesCheckedOn'] != null &&
              (p['achillesCheckedOn'] is! String ||
                  recordedTestDate(p['achillesCheckedOn'] as String) ==
                      null)) ||
          p['version'] is! int ||
          p['version'] != 1 ||
          p['identity'] is! String ||
          !RegExp(r'^\d+:\d+$').hasMatch(p['identity'] as String) ||
          ['variantConfirmed', 'relaxed', 'alarmFree', 'pause2Confirmed']
              .any((k) => p[k] != null && p[k] is! bool) ||
          (p['alarm'] != null &&
              ![
                'groin_over_3',
                'achilles_next_morning',
                'shoulder_pinch',
                'inner_elbow',
                'hamstring_pinch'
              ].contains(p['alarm'])) ||
          (p['alarm'] != null && p['alarmFree'] == true)) return null;
      return AccessoryQualityProof(
          identity: p['identity'] as String,
          variantConfirmed: p['variantConfirmed'] as bool?,
          pause2Confirmed: p['pause2Confirmed'] as bool?,
          relaxed: p['relaxed'] as bool?,
          alarmFree: p['alarmFree'] as bool?,
          alarm: p['alarm'] as String?,
          achillesCheckedOn: p['achillesCheckedOn'] as String?);
    } catch (_) {
      return null;
    }
  }
}
