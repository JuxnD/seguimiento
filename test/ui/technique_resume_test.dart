import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/guided_plan_snapshot.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/domain/technique_session.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart' show scriptDayFrom;
import 'package:seguimiento/features/training/training_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../support/sqlite_host.dart';

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

class _Notifications extends NotificationService {
  _Notifications() : super(FlutterLocalNotificationsPlugin());
  @override
  Future<void> init() async {}
  @override
  Future<bool> scheduleRestEnd({required Duration inSeconds, required String nextLabel}) async => true;
  @override
  Future<void> cancelRestEnd() async {}
}

/// Una sesión fuera del plan (sesión técnica, plan B) se retoma con su guion
/// guardado; antes se descartaba con "El día del plan ya no existe".
void main() {
  setUpAll(useHostSqlite);

  testWidgets('sesión técnica cerrada por Android: se retoma en el mismo paso', (t) async {
    final db = openInMemoryDatabase();
    final dir = Directory.systemTemp.createTempSync('tecnica');
    final store = ActiveSessionStore(File('${dir.path}/session.json'));
    wakelock.wakelockPlusPlatformInstance = _NoWakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);

    Future<T> io<T>(Future<T> Function() action) async {
      var done = false;
      final task = action();
      task.then((_) => done = true, onError: (Object _, StackTrace __) => done = true).ignore();
      for (var i = 0; i < 200 && !done; i++) {
        await t.pump(const Duration(milliseconds: 5));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      }
      if (!done) throw TimeoutException('IO no completó');
      return task;
    }

    Future<void> settle() async {
      await t.pump();
      await io(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 400));
      await io(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }

    final day = techniqueDayDraft(DateTime(2026, 10, 13));
    final script = buildScript(scriptDayFrom(day));
    final index = script.indexWhere((s) => s is WorkStep && s.exercise == 'Flexiones diamante');
    final snapshot = GuidedSnapshot(
      date: '2026-10-13',
      startedAt: clock.now().subtract(const Duration(minutes: 5)),
      planDayId: -1,
      sessionType: SessionType.trenSuperior,
      phase: GuidedPhase.trabajo,
      index: index,
      effectiveDay: freezeGuidedDay(day),
      note: 'Sesión técnica (RIR 4)',
      mode: techniqueMode,
    );
    await io(() => store.save(snapshot));
    final loaded = (await io(() => ActiveSessionStore(store.file).load()))!;

    t.view.physicalSize = const Size(1500, 6500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWithValue(db),
      activeSessionStoreProvider.overrideWithValue(store),
      localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
      notificationServiceProvider.overrideWithValue(_Notifications()),
      latestWeightProvider.overrideWithValue(70),
      profileProvider.overrideWith((ref) => const Stream.empty()),
    ], child: MaterialApp(
      home: Consumer(
        builder: (c, ref, _) =>
            Scaffold(body: TextButton(onPressed: () => resumeActiveSession(c, ref, loaded), child: const Text('retomar'))),
      ),
    )));
    await settle();
    await t.tap(find.text('retomar'));
    await settle();
    await settle();

    expect(find.textContaining('El día del plan de esa sesión ya no existe'), findsNothing);
    expect(find.text('Flexiones diamante'), findsWidgets);
    final current = await io(() => store.load()) as GuidedSnapshot;
    expect((current.index, current.planDayId, current.mode), (index, -1, techniqueMode));
    expect(freezeGuidedDay(thawGuidedDay(current.effectiveDay!)), freezeGuidedDay(day));

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 500));
    await io(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await io(db.close);
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {/* Windows conserva el handle hasta que salga flutter_tester. */}
  });
}
