import 'dart:io';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/timer_profile.dart';
import 'package:seguimiento/features/training/v3_timers.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _PlatformWake extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

void main() {
  setUp(() {
    wakelock.wakelockPlusPlatformInstance = _PlatformWake();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  for (final elapsed in [14, 15, 479, 480, 959, 960, 980]) {
    testWidgets('physical snapshot restores running at $elapsed seconds with its frozen prescription', (t) async {
      final start = DateTime(2030, 2, 5, 8);
      late Directory dir;
      late ActiveSessionStore store;
      late TimerSnapshot restored;
      await t.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('running045-');
        store = ActiveSessionStore(File('${dir.path}/active.json'));
        await store.save(TimerSnapshot(
            date: '2030-02-05',
            startedAt: start.subtract(const Duration(minutes: 8)),
            mode: 'running1515',
            phase: 'trabajo',
            workStartedAt: start,
            exercises: const ['Carrera 15/15', 'Carrera 15/15'],
            prescription: const TimerPrescription.running1515()));
        restored = (await store.load())! as TimerSnapshot;
      });
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final snapshots = <TimerSnapshot>[];
      SessionDraft? result;
      var returns = 0;
      await withClock(Clock.fixed(start.add(Duration(seconds: elapsed))), () async {
        await t.pumpWidget(MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: FilledButton(
                        onPressed: () async {
                          result = await Navigator.push<SessionDraft>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => TabataScreen.running1515(
                                      date: DateTime(2040),
                                      footballFreeConfirmed: false,
                                      resume: restored,
                                      onSnapshot: snapshots.add)));
                          returns++;
                        },
                        child: const Text('Retomar'))))));
        await t.tap(find.text('Retomar'));
        await t.pumpAndSettle();
        expect(find.text('Carrera · intervalos 15/15'), findsOneWidget);
        expect(find.text('¡A TOPE!'), findsNothing);
        if (elapsed < 960) {
          final isRest = elapsed % 30 >= 15;
          expect(find.text(isRest ? 'Pausa' : 'Carrera'), findsOneWidget);
          final block = elapsed < 480 ? 1 : 2;
          final interval = (elapsed % 480) ~/ 30 + 1;
          expect(find.text('BLOQUE $block/2 · INTERVALO $interval/16'), findsOneWidget);
          await t.tap(find.text('Terminar antes'));
          await t.pump();
        }
        expect(find.text('ENFRIAMIENTO'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing, reason: 'running never asks for worst repetitions');
        await t.tap(find.text('Terminar y guardar'));
        await t.pumpAndSettle();
        expect(returns, 1);
        expect(result, isNotNull);
        expect(result!.mode, 'running1515');
        expect(result!.date, DateTime(2030, 2, 5));
        expect(result!.incomplete, elapsed < 960);
        expect(result!.totalSec - result!.warmupSec - result!.cooldownSec, elapsed.clamp(0, 960));
        final expectedRest = switch (elapsed) { 14 => 0, 15 => 0, 479 => 239, 480 => 240, 959 => 479, _ => 480 };
        expect(result!.restSec, expectedRest);
        expect(result!.sets, isEmpty);
        expect(snapshots, isNotEmpty);
        expect(snapshots.last.profile, TimerProfile.running1515);
        expect(snapshots.last.prescription!.toJson(), const TimerPrescription.running1515().toJson());
        expect(snapshots.last.workEndedAt, start.add(Duration(seconds: elapsed.clamp(0, 960))));
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      });
      await t.runAsync(() async {
        await store.save(snapshots.last);
        expect((await store.load())!.toJson(), snapshots.last.toJson());
        await dir.delete(recursive: true);
      });
    });
  }

  testWidgets('new running session emits all parameters and includes its last pause before completion', (t) async {
    var now = DateTime(2030, 2, 5, 8);
    final snapshots = <TimerSnapshot>[];
    await withClock(Clock(() => now), () async {
      await t.pumpWidget(MaterialApp(
          home: TabataScreen.running1515(date: now, footballFreeConfirmed: true, onSnapshot: snapshots.add)));
      await t.tap(find.text('Empezar intervalos'));
      await t.pump();
      expect(snapshots.last.prescription!.toJson(), const TimerPrescription.running1515().toJson());
      now = now.add(const Duration(seconds: 959));
      await t.pump(const Duration(milliseconds: 250));
      expect(find.text('Pausa'), findsOneWidget);
      expect(find.text('ENFRIAMIENTO'), findsNothing);
      now = now.add(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 250));
      expect(find.text('ENFRIAMIENTO'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(snapshots.last.workEndedAt!.difference(snapshots.last.workStartedAt!).inSeconds, 960);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
  });
}
