import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/enums.dart';

void main() {
  final t0 = DateTime(2026, 9, 23, 15, 10);

  test('el guiado vuelve igual tras pasar por JSON', () {
    final snap = GuidedSnapshot(
      date: '2026-09-23',
      startedAt: t0,
      planDayId: 12,
      sessionType: SessionType.circuitoLigero,
      coreVariant: 'B',
      roundsOverride: 5,
      phase: GuidedPhase.trabajo,
      index: 7,
      workStartedAt: t0.add(const Duration(minutes: 6)),
      restStartedAt: t0.add(const Duration(minutes: 9)),
      reps: 12,
      done: const [DoneStep('Flexiones', 12, true), DoneStep('Dominadas', 5, true)],
      roundMarks: const [150, 310],
    );
    final back = ActiveSession.fromJson(jsonDecode(jsonEncode(snap.toJson()))) as GuidedSnapshot;

    expect(back.date, '2026-09-23');
    expect(back.startedAt, t0);
    expect(back.planDayId, 12);
    expect(back.sessionType, SessionType.circuitoLigero);
    expect(back.coreVariant, 'B');
    expect(back.roundsOverride, 5);
    expect(back.phase, GuidedPhase.trabajo);
    expect(back.index, 7);
    expect(back.workStartedAt, t0.add(const Duration(minutes: 6)));
    expect(back.workEndedAt, isNull);
    expect(back.restStartedAt, t0.add(const Duration(minutes: 9)));
    expect(back.reps, 12);
    expect(back.done.map((d) => (d.exercise, d.reps, d.isRound)), [('Flexiones', 12, true), ('Dominadas', 5, true)]);
    expect(back.roundMarks, [150, 310]);
  });

  test('el libre vuelve igual tras pasar por JSON', () {
    final snap = CounterSnapshot(
      date: '2026-09-23',
      startedAt: t0,
      phase: CounterPhase.cooldown,
      outOfPlan: true,
      circuitStart: t0.add(const Duration(minutes: 5)),
      circuitEnd: t0.add(const Duration(minutes: 25)),
      marks: const [140, 290, 450],
    );
    final back = ActiveSession.fromJson(jsonDecode(jsonEncode(snap.toJson()))) as CounterSnapshot;
    expect(back.phase, CounterPhase.cooldown);
    expect(back.outOfPlan, isTrue);
    expect(back.circuitEnd, t0.add(const Duration(minutes: 25)));
    expect(back.marks, [140, 290, 450]);
  });

  test('JSON raro o de otra versión no revienta: devuelve null', () {
    expect(ActiveSession.fromJson(null), isNull);
    expect(ActiveSession.fromJson('texto'), isNull);
    expect(ActiveSession.fromJson({'kind': 'otro'}), isNull);
    expect(ActiveSession.fromJson({'kind': 'guided', 'date': '2026-09-23'}), isNull);
    expect(ActiveSession.fromJson({'kind': 'counter', 'date': 1, 'startedAt': 'x'}), isNull);
  });
}
