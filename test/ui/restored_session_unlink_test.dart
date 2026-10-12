import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/guided_plan_snapshot.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/features/settings/restore_access.dart';
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

/// Plan 027, revisión 1. Cruce real: ZIP exportado con BackupArchive, restauración
/// común (restoreBackupFile), snapshot releído de disco y retomado con la UI.
/// El respaldo trae un martes con los MISMOS id, día, tipo y nombres pero otra
/// dosis: la estructura no prueba que sea el plan de la sesión; lo que lo
/// desvincula es la restauración exitosa.
enum _Mode { restored, cancelled, rolledBack, ordinary }

PlanDayDraft _tuesday(int sets, int repsMin, int repsMax) => PlanDayDraft(weekday: 2, type: DayType.trenSuperior, exercises: [
      PlanExerciseDraft(name: 'Dominadas australianas', sets: sets, repsMin: repsMin, repsMax: repsMax, restSec: 90),
      PlanExerciseDraft(name: 'Fondos en banco', sets: sets, repsMin: repsMin, repsMax: repsMax, restSec: 90),
    ]);

Future<int> _seed(AppDatabase db, PlanDayDraft tuesday) async {
  final draft = PlanDraft.empty(DateTime(2026, 9, 1));
  draft.days[1] = tuesday;
  await PlanRepository(db, ExerciseRepository(db)).saveAsNewVersion(draft);
  return (await db.select(db.planDays).get()).firstWhere((d) => d.weekday == 2).id;
}

void main() {
  setUpAll(useHostSqlite);

  for (final mode in _Mode.values) {
    final title = switch (mode) {
      _Mode.restored => 'restauración exitosa: el snapshot en disco suelta el id, conserva todo lo demás y se retoma con su dosis',
      _Mode.cancelled => 'restauración cancelada: el snapshot en disco queda byte a byte igual y sigue vinculado',
      _Mode.rolledBack => 'restauración fallida con rollback: el snapshot queda byte a byte igual y sigue vinculado',
      _Mode.ordinary => 'sin restauración: el guion normal se retoma vinculado a su plan',
    };
    testWidgets(title, (t) async {
      final deadline = Stopwatch()..start();
      late Directory root;
      late DatabaseHost host;
      late File zip;
      late File snapshotFile;
      late List<int> originalBytes;
      late int deviceDayId;
      var failNextOpen = false;
      final mine = _tuesday(3, 6, 8);
      wakelock.wakelockPlusPlatformInstance = _NoWakelock();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);

      await t.runAsync(() async {
        root = await Directory.systemTemp.createTemp('seguimiento_027_restore_');
        final sourceDir = Directory('${root.path}/source')..createSync();
        final source = DatabaseHost(File('${sourceDir.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
        await ProfileRepository(source.db).confirmSetup(SetupDraft(startDate: DateTime(2026, 9, 1), stepsTarget: 8100));
        await _seed(source.db, _tuesday(3, 12, 15)); // mismo id, día, tipo y nombres; otra dosis
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
        deviceDayId = await _seed(host.db, mine);
        final script = buildScript(scriptDayFrom(mine));
        snapshotFile = File('${targetDir.path}/sesion.json');
        await ActiveSessionStore(snapshotFile).save(GuidedSnapshot(
          date: '2026-10-13',
          startedAt: clock.now().subtract(const Duration(minutes: 20)),
          planDayId: deviceDayId,
          sessionType: SessionType.trenSuperior,
          phase: GuidedPhase.trabajo,
          index: script.indexWhere((s) => s is WorkStep && s.exercise == 'Fondos en banco'),
          workStartedAt: clock.now().subtract(const Duration(minutes: 12)),
          restAccumSec: 75,
          done: const [DoneStep('Dominadas australianas', 7, false, loadKg: 5, variant: 'pies elevados', rir: 2)],
          roundMarks: const [180],
          roundRests: const [60],
          warmupDone: const ['hombros'],
          lumbar: const ['leve'],
          effectiveDay: freezeGuidedDay(mine),
          note: 'nota previa',
        ));
        originalBytes = snapshotFile.readAsBytesSync();
      });

      final store = ActiveSessionStore(snapshotFile);
      final flags = LocalFlags(File('${root.path}/target/flags.json'));
      t.view.physicalSize = const Size(1500, 6500);
      t.view.devicePixelRatio = 1;
      GuidedSnapshot? loaded;
      late ProviderContainer container;

      Future<void> tick() async {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await t.pump(const Duration(milliseconds: 10));
        expect(t.takeException(), isNull);
      }

      Future<void> waitFor(bool Function() done, String what) async {
        while (!done() && deadline.elapsed < const Duration(seconds: 40)) {
          await tick();
          final snack = find.descendant(of: find.byType(SnackBar), matching: find.byType(Text));
          if (snack.evaluate().isNotEmpty && what == 'confirmación') {
            fail('aviso inesperado esperando $what: ${(snack.evaluate().first.widget as Text).data}');
          }
        }
        expect(done(), isTrue,
            reason: 'no completó: $what; textos: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}');
      }

      Future<T> io<T>(Future<T> Function() f) async {
        var completed = false;
        T? value;
        Object? error;
        await t.runAsync(() async {
          unawaited(Future<T>.sync(f).then<void>((v) {
            value = v;
            completed = true;
          }, onError: (Object e, StackTrace _) {
            error = e;
            completed = true;
          }));
        });
        await waitFor(() => completed, 'operación real');
        if (error != null) throw error!;
        return value as T;
      }

      try {
        await t.pumpWidget(ProviderScope(overrides: [
          databaseHostProvider.overrideWithValue(host),
          activeSessionStoreProvider.overrideWithValue(store),
          localFlagsProvider.overrideWithValue(flags),
          documentsDirProvider.overrideWith((_) => host.file.parent),
          notificationServiceProvider.overrideWithValue(_Notifications()),
          latestWeightProvider.overrideWithValue(70),
          profileProvider.overrideWith((ref) => const Stream.empty()),
        ], child: MaterialApp(
          home: Consumer(
            builder: (c, ref, _) => Scaffold(
              body: Column(children: [
                TextButton(onPressed: () => restoreBackupFile(c, ref, zip, 'respaldo.zip'), child: const Text('restaurar')),
                TextButton(onPressed: () => resumeActiveSession(c, ref, loaded!), child: const Text('retomar')),
              ]),
            ),
          ),
        )));
        container = ProviderScope.containerOf(t.element(find.text('restaurar')), listen: false);
        await tick();

        if (mode != _Mode.ordinary) {
          if (mode == _Mode.rolledBack) failNextOpen = true;
          await t.tap(find.text('restaurar'));
          await waitFor(() => find.text('¿Restaurar este respaldo?').evaluate().isNotEmpty, 'confirmación');
          await t.tap(find.text(mode == _Mode.cancelled ? 'Cancelar' : 'Restaurar'));
          final generation = mode == _Mode.cancelled ? 0 : 1;
          await waitFor(
              () =>
                  find.text('¿Restaurar este respaldo?').evaluate().isEmpty &&
                  find.text('Restaurando respaldo').evaluate().isEmpty &&
                  find.text('Verificando respaldo').evaluate().isEmpty &&
                  container.read(databaseGenerationProvider) == generation,
              'restauración terminada');
          for (var i = 0; i < 10; i++) {
            await tick();
          }
        }

        // Releído de disco, como lo vería el arranque siguiente.
        final onDisk = await io(() => ActiveSessionStore(snapshotFile).load()) as GuidedSnapshot;
        loaded = onDisk;
        if (mode == _Mode.restored) {
          final db = host.db;
          final restoredDay = await io(() => (db.select(db.planDays)..where((d) => d.id.equals(deviceDayId))).getSingle());
          expect(restoredDay.weekday, 2, reason: 'el id existe en la base restaurada y parece el mismo día');
          final original = jsonDecode(utf8.decode(originalBytes)) as Map<String, Object?>;
          final now = onDisk.toJson();
          expect(now['planDayId'], -1);
          expect(now['note'], 'nota previa. Recuperada tras restaurar: no se pudo identificar el plan de origen');
          for (final k in original.keys.where((k) => k != 'planDayId' && k != 'note')) {
            expect(jsonEncode(now[k]), jsonEncode(original[k]), reason: 'campo conservado: $k');
          }
        } else {
          expect(snapshotFile.readAsBytesSync(), originalBytes);
          expect(onDisk.planDayId, deviceDayId);
        }

        await t.tap(find.text('retomar'));
        await waitFor(() => find.text('Fondos en banco').evaluate().isNotEmpty, 'cronómetro abierto');
        for (var i = 0; i < 10; i++) {
          await tick();
        }
        expect(find.text('Sesión sin su guion'), findsNothing);
        final current = await io(() => ActiveSessionStore(snapshotFile).load()) as GuidedSnapshot;
        expect(current.planDayId, mode == _Mode.restored ? -1 : deviceDayId);
        final frozen = thawGuidedDay(current.effectiveDay!);
        expect((frozen.exercises.first.sets, frozen.exercises.first.repsMin, frozen.exercises.first.repsMax), (3, 6, 8),
            reason: 'la dosis original, no la del respaldo');
        expect(current.done.single.loadKg, 5);
        expect(current.roundMarks, [180]);
        expect(current.restAccumSec, 75);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 500));
        var closed = false;
        await t.runAsync(() async {
          unawaited(Future<void>.sync(host.db.close).then<void>((_) => closed = true, onError: (Object _) => closed = true));
        });
        while (!closed && deadline.elapsed < const Duration(seconds: 60)) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await t.pump(const Duration(milliseconds: 10));
        }
        t.view.reset();
        await t.runAsync(() async {
          try {
            await root.delete(recursive: true);
          } on FileSystemException {/* Windows retiene el handle. */}
        });
      }
    });
  }
}
