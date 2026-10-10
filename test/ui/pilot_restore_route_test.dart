import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/app.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/auto_backup.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/features/onboarding/app_entry.dart';
import 'package:seguimiento/features/onboarding/onboarding_screen.dart';
import 'package:seguimiento/features/settings/settings_screen.dart';

import '../support/sqlite_host.dart';

/// Plan 024: la barrera de entrada con una ruta abierta encima (Ajustes) al
/// restaurar. SQLite, BackupArchive y DatabaseHost reales; espías sólo de
/// permisos, avisos, pasos y respaldo semanal.

class _SelectedFile extends FilePicker {
  _SelectedFile(this.file);
  final File file;
  @override
  Future<FilePickerResult?> pickFiles(
          {String? dialogTitle,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Function(FilePickerStatus)? onFileLoading,
          bool allowCompression = true,
          int compressionQuality = 30,
          bool allowMultiple = false,
          bool withData = false,
          bool withReadStream = false,
          bool lockParentWindow = false,
          bool readSequential = false}) async =>
      FilePickerResult([PlatformFile(name: file.uri.pathSegments.last, path: file.path, size: file.lengthSync())]);
}

class _Notifications extends NotificationService {
  _Notifications() : super(FlutterLocalNotificationsPlugin());
  int permissions = 0;
  final schedules = <List<PlannedNotification>>[];
  @override
  Future<void> init() async {}
  @override
  Future<bool> hasPermission() async {
    permissions++;
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    permissions++;
    return true;
  }

  @override
  Future<bool> canScheduleExact() async => true;
  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async => schedules.add(planned);
}

class _Steps extends StepsSync {
  _Steps(AppDatabase db)
      : super(health: const HealthConnect(), steps: StepsRepository(db), flags: LocalFlags(File('no-se-usa.json')));
  int runs = 0;
  @override
  bool get enabled => false;
  @override
  Future<StepsSyncResult> run({int days = 14, DateTime? now}) async {
    runs++;
    return const StepsSyncResult(StepsSyncOutcome.hecho);
  }
}

class _Backup extends AutoBackup {
  _Backup(DatabaseHost host, LocalFlags flags, Directory dir) : super(host: host, flags: flags, dir: dir);
  int runs = 0;
  @override
  Future<File?> runIfDue({DateTime? now}) async {
    runs++;
    return null;
  }
}

enum _Mode { sqlPending, zipPending, zipReady, cancel, rollback }

void main() {
  setUpAll(useHostSqlite);

  for (final mode in _Mode.values) {
    final title = switch (mode) {
      _Mode.sqlPending => 'SQL pendiente con Ajustes encima muestra el alta visible',
      _Mode.zipPending => 'ZIP pendiente real desde Ajustes: alta visible, Ajustes/shell fuera, guion intacto',
      _Mode.zipReady => 'ZIP listo real desde Ajustes: sigue en Ajustes con los datos del respaldo',
      _Mode.cancel => 'cancelar la confirmación no cambia base, fotos, flags ni guion',
      _Mode.rollback => 'fallo tardío revierte: alta lista, Ajustes y fotos intactos',
    };
    testWidgets(title, (tester) async {
      final deadline = Stopwatch()..start();
      late Directory root;
      late DatabaseHost host;
      late File zip;
      late File snapshot;
      late List<int> snapshotBytes;
      late File photo;
      var failNextOpen = false;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('seguimiento_024_route_');
        final sourceDir = Directory('${root.path}/source')..createSync();
        final source = DatabaseHost(
            File('${sourceDir.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
        if (mode == _Mode.zipReady || mode == _Mode.rollback) {
          await ProfileRepository(source.db)
              .confirmSetup(SetupDraft(startDate: DateTime(2026, 9, 1), stepsTarget: 8100));
          await BodyRepository(source.db).addWeight(DateTime(2026, 10, 9), 64.5);
        } else {
          expect(await source.db.select(source.db.goalVersions).get(), isEmpty);
        }
        zip = (await BackupArchive(host: source, documents: sourceDir).exportTo('${root.path}/respaldo.zip')).file;
        await source.db.close();
        final targetDir = Directory('${root.path}/target')..createSync();
        final target = File('${targetDir.path}/seguimiento.sqlite');
        host = DatabaseHost(target, (f) {
          if (failNextOpen && f.path == target.path) {
            failNextOpen = false;
            throw StateError('fallo tardío sintético');
          }
          return AppDatabase(NativeDatabase(f));
        });
        await ProfileRepository(host.db).confirmSetup(SetupDraft(startDate: DateTime(2026, 10, 10), stepsTarget: 6000));
        await ReminderRepository(host.db).ensureDefaults();
        photo = File('${targetDir.path}/fotos/vieja.jpg')
          ..createSync(recursive: true)
          ..writeAsBytesSync([4, 2]);
        snapshot = File('${targetDir.path}/sesion.json');
        await ActiveSessionStore(snapshot).save(CounterSnapshot(
            date: '2026-10-10', startedAt: DateTime(2026, 10, 10, 9), phase: CounterPhase.circuit, marks: const [60, 125]));
        snapshotBytes = snapshot.readAsBytesSync();
      });
      FilePicker.platform = _SelectedFile(zip);
      tester.view.physicalSize = const Size(1400, 7000);
      tester.view.devicePixelRatio = 1;
      final notifications = _Notifications();
      final steps = _Steps(host.db);
      final flagsFile = File('${host.file.parent.path}/flags.json');
      final flags = LocalFlags(flagsFile);
      final backup = _Backup(host, flags, host.file.parent);

      Future<void> tick() async {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
        expect(tester.takeException(), isNull);
      }

      Future<void> waitFor(bool Function() done, String what) async {
        while (!done() && deadline.elapsed < const Duration(seconds: 20)) {
          await tick();
        }
        expect(done(), isTrue, reason: 'frontera no completada: $what');
      }

      // Las consultas ya iniciadas por los widgets también necesitan avanzar
      // en FakeAsync. No esperar SQL dentro de runAsync sin bombear la app.
      Future<T> io<T>(Future<T> Function() f) async {
        var completed = false;
        T? value;
        Object? error;
        StackTrace? stack;
        await tester.runAsync(() async {
          unawaited(Future<T>.sync(f).then<void>((result) {
            value = result;
            completed = true;
          }, onError: (Object e, StackTrace s) {
            error = e;
            stack = s;
            completed = true;
          }));
        });
        await waitFor(() => completed, 'operación SQL real completada');
        if (error != null) Error.throwWithStackTrace(error!, stack!);
        return value as T;
      }

      try {
        await tester.pumpWidget(ProviderScope(overrides: [
          databaseHostProvider.overrideWithValue(host),
          localFlagsProvider.overrideWithValue(flags),
          activeSessionStoreProvider.overrideWithValue(ActiveSessionStore(snapshot)),
          notificationServiceProvider.overrideWithValue(notifications),
          stepsSyncProvider.overrideWithValue(steps),
          documentsDirProvider.overrideWith((_) => host.file.parent),
          autoBackupProvider.overrideWith((_) => backup),
          autoBackupsProvider.overrideWith((_) => []),
          appVersionProvider.overrideWith((_) => '0.0.0'),
          updateCheckProvider.overrideWith((_) => const UpdateCheck(currentVersion: '0.0.0')),
        ], child: const SeguimientoApp()));
        await waitFor(() => find.byType(HomeShell).evaluate().isNotEmpty && steps.runs == 1, 'shell listo');
        final container = ProviderScope.containerOf(tester.element(find.byType(AppEntry)), listen: false);
        await tester.tap(find.byTooltip('Ajustes'));
        await waitFor(() => find.text('Restaurar desde un respaldo').evaluate().isNotEmpty, 'Ajustes abierto');
        // Lo que el arranque escribe (permiso pedido) debe haber llegado al
        // disco antes de fijar la referencia de flags.
        await waitFor(() => flagsFile.existsSync() && flagsFile.readAsStringSync().contains('notificationsAsked'),
            'flags del arranque escritos');
        final flagsBytes = flagsFile.existsSync() ? flagsFile.readAsBytesSync() : <int>[];
        final before = (notifications.permissions, steps.runs, backup.runs);

        if (mode == _Mode.sqlPending) {
          // Estado posterior a una restauración pendiente, con escrituras Drift
          // reales y cambio de generación; no acredita restoreFrom (eso es zipPending).
          await io(() async {
            await host.db.delete(host.db.goalVersions).go();
            await host.db.update(host.db.profiles).write(const ProfilesCompanion(
                profileOrigin: Value(ProfileOrigin.newInstall),
                setupState: Value(SetupState.pending),
                setupConfirmedAt: Value(null)));
          });
          container.read(databaseGenerationProvider.notifier).state++;
        } else {
          if (mode == _Mode.rollback) failNextOpen = true;
          await tester.tap(find.text('Restaurar desde un respaldo'));
          await waitFor(() => find.text('¿Restaurar este respaldo?').evaluate().isNotEmpty, 'confirmación');
          await tester.tap(find.text(mode == _Mode.cancel ? 'Cancelar' : 'Restaurar'));
        }

        final expectedGeneration = mode == _Mode.cancel ? 0 : 1;
        final expectPending = mode == _Mode.sqlPending || mode == _Mode.zipPending;
        // Restauración REAL completada antes del oráculo visible: sin diálogos,
        // generación observada y estado del alta ya releído de la base nueva.
        await waitFor(
            () =>
                find.text('¿Restaurar este respaldo?').evaluate().isEmpty &&
                find.text('Restaurando respaldo').evaluate().isEmpty &&
                find.text('Verificando respaldo').evaluate().isEmpty &&
                container.read(databaseGenerationProvider) == expectedGeneration &&
                container.read(setupStatusProvider).valueOrNull?.pending == expectPending &&
                !container.read(setupStatusProvider).isLoading,
            'restauración completada');
        for (var i = 0; i < 10; i++) {
          await tick();
        }

        final db = host.db;
        final status = await io(() => ProfileRepository(db).setupStatus());
        final goals = await io(() => db.select(db.goalVersions).get());
        final profile = await io(() => ProfileRepository(db).get());
        final weights = await io(() => db.select(db.bodyWeights).get());
        expect(snapshot.readAsBytesSync(), snapshotBytes, reason: 'el guion en curso no es parte del respaldo');
        expect(flagsFile.existsSync() ? flagsFile.readAsBytesSync() : <int>[], flagsBytes, reason: 'flags intactos');

        if (expectPending) {
          expect((status.pending, status.origin), (true, ProfileOrigin.newInstall));
          expect(goals, isEmpty);
          expect(await io(() => personalTablesWithRows(db)), isEmpty);
          await tester.pump(const Duration(minutes: 3));
          await tick();
          expect((notifications.permissions, steps.runs, backup.runs), before, reason: 'efectos detenidos');
          expect(notifications.schedules.last, isEmpty, reason: 'avisos retirados');
          expect(find.byType(OnboardingScreen), findsOneWidget, reason: 'alta VISIBLE');
          expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
          expect(find.byType(HomeShell, skipOffstage: false), findsNothing);
          if (mode == _Mode.zipPending) {
            expect(photo.existsSync(), isFalse, reason: 'un ZIP reemplaza las fotos por las suyas (ninguna)');
          }
        } else {
          expect(status.ready, isTrue);
          expect(find.byType(SettingsScreen), findsOneWidget, reason: 'ready→ready conserva la ruta abierta');
          expect(find.byType(OnboardingScreen, skipOffstage: false), findsNothing);
          expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
          if (mode == _Mode.zipReady) {
            expect((profile.stepsTarget, profile.startDate), (8100, '2026-09-01'));
            expect(weights.map((w) => w.kg), [64.5]);
            expect(photo.existsSync(), isFalse, reason: 'el ZIP trae sus fotos (ninguna)');
          } else {
            expect((profile.stepsTarget, profile.startDate), (6000, '2026-10-10'), reason: 'sin cambios');
            expect(weights, isEmpty);
            expect(photo.readAsBytesSync(), [4, 2], reason: 'fotos intactas');
          }
          if (mode == _Mode.rollback) {
            expect(find.textContaining('No se pudo restaurar'), findsOneWidget);
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        var closed = false;
        Object? closeError;
        StackTrace? closeStack;
        await tester.runAsync(() async {
          unawaited(Future<void>.sync(host.db.close).then<void>((_) {
            closed = true;
          }, onError: (Object e, StackTrace s) {
            closeError = e;
            closeStack = s;
            closed = true;
          }));
        });
        while (!closed && deadline.elapsed < const Duration(seconds: 25)) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(closed, isTrue, reason: 'cierre real de SQLite no completado dentro de 25 s');
        if (closeError != null) Error.throwWithStackTrace(closeError!, closeStack!);
        tester.view.reset();
        await tester.runAsync(() async {
          try {
            await root.delete(recursive: true);
          } on FileSystemException {
            // Windows puede retener un archivo; carpeta sintética temporal.
          }
        });
      }
    });
  }
}
