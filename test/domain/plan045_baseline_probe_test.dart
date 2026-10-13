import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/timer_profile.dart';
import 'package:seguimiento/features/training/v3_timers.dart';

void main() {
  test('running 15/15 needs both final pauses to reach two complete eight minute blocks', () {
    final steps = tabataTimeline(blocks: 2, intervals: 16, work: 15, rest: 15, between: 0, includeFinalRest: true);
    expect(steps.fold<int>(0, (sum, step) => sum + step.seconds), 960);
    expect(steps.where((s) => s.kind == 'trabajo'), hasLength(32));
    expect(steps.where((s) => s.kind == 'pausa'), hasLength(32));
    expect((steps.last.kind, steps.last.seconds), ('pausa', 15));
    expect(tabataTimeSplit(steps, 960), (work: 480, rest: 480));
    expect(tabataTimeSplit(steps, 479), (work: 240, rest: 239));
    expect(tabataTimeSplit(steps, 480), (work: 240, rest: 240));
    expect(tabataTimeSplit(steps, 959), (work: 480, rest: 479));
  });
  test('timer JSON preserves a frozen running prescription instead of silently restoring defaults', () {
    final json = <String, Object?>{
      'kind': 'timer',
      'date': '2030-02-05',
      'startedAt': '2030-02-05T08:00:00.000',
      'mode': 'running1515',
      'phase': 'trabajo',
      'workStartedAt': '2030-02-05T08:08:00.000',
      'exercises': ['Carrera 15/15', 'Carrera 15/15'],
      'profile': 'running1515',
      'workSec': 15,
      'restSec': 15,
      'intervals': 16,
      'betweenBlocksSec': 0,
      'includeFinalRest': true,
      'footballFreeConfirmed': true,
    };
    final restored = ActiveSession.fromJson(jsonDecode(jsonEncode(json)));
    expect(restored, isA<TimerSnapshot>());
    final frozen = restored!.toJson();
    for (final key in [
      'profile',
      'workSec',
      'restSec',
      'intervals',
      'betweenBlocksSec',
      'includeFinalRest',
      'footballFreeConfirmed'
    ]) {
      expect(frozen[key], json[key], reason: key);
    }
  });
  test('legacy timeline remains unchanged and unknown or partial profiles are rejected', () {
    final legacy = tabataTimeline();
    expect(legacy.fold<int>(0, (sum, step) => sum + step.seconds), 1100);
    expect(tabataTimeSplit(legacy, 1100), (work: 640, rest: 460));
    final old = TimerSnapshot(date: '2030-02-05', startedAt: DateTime(2030), mode: 'tabata', phase: 'trabajo');
    expect(ActiveSession.fromJson(old.toJson())!.toJson(), old.toJson());
    expect(ActiveSession.fromJson({...old.toJson(), 'profile': 'unknown'}), isNull);
    expect(ActiveSession.fromJson({...old.toJson(), 'workSec': 15}), isNull);
    for (final bad in [
      {'footballFreeConfirmed': false},
      {'workSec': 20},
      {'restSec': -1},
      {'includeFinalRest': false},
      {'intervals': 8},
      {'mode': 'tabata'},
    ]) {
      final running = TimerSnapshot(
          date: '2030-02-05',
          startedAt: DateTime(2030),
          mode: 'running1515',
          phase: 'trabajo',
          exercises: const ['Carrera', 'Carrera'],
          prescription: const TimerPrescription.running1515());
      expect(ActiveSession.fromJson({...running.toJson(), ...bad}), isNull, reason: '$bad');
    }
    expect(() => TabataScreen.running1515(date: DateTime(2030), footballFreeConfirmed: false), throwsArgumentError);
  });
  test('custom Tabata prescription survives JSON without inheriting the running profile', () {
    final custom = TimerSnapshot(
        date: '2030-02-05',
        startedAt: DateTime(2030),
        mode: 'tabata',
        phase: 'trabajo',
        exercises: const ['A', 'B', 'C'],
        prescription: const TimerPrescription(
            profile: TimerProfile.tabata,
            workSec: 30,
            restSec: 20,
            intervals: 4,
            betweenBlocksSec: 45,
            includeFinalRest: true));
    final back = ActiveSession.fromJson(jsonDecode(jsonEncode(custom.toJson())))! as TimerSnapshot;
    expect(back.toJson(), custom.toJson());
    expect((back.workSec, back.restSec, back.intervals, back.betweenBlocksSec, back.includeFinalRest),
        (30, 20, 4, 45, true));
    expect(back.footballFreeConfirmed, isNull);
  });
}
