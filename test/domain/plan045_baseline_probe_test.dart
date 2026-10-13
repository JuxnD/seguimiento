import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/features/training/v3_timers.dart';

void main() {
  test('running 15/15 needs both final pauses to reach two complete eight minute blocks', () {
    final steps = tabataTimeline(blocks: 2, intervals: 16, work: 15, rest: 15, between: 0);
    expect(steps.fold<int>(0, (sum, step) => sum + step.seconds), 960);
  });
  test('timer JSON preserves a frozen running prescription instead of silently restoring defaults', () {
    final json = <String, Object?>{
      'kind': 'timer', 'date': '2030-02-05', 'startedAt': '2030-02-05T08:00:00.000',
      'mode': 'running1515', 'phase': 'trabajo', 'workStartedAt': '2030-02-05T08:08:00.000',
      'exercises': ['Carrera 15/15', 'Carrera 15/15'],
      'profile': 'running1515', 'workSec': 15, 'restSec': 15,
      'intervals': 16, 'betweenBlocksSec': 0, 'includeFinalRest': true,
      'footballFreeConfirmed': true,
    };
    final restored = ActiveSession.fromJson(jsonDecode(jsonEncode(json)));
    expect(restored, isA<TimerSnapshot>());
    final frozen = restored!.toJson();
    for (final key in ['profile', 'workSec', 'restSec', 'intervals', 'betweenBlocksSec',
      'includeFinalRest', 'footballFreeConfirmed']) {
      expect(frozen[key], json[key], reason: key);
    }
  });
}
