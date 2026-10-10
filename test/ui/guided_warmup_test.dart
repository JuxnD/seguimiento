import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../support/sqlite_host.dart';

/// La pantalla no apaga nada de verdad en una prueba.
class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

class _NoNotifications extends NotificationService {
  _NoNotifications() : super(FlutterLocalNotificationsPlugin());

  @override
  Future<void> init() async {}

  @override
  Future<bool> scheduleRestEnd({required Duration inSeconds, required String nextLabel}) async => true;

  @override
  Future<void> cancelRestEnd() async {}

  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async {}
}

void main() {
  late Directory dir;

  setUpAll(useHostSqlite);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_guiado');
    wakelock.wakelockPlusPlatformInstance = _NoWakelock();
    // Háptica y sonido del sistema: sin plataforma, que no respondan nada.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows puede tener el archivo tomado.
    }
  });

  /// Monta el cronómetro detrás de una ruta que recoge lo que devuelve.
  Future<List<SessionDraft?>> pumpGuided(WidgetTester tester, {PlanDayDraft? day, TrainingRepository? training}) async {
    // Alta para que quepa todo y ancha porque la fuente de prueba dibuja cada
    // letra como un cuadrado (ver app_smoke_test.dart).
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final results = <SessionDraft?>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(_NoNotifications()),
        activeSessionStoreProvider.overrideWithValue(ActiveSessionStore(File('${dir.path}/sesion.json'))),
        latestWeightProvider.overrideWithValue(70),
        profileProvider.overrideWith((ref) => const Stream.empty()),
        trainingRepositoryProvider.overrideWith((ref) => training ?? (throw UnimplementedError('no se usa'))),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => results.add(await Navigator.push<SessionDraft>(
                  context,
                  MaterialPageRoute(builder: (_) => GuidedSessionScreen(day: day!, date: DateTime(2026, 9, 24))),
                )),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return results;
  }

  Future<void> step(WidgetTester tester, [Duration d = const Duration(seconds: 5)]) async {
    await tester.pump(d);
    await tester.pump(const Duration(milliseconds: 400)); // transición
  }

  /// Lee la foto cuando ya trae lo esperado. Con el equipo cargado la cola de
  /// escritura tarda más que un tiempo fijo. Se lee pocas veces y tras dejar
  /// correr la cola: en Windows, leer mientras se renombra encima hace fallar
  /// ese guardado (que la app descarta en silencio) y la foto queda vieja.
  Future<String> snapshotWhere(WidgetTester tester, bool Function(String json) ready) async {
    final file = File('${dir.path}/sesion.json');
    var last = '';
    for (var attempt = 0; attempt < 8; attempt++) {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 5));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      }
      final text = await tester.runAsync<String>(() async => file.existsSync() ? await file.readAsString() : '');
      last = text ?? '';
      if (ready(last)) return last;
    }
    return last;
  }

  /// Bloques de empuje: dos series de flexiones.
  PlanDayDraft push() => PlanDayDraft(weekday: 2, type: DayType.bloques, exercises: [
        PlanExerciseDraft(name: 'Flexiones', sets: 2, repsMin: 10, repsMax: 12),
      ]);

  Future<void> finish(WidgetTester tester) async {
    await tester.tap(find.text('Terminar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
    await step(tester, const Duration(seconds: 70));
    await tester.tap(find.text('Terminar enfriamiento'));
    await step(tester, const Duration(seconds: 2));
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('calentamiento guiado: pasos con su dosis, reloj por paso y lo marcado queda anotado', (tester) async {
    final results = await pumpGuided(tester, day: push());
    expect(find.text('CALENTAMIENTO'), findsOneWidget);
    expect(find.text('Círculos de hombros · 30 s'), findsOneWidget);
    expect(find.text('Flexiones escapulares · 2 × 8'), findsOneWidget, reason: 'activación de empuje');
    expect(find.text('Flexiones · 4'), findsOneWidget, reason: 'aproximación: 40 % de 10');
    expect(find.textContaining('0 de 7 pasos'), findsOneWidget);

    // El paso por tiempo se marca solo al terminar su reloj, no antes.
    await tester.tap(find.byTooltip('Empezar 30 s').first);
    await step(tester, const Duration(seconds: 20));
    expect(find.textContaining('0 de 7 pasos'), findsOneWidget);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('1 de 7 pasos'), findsOneWidget);

    // Marcar la aproximación arma los 2 min antes de la primera serie.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('warmup-aproximacion:Flexiones')), matching: find.byType(Checkbox)));
    await step(tester, const Duration(seconds: 1));
    expect(find.textContaining('antes de la primera serie que cuenta'), findsOneWidget);
    final snap = await snapshotWhere(tester, (j) => j.contains('aproximacion:Flexiones'));
    expect(snap, contains('aproximacion:Flexiones'), reason: 'retomar conserva lo marcado');

    await tester.tap(find.text('Empezar bloques'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Calentamiento a medias'), findsOneWidget);
    expect(find.textContaining('Marcaste 2 de 7'), findsOneWidget);
    await tester.tap(find.text('Empezar igual'));
    await step(tester, const Duration(seconds: 1));
    await finish(tester);

    final draft = results.single!;
    expect(draft.context, contains('Calentamiento: 2 de 7 pasos'));
    expect(draft.warmupSec, greaterThanOrEqualTo(30), reason: 'el tiempo real se conserva en la cuenta');
  });

  testWidgets('saltar el calentamiento queda registrado y no pregunta', (tester) async {
    final results = await pumpGuided(tester, day: push());
    await tester.tap(find.text('Saltar calentamiento'));
    await step(tester, const Duration(seconds: 1));
    expect(find.text('Calentamiento a medias'), findsNothing);
    final raw = await snapshotWhere(tester, (j) => j.contains('"warmupSkipped":true'));
    final snap = ActiveSession.fromJson(jsonDecode(raw) as Map<String, Object?>)! as GuidedSnapshot;
    expect(snap.warmupSkipped, isTrue);
    await finish(tester);
    expect(results.single!.context, contains('Calentamiento saltado'));
  });

  testWidgets('foto vieja sin calentamiento guiado: nada marcado, no se rompe', (tester) async {
    final legacy = GuidedSnapshot(
        date: '2026-09-24', startedAt: DateTime(2026, 9, 24, 7), planDayId: 1, phase: GuidedPhase.calentamiento, index: 0);
    final json = legacy.toJson()
      ..remove('warmupDone')
      ..remove('warmupSkipped');
    final back = ActiveSession.fromJson(json)! as GuidedSnapshot;
    expect(back.warmupDone, isEmpty);
    expect(back.warmupSkipped, isFalse);
  });
}
