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
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/session_script.dart';
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

/// Plan 027. El cronómetro vive en un archivo fuera de SQLite: tras restaurar
/// una copia más vieja, el id del día guardado puede no existir o ser de otro
/// día. El guion congelado manda; nunca se descarta ni se asigna a un plan ajeno.
void main() {
  setUpAll(useHostSqlite);

  /// Sesión de tren superior, ya con dosis, marcas y calentamiento.
  PlanDayDraft frozenDay() => PlanDayDraft(weekday: 2, type: DayType.trenSuperior, exercises: [
        PlanExerciseDraft(name: 'Dominadas australianas', sets: 3, repsMin: 6, repsMax: 8, restSec: 90),
        PlanExerciseDraft(name: 'Fondos en banco', sets: 3, repsMin: 8, repsMax: 10, restSec: 90),
      ]);

  Future<void> run(
    WidgetTester t,
    Future<void> Function(
      Future<void> Function() settle,
      AppDatabase db,
      ActiveSessionStore store,
      Future<void> Function(ActiveSession) resume,
    ) body,
  ) async {
    final db = openInMemoryDatabase();
    final dir = Directory.systemTemp.createTempSync('restaurada');
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

    t.view.physicalSize = const Size(1500, 6500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    ActiveSession? pending;
    await t.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWithValue(db),
      activeSessionStoreProvider.overrideWithValue(store),
      localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
      notificationServiceProvider.overrideWithValue(_Notifications()),
      latestWeightProvider.overrideWithValue(70),
      profileProvider.overrideWith((ref) => const Stream.empty()),
    ], child: MaterialApp(
      home: Consumer(
        builder: (c, ref, _) => Scaffold(
            body: TextButton(onPressed: () => resumeActiveSession(c, ref, pending!), child: const Text('retomar'))),
      ),
    )));
    await settle();

    Future<void> resume(ActiveSession s) async {
      pending = s;
      await t.tap(find.text('retomar'));
      await settle();
      await settle();
    }

    await body(settle, db, store, resume);
    // Las pruebas guardan con `io` implícito: esperar a que el último save termine.
    final reload = ActiveSessionStore(store.file);
    await io(reload.load);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 500));
    await io(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await io(db.close);
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {/* Windows conserva el handle hasta que salga flutter_tester. */}
  }

  GuidedSnapshot snapshot({required int planDayId, Map<String, Object?>? day, String? note}) {
    final d = frozenDay();
    final script = buildScript(scriptDayFrom(d));
    final index = script.indexWhere((s) => s is WorkStep && s.exercise == 'Fondos en banco');
    return GuidedSnapshot(
      date: '2026-10-13',
      startedAt: clock.now().subtract(const Duration(minutes: 20)),
      planDayId: planDayId,
      sessionType: SessionType.trenSuperior,
      phase: GuidedPhase.trabajo,
      index: index,
      workStartedAt: clock.now().subtract(const Duration(minutes: 12)),
      done: const [DoneStep('Dominadas australianas', 8, false, loadKg: 5, variant: 'pies elevados', rir: 2)],
      roundMarks: const [180],
      warmupDone: const ['hombros'],
      effectiveDay: day ?? freezeGuidedDay(d),
      note: note,
    );
  }

  /// Plan de la base "restaurada": un día descanso el viernes y otro.
  Future<int> seedPlan(AppDatabase db,
      {required DayType friday, DayType tuesday = DayType.descanso, List<PlanExerciseDraft>? tuesdayExercises}) async {
    final draft = PlanDraft.empty(DateTime(2026, 9, 1));
    draft.days[1] = PlanDayDraft(
        weekday: 2,
        type: tuesday,
        exercises: tuesdayExercises ?? (tuesday == DayType.trenSuperior ? frozenDay().exercises : []));
    draft.days[4] = PlanDayDraft(weekday: 5, type: friday);
    await PlanRepository(db, ExerciseRepository(db)).saveAsNewVersion(draft);
    final days = await db.select(db.planDays).get();
    return days.firstWhere((d) => d.weekday == (tuesday == DayType.trenSuperior ? 2 : 5)).id;
  }

  testWidgets('el id del día no existe en la copia restaurada: se retoma con el guion congelado', (t) async {
    await run(t, (settle, db, store, resume) async {
      await seedPlan(db, friday: DayType.descanso);
      await resume(snapshot(planDayId: 99));

      expect(find.textContaining('ya no existe'), findsNothing);
      expect(find.text('Fondos en banco'), findsWidgets);
      final current = await t.runAsync(store.load) as GuidedSnapshot?;
      expect(current, isNotNull, reason: 'el intento no se descarta en silencio');
      expect(current!.planDayId, -1, reason: 'sin referencia a un plan que no es de este dispositivo');
      expect(current.done.single.loadKg, 5);
      expect(current.done.single.variant, 'pies elevados');
      expect(current.roundMarks, [180]);
      expect(current.warmupDone, ['hombros']);
      expect(current.index, snapshot(planDayId: 99).index);
      expect(current.note, contains('plan'), reason: 'el contexto lo marca como recuperado');
    });
  });

  testWidgets('el mismo id pertenece a otro día de otra base: no se asigna a ese plan', (t) async {
    await run(t, (settle, db, store, resume) async {
      final foreign = await seedPlan(db, friday: DayType.piernas);
      await resume(snapshot(planDayId: foreign));

      expect(find.text('Fondos en banco'), findsWidgets);
      expect(find.text('Sentadilla'), findsNothing);
      final current = await t.runAsync(store.load) as GuidedSnapshot?;
      expect(current, isNotNull);
      expect(current!.planDayId, -1, reason: 'un día ajeno con el mismo id no es el plan de la sesión');
      expect(current.done.single.reps, 8);
    });
  });

  testWidgets('el id coincide con el mismo día: se conserva el vínculo normal', (t) async {
    await run(t, (settle, db, store, resume) async {
      final same = await seedPlan(db, friday: DayType.descanso, tuesday: DayType.trenSuperior);
      await resume(snapshot(planDayId: same));

      expect(find.text('Fondos en banco'), findsWidgets);
      final current = await t.runAsync(store.load) as GuidedSnapshot?;
      expect(current!.planDayId, same);
      expect(current.note, isNull);
    });
  });

  testWidgets('mismo martes y tipo con otros ejercicios: el guion se retoma pero no se vincula', (t) async {
    await run(t, (settle, db, store, resume) async {
      final foreign = await seedPlan(db,
          friday: DayType.descanso,
          tuesday: DayType.trenSuperior,
          tuesdayExercises: [PlanExerciseDraft(name: 'Remo invertido', sets: 5, repsMin: 3, repsMax: 5)]);
      await resume(snapshot(planDayId: foreign));

      expect(find.text('Fondos en banco'), findsWidgets);
      final current = await t.runAsync(store.load) as GuidedSnapshot?;
      expect(current!.planDayId, -1);
      expect(current.note, contains('plan'));
      expect(current.done.single.loadKg, 5);
    });
  });

  testWidgets('el guion trae un bloque añadido (escalera): sigue siendo el mismo día y se vincula', (t) async {
    await run(t, (settle, db, store, resume) async {
      final same = await seedPlan(db, friday: DayType.descanso, tuesday: DayType.trenSuperior);
      final withLadder = frozenDay();
      withLadder.exercises.insert(
          0, PlanExerciseDraft(name: 'Dragon flag', sets: 2, repsMin: 3, repsMax: 5, block: 'escalera de core'));
      final base = snapshot(planDayId: same, day: freezeGuidedDay(withLadder));
      await resume(base);

      final current = await t.runAsync(store.load) as GuidedSnapshot?;
      expect(current!.planDayId, same);
    });
  });

  testWidgets('legado sin lo hecho y un día ajeno con el mismo id: pide decisión, no reconstruye solo', (t) async {
    await run(t, (settle, db, store, resume) async {
      final foreign = await seedPlan(db, friday: DayType.descanso, tuesday: DayType.trenSuperior);
      final legacy = GuidedSnapshot(
        date: '2026-10-13',
        startedAt: clock.now().subtract(const Duration(minutes: 20)),
        planDayId: foreign,
        phase: GuidedPhase.trabajo,
        index: 3,
      );
      await t.runAsync(() => store.save(legacy));
      await resume(legacy);

      expect(find.text('Sesión sin su guion'), findsOneWidget);
      expect(find.textContaining('no se puede comprobar'), findsOneWidget);
      expect(find.text('Fondos en banco'), findsNothing, reason: 'no se arrancó el cronómetro por presunción');
      await t.tap(find.text('Dejarla pendiente'));
      await settle();
      expect(await t.runAsync(store.load), isNotNull);

      await resume(legacy);
      await t.tap(find.text('Retomar con ese día'));
      await settle();
      await settle();
      expect(find.text('Sesión sin su guion'), findsNothing);
      final current = await t.runAsync(store.load) as GuidedSnapshot?;
      expect(current!.effectiveDay, isNotNull, reason: 'el cronómetro arrancó y congeló el guion');
      expect(current.planDayId, -1, reason: 'confirmado a mano, pero sin vincular al plan');
      expect(current.note, contains('plan'));
    });
  });

  testWidgets('snapshot legado sin guion y sin día: se conserva y se pide decisión', (t) async {
    await run(t, (settle, db, store, resume) async {
      await seedPlan(db, friday: DayType.descanso);
      final legacy = GuidedSnapshot(
        date: '2026-10-13',
        startedAt: clock.now().subtract(const Duration(minutes: 20)),
        planDayId: 99,
        phase: GuidedPhase.trabajo,
        index: 3,
      );
      await t.runAsync(() => store.save(legacy));
      await resume(legacy);

      expect(find.text('Sesión sin su guion'), findsOneWidget);
      expect(await t.runAsync(store.load), isNotNull, reason: 'abrir el aviso no borra el archivo');
      await t.tap(find.text('Dejarla pendiente'));
      await settle();
      expect(await t.runAsync(store.load), isNotNull);

      await resume(legacy);
      await t.tap(find.text('Descartarla'));
      await settle();
      expect(await t.runAsync(store.load), isNull);
    });
  });

  testWidgets('legado cuyo id es de un día con otros ejercicios: no se reconstruye con ese día', (t) async {
    await run(t, (settle, db, store, resume) async {
      final foreign = await seedPlan(db, friday: DayType.piernas); // id de un viernes
      // Lo hecho (dominadas) no está en ese día: es de otra base.
      final legacy = GuidedSnapshot(
        date: '2026-10-13',
        startedAt: clock.now().subtract(const Duration(minutes: 20)),
        planDayId: foreign,
        phase: GuidedPhase.trabajo,
        index: 3,
        done: const [DoneStep('Dominadas australianas', 8, false)],
      );
      await t.runAsync(() => store.save(legacy));
      await resume(legacy);

      expect(find.text('Sesión sin su guion'), findsOneWidget);
      expect(find.text('Sentadilla'), findsNothing);
      expect(await t.runAsync(store.load), isNotNull);
    });
  });

  testWidgets('guion congelado inválido: el archivo se conserva y se pide decisión', (t) async {
    await run(t, (settle, db, store, resume) async {
      final broken = snapshot(planDayId: -1, day: {'type': 'no-existe'});
      await t.runAsync(() => store.save(broken));
      await resume(broken);

      expect(find.text('Sesión sin su guion'), findsOneWidget);
      expect(await t.runAsync(store.load), isNotNull);
    });
  });
}
