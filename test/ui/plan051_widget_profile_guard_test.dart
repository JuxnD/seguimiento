import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/app.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/app/startup_error.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/auto_backup.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/rayito_widget_bridge.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/features/onboarding/onboarding_screen.dart';
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

class _Notifications extends NotificationService {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> canScheduleExact() async => true;
  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async {}
}

class _Steps extends StepsSync {
  _Steps(AppDatabase db, LocalFlags flags)
      : super(
            health: const HealthConnect(),
            steps: StepsRepository(db),
            flags: flags);
  @override
  bool get enabled => false;
}

class _Backup extends AutoBackup {
  _Backup(DatabaseHost host, LocalFlags flags, Directory dir)
      : super(host: host, flags: flags, dir: dir);
  @override
  Future<File?> runIfDue({DateTime? now}) async => null;
}

void main() {
  setUpAll(useHostSqlite);
  const channel = MethodChannel('seguimiento/widget');
  const ready = SetupStatus(origin: 'legacyUnknown', state: 'ready');
  const pending = SetupStatus(origin: 'new', state: 'pending');
  Future<T> drive<T>(WidgetTester t, Future<T> Function() f) async {
    var done = false;
    T? value;
    Object? error;
    unawaited(f().then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    }));
    for (var i = 0; i < 200 && !done; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    if (!done) fail('IO sintético no terminó');
    if (error != null) throw error!;
    return value as T;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
  }

  for (final mode in [
    'ready-pending',
    'ready-error',
    'initial-pending',
    'initial-error',
    'startup-error'
  ]) {
    testWidgets('widget pierde caché anterior en $mode', (t) async {
      final dir = Directory.systemTemp.createTempSync('myprime051-guard');
      final db = openInMemoryDatabase();
      final host = DatabaseHost(File('${dir.path}/unused.sqlite'), (_) => db,
          initial: db);
      final flags = LocalFlags(File('${dir.path}/flags.json'));
      flags.file.writeAsStringSync('{"notificationsAsked":true}');
      debugPrint('GUARD:setup-start');
      await drive(t, () => asExistingUser(db));
      debugPrint('GUARD:setup-done');
      final states = StreamController<SetupStatus>.broadcast();
      final bridge = RayitoWidgetBridge(android: true);
      final calls = <String>[];
      Map<String, Object?>? cache = {'title': 'Rayito · Prime', 'streak': '30 días de racha'};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'update') {
          cache = Map<String, Object?>.from(call.arguments as Map<Object?, Object?>);
        }
        if (call.method == 'clear') cache = null;
        return call.method == 'consumeOpenToday' ? false : 1;
      });
      try {
        await t.pumpWidget(ProviderScope(
            overrides: [
              databaseHostProvider.overrideWithValue(host),
              localFlagsProvider.overrideWithValue(flags),
              activeSessionStoreProvider.overrideWithValue(
                  ActiveSessionStore(File('${dir.path}/session.json'))),
              notificationServiceProvider.overrideWithValue(_Notifications()),
              stepsSyncProvider.overrideWithValue(_Steps(db, flags)),
              documentsDirProvider.overrideWith((_) => dir),
              autoBackupProvider.overrideWith((_) => _Backup(host, flags, dir)),
              autoBackupsProvider.overrideWith((_) => []),
              updateCheckProvider.overrideWith(
                  (_) => const UpdateCheck(currentVersion: '1.25.0')),
              setupStatusProvider.overrideWith((_) => states.stream),
              rayitoWidgetBridgeProvider.overrideWithValue(bridge),
            ],
            child: mode == 'startup-error'
                ? StartupErrorApp(
                    error: StateError('synthetic database opening failure'))
                : const SeguimientoApp()));
        debugPrint('GUARD:mounted');
        if (mode.startsWith('ready-')) {
          states.add(ready);
          await settle(t);
          expect(find.byType(HomeShell), findsOneWidget);
          expect(cache, isNotNull);
        }
        if (mode.endsWith('pending')) states.add(pending);
        if (mode.endsWith('error') && mode != 'startup-error') {
          states.addError(StateError('synthetic invalid profile'));
        }
        await settle(t);
        if (mode.endsWith('pending')) {
          expect(find.byType(OnboardingScreen), findsOneWidget);
        }
        if (mode == 'startup-error') {
          expect(find.text('My Prime no pudo arrancar'), findsOneWidget);
        }
        expect(calls, contains('clear'),
            reason: 'no puede conservar actividad del perfil previo');
        expect(cache, isNull, reason: 'el oráculo relee la caché de frontera');
        expect(t.takeException(), isNull);
      } finally {
        debugPrint('GUARD:teardown-start');
        await t.pumpWidget(const SizedBox());
        await settle(t);
        await drive(t, states.close);
        debugPrint('GUARD:stream-closed');
        await drive(t, db.close);
        debugPrint('GUARD:db-closed');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        dir.deleteSync(recursive: true);
      }
    });
  }
}
