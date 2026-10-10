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
import 'package:seguimiento/data/database.dart' show openInMemoryDatabase;
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../support/sqlite_host.dart';

/// Molestias sin base: el cronómetro de prueba congela el reloj.
class _Sore extends RecoveryRepository {
  _Sore(this.byDay) : super(openInMemoryDatabase());

  final Map<DateTime, Map<String, int>> byDay;

  @override
  Future<Map<DateTime, Map<String, int>>> sorenessRange(DateTime today, {int days = 7}) async => byDay;
}

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
  Future<List<SessionDraft?>> pumpGuided(WidgetTester tester,
      {PlanDayDraft? day, TrainingRepository? training, RecoveryRepository? recovery}) async {
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
        if (recovery != null) recoveryRepositoryProvider.overrideWithValue(recovery),
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

  /// La foto se escribe en cola: avanzar los dos relojes hasta que llegue.
  Future<void> flushStore(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 5));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
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
    await flushStore(tester);
    final snap = await tester.runAsync(() => File('${dir.path}/sesion.json').readAsString());
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
    await flushStore(tester);
    final raw = (await tester.runAsync(() => File('${dir.path}/sesion.json').readAsString()))!;
    final snap = ActiveSession.fromJson(jsonDecode(raw) as Map<String, Object?>)! as GuidedSnapshot;
    expect(snap.warmupSkipped, isTrue);
    await finish(tester);
    expect(results.single!.context, contains('Calentamiento saltado'));
  });

  testWidgets('molestia en el registro: aviso visible y los mismos pasos', (tester) async {
    // Lo que devuelve el repositorio con hombro 5/10 y rodilla 2/10 ayer (la
    // lectura SQLite real está en test/data/warmup_soreness_data_test.dart).
    await pumpGuided(tester, day: push(), recovery: _Sore({DateTime(2026, 9, 23): {'Hombro': 5, 'Rodilla': 2}}));
    await flushStore(tester);
    expect(find.textContaining('Molestia en hombro (5/10)'), findsOneWidget);
    expect(find.textContaining('Molestia en rodilla'), findsNothing, reason: '2/10 no llega al umbral');
    expect(find.textContaining('0 de 7 pasos'), findsOneWidget, reason: 'la molestia no agrega ejercicios');
    expect(find.text('Dislocaciones con banda · 30 s'), findsNothing);
  });

  testWidgets('SQLite a pantalla: hombro reciente avisa sin cambiar ni completar el bloque', (tester) async {
    final db = openInMemoryDatabase();
    final recovery = RecoveryRepository(db);
    try {
      await tester.runAsync(() async {
        await recovery.setSoreness(DateTime(2026, 9, 23), {'Hombro': 5, 'Rodilla': 2});
        await recovery.setSoreness(DateTime(2026, 9, 20), {'Codo': 6});
      });

      await pumpGuided(tester, day: push(), recovery: recovery);
      await flushStore(tester);
      expect(find.textContaining('Molestia en hombro (5/10)'), findsOneWidget);
      expect(find.textContaining('Molestia en rodilla'), findsNothing, reason: '2/10 no llega al umbral');
      expect(find.textContaining('Molestia en codo'), findsNothing, reason: 'el registro es de hace cuatro días');
      expect(find.textContaining('0 de 7 pasos'), findsOneWidget);
      expect(find.text('Dislocaciones con banda · 30 s'), findsNothing);
      for (final label in const [
        'Círculos de hombros · 30 s',
        'Rotación torácica en cuatro apoyos · 30 s',
        'Balanceos de pierna · 30 s',
        'Movilidad de tobillo contra la pared · 30 s',
        'Flexiones escapulares · 2 × 8',
        'Muñecas (planche) · 30 s',
        'Flexiones · 4',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'se conserva el bloque de empuje');
      }
      final raw = (await tester.runAsync(() => File('${dir.path}/sesion.json').readAsString()))!;
      final snap = ActiveSession.fromJson(jsonDecode(raw) as Map<String, Object?>)! as GuidedSnapshot;
      expect(snap.warmupDone, isEmpty, reason: 'leer una molestia no equivale a completar un paso');
      expect(snap.warmupSkipped, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final closing = db.close();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await closing;
    }
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
