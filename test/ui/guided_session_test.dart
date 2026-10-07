import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart';
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
                  MaterialPageRoute(builder: (_) => GuidedSessionScreen(day: day ?? _circuit(), date: DateTime(2026, 9, 24))),
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

  /// Empieza el circuito sin calentar: el aviso de calentamiento corto sale y
  /// se acepta.
  Future<void> startNow(WidgetTester tester) async {
    await tester.tap(find.text('Empezar circuito'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Calentamiento corto'), findsOneWidget);
    await tester.tap(find.text('Empezar igual'));
    await step(tester);
  }

  testWidgets('terminar antes guarda solo lo hecho y la marca como incompleta', (tester) async {
    final results = await pumpGuided(tester);

    await startNow(tester);

    // Ronda 1: dos paradas.
    expect(find.text('Aún sin reps registradas en esta sesión'), findsOneWidget);
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
    expect(draft.roundRestSec.single, inInclusiveRange(9, 11), reason: 'el descanso es de la ronda 1');
    expect(draft.roundWorkSec, [draft.roundMarksSec.single], reason: 'la ronda 1 no tiene descanso delante');
  });

  testWidgets('cada ronda separa su trabajo del descanso que la precede', (tester) async {
    final results = await pumpGuided(tester);
    await startNow(tester);

    // Ronda 1: 10 s de trabajo.
    await tester.tap(find.text('Hecho'));
    await step(tester);
    await tester.tap(find.text('Hecho'));
    await step(tester, const Duration(seconds: 20)); // 20 s de descanso

    await tester.tap(find.text('Saltar descanso'));
    await step(tester);
    // Ronda 2.
    await tester.tap(find.text('Hecho'));
    await step(tester);
    await tester.tap(find.text('Hecho'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Terminar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
    await step(tester, const Duration(seconds: 70));
    await tester.tap(find.text('Terminar enfriamiento'));
    await step(tester, const Duration(seconds: 2));
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pump(const Duration(milliseconds: 400));

    final draft = results.single!;
    expect(draft.roundMarksSec, hasLength(2));
    final rest = draft.roundRestSec.first;
    expect(rest, inInclusiveRange(19, 21));
    final lap2 = draft.roundMarksSec[1] - draft.roundMarksSec[0];
    expect(draft.roundWorkSec![1], lap2 - rest, reason: 'la vuelta 2 sin el descanso previo');
    expect(draft.roundWorkSec![1], inInclusiveRange(9, 12));
  });

  testWidgets('un doble toque en "Hecho" no salta el descanso ni la parada siguiente', (tester) async {
    final results = await pumpGuided(tester);
    await startNow(tester);

    // Doble toque en Flexiones: el segundo cae sobre Sentadillas recién
    // aparecida y no debe darla por hecha.
    await tester.tap(find.text('Hecho'));
    await tester.pump(const Duration(milliseconds: 300));
    // En plena transición hay dos "Hecho": el de encima es el del paso nuevo.
    await tester.tap(find.text('Hecho').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sentadillas'), findsWidgets);
    expect(find.text('DESCANSO'), findsNothing);

    // Cerrar la ronda y tocar otra vez en el mismo sitio: cae sobre "Saltar
    // descanso", que aún no responde. Era el 0:00 que inflaba la ronda (§16.9).
    await step(tester);
    await tester.tap(find.text('Hecho'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Saltar descanso'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('DESCANSO'), findsOneWidget, reason: 'el descanso sigue');

    await step(tester, const Duration(seconds: 30));
    await tester.tap(find.text('Terminar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
    await step(tester, const Duration(seconds: 70));
    await tester.tap(find.text('Terminar enfriamiento'));
    await step(tester, const Duration(seconds: 2));
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pump(const Duration(milliseconds: 400));

    final draft = results.single!;
    expect(draft.roundRestSec.first, greaterThanOrEqualTo(28), reason: 'el descanso se midió entero');
  });

  testWidgets('el cierre de un circuito pide técnica, rango y recuperación', (tester) async {
    final results = await pumpGuided(tester);
    await startNow(tester);
    await tester.tap(find.text('Hecho'));
    await step(tester);
    await tester.tap(find.text('Terminar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
    await step(tester, const Duration(seconds: 70));
    await tester.tap(find.text('Terminar enfriamiento'));
    await step(tester, const Duration(seconds: 2));

    expect(find.text('¿Cómo salió?'), findsOneWidget);
    await tester.tap(find.text('Sí').at(0));
    await tester.tap(find.text('Sí').at(1));
    await tester.tap(find.text('No').at(2));
    await tester.pump();
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pump(const Duration(milliseconds: 400));

    final draft = results.single!;
    expect((draft.techniqueOk, draft.fullRange, draft.recoveryOk), (true, true, false));
  });

  testWidgets('al terminar el enfriamiento la sesión queda guardada sin revisar (§16.9)', (tester) async {
    final db = openInMemoryDatabase();
    final training = TrainingRepository(db, ExerciseRepository(db));
    // La base corre sobre el reloj falso de la prueba: hay que bombear
    // mientras se espera una consulta.
    Future<T> wait<T>(Future<T> f) async {
      var done = false;
      late T value;
      unawaited(f.then((v) {
        value = v;
        done = true;
      }));
      for (var i = 0; i < 200 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(done, isTrue, reason: 'la consulta no terminó');
      return value;
    }

    final results = await pumpGuided(tester, training: training);
    await startNow(tester);
    await tester.tap(find.text('Hecho'));
    await step(tester);
    await tester.tap(find.text('Hecho'));
    await step(tester);
    await tester.tap(find.text('Terminar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
    await step(tester, const Duration(seconds: 70));
    await tester.tap(find.text('Terminar enfriamiento'));
    await step(tester, const Duration(seconds: 2));

    final saved = await wait(db.select(db.sessions).getSingle());
    expect(saved.pendingReview, isTrue);
    expect(saved.roundsDone, 1);
    expect(find.textContaining('Ya quedó guardada'), findsOneWidget);
    expect(File('${dir.path}/sesion.json').existsSync(), isFalse, reason: 'la foto ya no hace falta');

    // Salir del resumen sin "Revisar y guardar" no la pierde.
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    expect(results.single, isNull);
    expect((await wait(db.select(db.sessions).getSingle())).pendingReview, isTrue);
    await wait(db.close());
  });

  testWidgets('el acumulado de reps es por ejercicio', (tester) async {
    await pumpGuided(tester);
    await startNow(tester);

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

  testWidgets('un aguante por lado: derecho, luego izquierdo, con cronómetro y descanso entre series', (tester) async {
    final day = PlanDayDraft(weekday: 1, type: DayType.bloques, exercises: [
      PlanExerciseDraft(name: 'Plancha lateral', sets: 2, holdSecMin: 10, holdSecMax: 15, perSide: true),
    ]);
    final results = await pumpGuided(tester, day: day);
    await tester.tap(find.text('Empezar bloques'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Empezar igual'));
    await step(tester, const Duration(seconds: 1));

    expect(find.text('SERIE 1/2 · LADO DERECHO'), findsOneWidget);
    expect(find.text('Lado derecho'), findsOneWidget);
    expect(find.text('10–15 s'), findsOneWidget, reason: 'sin "por lado": este paso ya es un lado');

    // Colocarse 5 s y aguantar hasta el máximo: pasa solo al otro lado.
    await tester.tap(find.text('Empezar lado derecho'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('colócate'), findsOneWidget);
    for (var i = 0; i < 21; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SERIE 1/2 · LADO IZQUIERDO'), findsOneWidget, reason: 'sin descanso entre lados');

    // El izquierdo se cierra a mano a los 12 s.
    await tester.tap(find.text('Empezar lado izquierdo'));
    for (var i = 0; i < 17; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('ya puedes soltar · máx 15 s'), findsOneWidget);
    await tester.tap(find.text('Hecho'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('DESCANSO'), findsOneWidget, reason: 'el plan no fija descanso: 60 s por defecto');
    expect(find.textContaining('plan 60 s'), findsOneWidget);
    // "Saltar" se habilita a los 3 s: antes sería un doble toque de "Hecho".
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Saltar descanso'));
    await step(tester, const Duration(seconds: 1));
    expect(find.text('SERIE 2/2 · LADO DERECHO'), findsOneWidget);

    await tester.tap(find.text('Terminar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
    await step(tester, const Duration(seconds: 70));
    await tester.tap(find.text('Terminar enfriamiento'));
    await step(tester, const Duration(seconds: 2));
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pump(const Duration(milliseconds: 400));

    final draft = results.single!;
    expect(draft.sets.map((s) => s.exercise), ['Plancha lateral', 'Plancha lateral']);
    expect(draft.sets.first.reps, 15, reason: 'se guardan los segundos aguantados');
    expect(draft.sets.last.reps, inInclusiveRange(11, 13));
  });
}
