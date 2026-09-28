import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/domain/steps.dart';

import '../support/sqlite_host.dart';

/// Health Connect de mentira: lo que la app del reloj habría escrito.
class _FakeHealth extends HealthConnect {
  _FakeHealth(this.byDay, {this.status_ = HealthConnectStatus.disponible, this.permitted = true});

  final Map<String, int> byDay;
  final HealthConnectStatus status_;
  final bool permitted;
  Object? throwOnRead;

  @override
  Future<HealthConnectStatus> status() async => status_;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Map<String, int>> stepsByDay(DateTime from, DateTime to) async {
    if (throwOnRead != null) throw throwOnRead!;
    return byDay;
  }
}

void main() {
  setUpAll(useHostSqlite);

  group('qué cifra queda en un día', () {
    test('vacío toma lo del reloj; del reloj se actualiza; a mano solo si el reloj va más alto', () {
      expect(mergeSyncedSteps(current: null, currentSource: null, synced: 4200), 4200);
      expect(mergeSyncedSteps(current: 4200, currentSource: 'health_connect', synced: 6100), 6100);
      expect(mergeSyncedSteps(current: 6100, currentSource: 'health_connect', synced: 6100), isNull);
      expect(mergeSyncedSteps(current: 1935, currentSource: 'manual', synced: 5400), 5400);
      expect(mergeSyncedSteps(current: 9000, currentSource: 'manual', synced: 5400), isNull);
      expect(mergeSyncedSteps(current: null, currentSource: null, synced: 0), isNull, reason: 'día sin datos');
    });
  });

  group('sincronización', () {
    late Directory dir;
    late AppDatabase db;
    late StepsRepository steps;
    late LocalFlags flags;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('seguimiento_pasos');
      db = openInMemoryDatabase();
      steps = StepsRepository(db);
      flags = LocalFlags(File('${dir.path}/flags.json'));
    });

    tearDown(() async {
      await db.close();
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows puede tener el archivo tomado.
      }
    });

    test('sin conectar en Ajustes no toca nada', () async {
      final sync = StepsSync(health: _FakeHealth({'2026-09-28': 5000}), steps: steps, flags: flags);
      expect((await sync.run(now: DateTime(2026, 9, 28, 20))).outcome, StepsSyncOutcome.apagado);
      expect(await steps.day(DateTime(2026, 9, 28)), isNull);
    });

    test('conectado trae los días y respeta lo anotado a mano si es mayor', () async {
      await flags.set(FlagKeys.healthConnectEnabled, true);
      await steps.setSteps(DateTime(2026, 9, 26), 12000); // fútbol, anotado a mano
      await steps.setSteps(DateTime(2026, 9, 27), 1935);
      final sync = StepsSync(
        health: _FakeHealth({'2026-09-26': 9000, '2026-09-27': 6400, '2026-09-28': 3100, '2026-09-25': 0}),
        steps: steps,
        flags: flags,
      );
      final result = await sync.run(now: DateTime(2026, 9, 28, 20));
      expect(result.outcome, StepsSyncOutcome.hecho);
      expect(result.updatedDays, 2);
      expect(await steps.day(DateTime(2026, 9, 26)), 12000);
      expect(await steps.day(DateTime(2026, 9, 27)), 6400);
      expect((await steps.row(DateTime(2026, 9, 28)))!.source, StepsSync.source);
      expect(await steps.day(DateTime(2026, 9, 25)), isNull);
      expect(sync.lastSync, DateTime(2026, 9, 28, 20));
    });

    test('sin permiso o sin Health Connect lo dice y no lanza', () async {
      await flags.set(FlagKeys.healthConnectEnabled, true);
      expect((await StepsSync(health: _FakeHealth({}, permitted: false), steps: steps, flags: flags).run()).outcome,
          StepsSyncOutcome.sinPermiso);
      expect(
          (await StepsSync(
                  health: _FakeHealth({}, status_: HealthConnectStatus.noInstalado), steps: steps, flags: flags)
              .run())
              .outcome,
          StepsSyncOutcome.noDisponible);
      final failing = _FakeHealth({})..throwOnRead = PlatformException(code: 'sin_permiso');
      expect((await StepsSync(health: failing, steps: steps, flags: flags).run()).outcome, StepsSyncOutcome.sinPermiso);
      final broken = _FakeHealth({})..throwOnRead = PlatformException(code: 'health_connect', message: 'caído');
      final r = await StepsSync(health: broken, steps: steps, flags: flags).run();
      expect(r.outcome, StepsSyncOutcome.error);
      expect(r.message, 'caído');
    });
  });
}
