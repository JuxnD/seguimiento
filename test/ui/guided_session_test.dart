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
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

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

/// Circuito de 3 rondas de 2 ejercicios, 30 s de descanso entre rondas.
PlanDayDraft _circuit() => PlanDayDraft(
      weekday: 1,
      type: DayType.circuito,
      targetRounds: 3,
      restBetweenRoundsSec: 30,
      exercises: [
        PlanExerciseDraft(name: 'Flexiones', repsMin: 10),
        PlanExerciseDraft(name: 'Sentadillas', repsMin: 15),
      ],
    );

void main() {
  late Directory dir;

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
  Future<List<SessionDraft?>> pumpGuided(WidgetTester tester) async {
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
        trainingRepositoryProvider.overrideWith((ref) => throw UnimplementedError('no se usa')),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => results.add(await Navigator.push<SessionDraft>(
                  context,
                  MaterialPageRoute(builder: (_) => GuidedSessionScreen(day: _circuit(), date: DateTime(2026, 9, 24))),
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

  testWidgets('terminar antes guarda solo lo hecho y la marca como incompleta', (tester) async {
    final results = await pumpGuided(tester);

    await tester.tap(find.text('Empezar circuito'));
    await step(tester);

    // Ronda 1: dos paradas.
    expect(find.text('Primera vez hoy con este ejercicio'), findsOneWidget);
    await tester.tap(find.text('Hecho'));
    await step(tester);
    await tester.tap(find.text('Hecho'));
    await step(tester, const Duration(seconds: 10)); // 10 s de descanso

    // Se corta en pleno descanso, antes de la ronda 2.
    await tester.tap(find.text('Terminar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
    await step(tester, const Duration(seconds: 70)); // enfriamiento de más de 1 min
    await tester.tap(find.text('Terminar enfriamiento'));
    await step(tester, const Duration(seconds: 2));
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pump(const Duration(milliseconds: 400));

    final draft = results.single!;
    expect(draft.incomplete, isTrue, reason: 'se cortó antes de terminar el plan');
    expect(draft.roundsDone, 1, reason: 'solo la ronda 1 se completó');
    expect(draft.plannedRounds, 3);
    expect(draft.sets.map((s) => (s.exercise, s.reps)), [('Flexiones', 10), ('Sentadillas', 15)]);
    expect(draft.restSec, inInclusiveRange(9, 11), reason: 'el descanso en curso cuenta hasta el corte');
    expect(draft.netSec, lessThan(draft.spanSec), reason: 'el neto no incluye el descanso');
  });

  testWidgets('el acumulado de reps es por ejercicio', (tester) async {
    await pumpGuided(tester);
    await tester.tap(find.text('Empezar circuito'));
    await step(tester);

    await tester.tap(find.text('Hecho')); // Flexiones 10
    await step(tester);
    await tester.tap(find.text('Hecho')); // Sentadillas 15
    await step(tester);
    await tester.tap(find.text('Saltar descanso'));
    await step(tester);

    expect(find.text('Llevas 10 reps de Flexiones'), findsOneWidget);
    await tester.tap(find.text('Hecho'));
    await step(tester);
    expect(find.text('Llevas 15 reps de Sentadillas'), findsOneWidget);

    // Salir sin guardar para desmontar limpio.
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Salir'));
    await tester.pump(const Duration(seconds: 1));
  });
}
