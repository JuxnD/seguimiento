import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/main.dart' as app;

/// SÓLO emulador QA051 nuevo, sin red/cuentas. Datos persistidos sintéticos;
/// runner comprueba serial/qemu/procedencia antes de invocar este archivo.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'nativo051: actividad guardada, Rayito y widget; intentwarm vuelve a Hoy',
      (tester) async {
    final host = await DatabaseHost.open();
    final day = DateUtils.dateOnly(DateTime.now());
    expect(await host.db.select(host.db.sessions).get(), isEmpty,
        reason: 'sandbox nueva obligatoria');
    final ex = ExerciseRepository(host.db);
    final plan = PlanRepository(host.db, ex);
    final setup = SetupDraft(startDate: day, stepsTarget: 5000)
      ..clearNutrition();
    expect(
        await ProfileRepository(host.db).confirmSetup(setup, now: day), isTrue);
    final draft = PlanDraft.empty(day);
    for (final d in draft.days) {
      d.type = DayType.trenSuperior;
    }
    await plan.saveAsNewVersion(draft);
    await host.db.close();
    final flags = await LocalFlags.open();
    await flags.set(FlagKeys.notificationsAsked, true);
    await app.main();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Nivel 1 de 8 · Sin racha todavía'), findsOneWidget);
    final writer = await DatabaseHost.open();
    await TrainingRepository(writer.db, ExerciseRepository(writer.db)).save(
        SessionDraft(
            date: day,
            type: SessionType.movilidad,
            totalSec: 60,
            incomplete: true));
    await writer.db.close();
    // Reload via lifecycle, as the app does after a native return.
    final started = await Process.run('/system/bin/am', [
      'start',
      '-n',
      'com.juandiego.seguimiento/.MainActivity',
      '--ez',
      'rayito_open_today',
      'true'
    ]);
    expect(started.exitCode, 0);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Nivel 2 de 8 · 1 día de racha'), findsOneWidget);
    await tester.tap(find.text('Cuerpo').last);
    await tester.pump(const Duration(milliseconds: 500));
    final warm = await Process.run('/system/bin/am', [
      'start',
      '-n',
      'com.juandiego.seguimiento/.MainActivity',
      '--ez',
      'rayito_open_today',
      'true'
    ]);
    expect(warm.exitCode, 0);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Nivel 2 de 8 · 1 día de racha'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.convertFlutterSurfaceToImage();
    await binding.takeScreenshot('native051-hoy');
  });
}
