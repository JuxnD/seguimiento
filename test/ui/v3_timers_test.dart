import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/features/training/v3_timers.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

/// Cindy y Tabata se retoman si Android cierra la app a mitad.
void main() {
  setUp(() {
    wakelock.wakelockPlusPlatformInstance = _NoWakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
  }

  test('la foto de Cindy o Tabata vuelve igual tras pasar por JSON', () {
    final t0 = DateTime(2026, 10, 16, 7);
    final snap = TimerSnapshot(
      date: '2026-10-16',
      startedAt: t0,
      mode: 'tabata',
      phase: 'trabajo',
      workStartedAt: t0.add(const Duration(minutes: 8)),
      worst: const {0: 11, 1: 9},
      exercises: const ['Flexiones', 'Escaladores', 'Sentadillas', 'Hollow rocks'],
    );
    final back = ActiveSession.fromJson(jsonDecode(jsonEncode(snap.toJson()))) as TimerSnapshot;
    expect((back.mode, back.phase, back.startedAt, back.workStartedAt), ('tabata', 'trabajo', t0, snap.workStartedAt));
    expect(back.worst, {0: 11, 1: 9});
    expect(back.exercises, snap.exercises);
  });

  testWidgets('Cindy retomada sigue con sus rondas y su reloj', (tester) async {
    final now = DateTime.now();
    final snaps = <TimerSnapshot>[];
    await show(
      tester,
      AmrapScreen(
        date: now,
        resume: TimerSnapshot(
          date: '2026-10-16',
          startedAt: now.subtract(const Duration(minutes: 13)),
          mode: 'cindy',
          phase: 'trabajo',
          workStartedAt: now.subtract(const Duration(minutes: 5)),
          roundMarks: const [70, 140],
        ),
        onSnapshot: snaps.add,
      ),
    );
    expect(find.text('2 rondas'), findsOneWidget);
    expect(find.textContaining('15:0'), findsOneWidget, reason: 'quedan ~15 min de los 20');

    await tester.tap(find.text('+1 ronda'));
    await tester.pump();
    expect(snaps.last.roundMarks, hasLength(3), reason: 'cada ronda deja la foto al día');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Cindy que terminó con la app cerrada pide la ronda a medias', (tester) async {
    final now = DateTime.now();
    await show(
      tester,
      AmrapScreen(
        date: now,
        resume: TimerSnapshot(
          date: '2026-10-16',
          startedAt: now.subtract(const Duration(minutes: 30)),
          mode: 'cindy',
          phase: 'trabajo',
          workStartedAt: now.subtract(const Duration(minutes: 22)),
          roundMarks: const [70, 140, 210],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('¿cuántas reps de la ronda a medias?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tabata retomado sigue en el bloque en que iba', (tester) async {
    final now = DateTime.now();
    await show(
      tester,
      TabataScreen(
        date: now,
        exercises: const ['Flexiones', 'Escaladores', 'Sentadillas', 'Hollow rocks'],
        resume: TimerSnapshot(
          date: '2026-10-16',
          startedAt: now.subtract(const Duration(minutes: 13)),
          mode: 'tabata',
          phase: 'trabajo',
          // Bloque 1 (230 s) + minuto entre bloques (60 s) + 5 s del bloque 2.
          workStartedAt: now.subtract(const Duration(seconds: 295)),
          worst: const {0: 12},
        ),
      ),
    );
    expect(find.textContaining('BLOQUE 2/4'), findsOneWidget);
    expect(find.textContaining('peor intervalo'), findsNothing, reason: 'el bloque 1 ya tenía su dato');
    await tester.pumpWidget(const SizedBox());
  });
}
