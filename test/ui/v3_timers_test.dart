import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/features/training/v3_timers.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

/// Cindy y Tabata se retoman si Android cierra la app a mitad.
void main() {
  setUp(() {
    wakelock.wakelockPlusPlatformInstance = _NoWakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
  }

  Future<SessionDraft> finishTimer(WidgetTester tester, Widget screen,
      {Future<void> Function()? beforeFinish}) async {
    SessionDraft? saved;
    await show(
        tester,
        Builder(
            builder: (context) => Scaffold(
                  body: FilledButton(
                    onPressed: () async {
                      saved = await Navigator.push<SessionDraft>(
                          context, MaterialPageRoute(builder: (_) => screen));
                    },
                    child: const Text('Abrir cronómetro'),
                  ),
                )));
    await tester.tap(find.text('Abrir cronómetro'));
    await tester.pumpAndSettle();
    await beforeFinish?.call();
    expect(find.text('ENFRIAMIENTO'), findsOneWidget);
    await tester.tap(find.text('Terminar y guardar'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull, reason: 'el draft real vuelve por Navigator');
    await tester.pumpWidget(const SizedBox.shrink());
    return saved!;
  }

  testWidgets('Cindy completa con fracciones no inventa un segundo de circuito',
      (tester) async {
    final start = DateTime(2026, 10, 16, 8, 0, 0, 100);
    final workStart = DateTime(2026, 10, 16, 8, 8, 0, 700);
    final workEnd = DateTime(2026, 10, 16, 8, 28, 0, 700);
    final ended = DateTime(2026, 10, 16, 8, 31, 0, 300);
    final original = TimerSnapshot(
      date: '2026-10-16',
      startedAt: start,
      mode: 'cindy',
      phase: 'enfriamiento',
      workStartedAt: workStart,
      workEndedAt: workEnd,
      roundMarks: const [70, 140],
      partial: 7,
    );
    final resume =
        ActiveSession.fromJson(jsonDecode(jsonEncode(original.toJson())))
            as TimerSnapshot;
    await withClock(Clock.fixed(ended), () async {
      final draft =
          await finishTimer(tester, AmrapScreen(date: start, resume: resume));
      expect(draft.spanSec, 1200,
          reason:
              'la ventana medida es 20:00; truncar fases separadas no añade trabajo');
      expect((draft.totalSec, draft.warmupSec, draft.cooldownSec),
          (1859, 480, 179));
      expect(
          (draft.incomplete, draft.roundsDone, draft.extraReps), (false, 2, 7));
      expect(draft.context, 'Cindy: 2 rondas + 7 reps en 20 min');
      expect(draft.roundMarksSec, [70, 140]);
      expect(draft.sets.map((s) => (s.exercise, s.reps)), [
        ('Dominadas', 5),
        ('Flexiones', 10),
        ('Sentadillas', 15),
        ('Dominadas', 5),
        ('Flexiones', 10),
        ('Sentadillas', 15),
        ('Dominadas', 5),
        ('Flexiones', 2),
      ]);
      expect(resume.toJson(), original.toJson(),
          reason: 'retomar no reescribe marcas ni dosis');
    });
  });

  testWidgets('Cindy completa con segundos enteros conserva sus tiempos',
      (tester) async {
    final start = DateTime(2026, 10, 16, 8);
    final workStart = start.add(const Duration(minutes: 8));
    final workEnd = workStart.add(const Duration(minutes: 20));
    final ended = workEnd.add(const Duration(minutes: 3));
    await withClock(Clock.fixed(ended), () async {
      final draft = await finishTimer(
          tester,
          AmrapScreen(
            date: start,
            resume: TimerSnapshot(
                date: '2026-10-16',
                startedAt: start,
                mode: 'cindy',
                phase: 'enfriamiento',
                workStartedAt: workStart,
                workEndedAt: workEnd,
                roundMarks: const [70],
                partial: 7),
          ));
      expect(
          (draft.totalSec, draft.warmupSec, draft.cooldownSec, draft.spanSec),
          (1860, 480, 180, 1200));
      expect(draft.incomplete, isFalse);
      expect(draft.context, 'Cindy: 1 ronda + 7 reps en 20 min');
    });
  });

  testWidgets(
      'Cindy cortada mide 2:00 reales con fracciones y conserva la foto',
      (tester) async {
    final start = DateTime(2026, 10, 16, 8, 0, 0, 100);
    final workStart = DateTime(2026, 10, 16, 8, 8, 0, 700);
    final workEnd =
        workStart.add(const Duration(seconds: 120, milliseconds: 250));
    final ended = workEnd.add(const Duration(seconds: 179, milliseconds: 600));
    var now = workEnd;
    final snapshots = <TimerSnapshot>[];
    await withClock(Clock(() => now), () async {
      final draft = await finishTimer(
          tester,
          AmrapScreen(
            date: start,
            resume: TimerSnapshot(
                date: '2026-10-16',
                startedAt: start,
                mode: 'cindy',
                phase: 'trabajo',
                workStartedAt: workStart,
                roundMarks: const [70]),
            onSnapshot: snapshots.add,
          ), beforeFinish: () async {
        await tester.tap(find.text('Terminar antes'));
        await tester.pumpAndSettle();
        // Plan 057 (auditoría 053, P1-8): «Terminar antes» pide confirmación.
        await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '7');
        await tester.pump(); // onChanged habilita Listo en el siguiente frame.
        await tester.tap(find.text('Listo'));
        await tester.pumpAndSettle();
        expect(snapshots.last.workEndedAt, workEnd);
        expect(snapshots.last.phase, 'enfriamiento');
        now = ended;
        await tester.pump();
      });
      expect(
          (draft.spanSec, draft.totalSec, draft.warmupSec, draft.cooldownSec),
          (120, 779, 480, 179));
      expect(
          (draft.incomplete, draft.roundsDone, draft.extraReps), (true, 1, 7));
      expect(draft.roundMarksSec, [70]);
      expect(draft.sets.map((s) => (s.exercise, s.reps)), [
        ('Dominadas', 5),
        ('Flexiones', 10),
        ('Sentadillas', 15),
        ('Dominadas', 5),
        ('Flexiones', 2),
      ]);
      expect(
          draft.context, 'Cindy cortada: 1 ronda + 7 reps en 2:00 de 20 min');
      final restored = ActiveSession.fromJson(
          jsonDecode(jsonEncode(snapshots.last.toJson()))) as TimerSnapshot;
      final resumed =
          await finishTimer(tester, AmrapScreen(date: start, resume: restored));
      expect((
        resumed.totalSec,
        resumed.warmupSec,
        resumed.cooldownSec,
        resumed.spanSec
      ), (
        draft.totalSec,
        draft.warmupSec,
        draft.cooldownSec,
        draft.spanSec
      ));
      expect((resumed.incomplete, resumed.roundsDone, resumed.extraReps),
          (true, 1, 7));
      expect(resumed.roundMarksSec, draft.roundMarksSec);
      expect(resumed.sets.map((s) => (s.exercise, s.reps)),
          draft.sets.map((s) => (s.exercise, s.reps)));
      expect((draft.rpe, draft.techniqueOk, draft.fullRange, draft.recoveryOk),
          (null, null, null, null));
      expect((draft.imported, draft.roundsEstimated), (false, false));
    });
  });

  testWidgets('Cindy sin inicio de trabajo no convierte el cap en tiempo hecho',
      (tester) async {
    final start = DateTime(2026, 10, 16, 8);
    await withClock(Clock.fixed(start.add(const Duration(minutes: 31))),
        () async {
      final draft = await finishTimer(
          tester,
          AmrapScreen(
            date: start,
            resume: TimerSnapshot(
                date: '2026-10-16',
                startedAt: start,
                mode: 'cindy',
                phase: 'enfriamiento'),
          ));
      expect((draft.spanSec, draft.incomplete), (0, true));
      expect(draft.context, startsWith('Cindy cortada: 0 rondas + 0 reps'));
      expect(draft.context, contains('en 0:00 de 20 min'));
    });
  });

  testWidgets('Cindy conserva ventana medida distinta del cap sin normalizarla',
      (tester) async {
    final start = DateTime(2026, 10, 16, 8, 0, 0, 100);
    final workStart = DateTime(2026, 10, 16, 8, 8, 0, 700);
    final workEnd = workStart.add(const Duration(seconds: 1300));
    await withClock(
        Clock.fixed(
            workEnd.add(const Duration(seconds: 179, milliseconds: 600))),
        () async {
      final draft = await finishTimer(
          tester,
          AmrapScreen(
            date: start,
            resume: TimerSnapshot(
                date: '2026-10-16',
                startedAt: start,
                mode: 'cindy',
                phase: 'enfriamiento',
                workStartedAt: workStart,
                workEndedAt: workEnd),
          ));
      expect(draft.spanSec, 1300,
          reason: 'no forzar la ventana a los 20 min prescritos');
    });
  });

  testWidgets('Tabata conserva su cálculo y dosis sin composición de Cindy',
      (tester) async {
    final start = DateTime(2026, 10, 16, 8, 0, 0, 100);
    final workStart = DateTime(2026, 10, 16, 8, 8, 0, 700);
    final workEnd = workStart.add(const Duration(seconds: 1100));
    const exercises = [
      'Flexiones',
      'Escaladores',
      'Sentadillas',
      'Hollow rocks'
    ];
    await withClock(
        Clock.fixed(
            workEnd.add(const Duration(seconds: 179, milliseconds: 600))),
        () async {
      final draft = await finishTimer(
          tester,
          TabataScreen(
            date: start,
            exercises: exercises,
            resume: TimerSnapshot(
                date: '2026-10-16',
                startedAt: start,
                mode: 'tabata',
                phase: 'enfriamiento',
                workStartedAt: workStart,
                workEndedAt: workEnd,
                worst: const {0: 12, 1: 10, 2: 9, 3: 8},
                exercises: exercises),
          ));
      expect(
          (draft.totalSec, draft.warmupSec, draft.cooldownSec, draft.restSec),
          (1760, 480, 179, 460));
      expect((draft.mode, draft.incomplete), ('tabata', false));
      expect(draft.sets.map((s) => (s.exercise, s.reps)), [
        ('Flexiones', 12),
        ('Escaladores', 10),
        ('Sentadillas', 9),
        ('Hollow rocks', 8),
      ]);
    });
  });

  test('la foto de Cindy o Tabata vuelve igual tras pasar por JSON', () {
    final t0 = DateTime(2026, 10, 16, 7);
    final snap = TimerSnapshot(
      date: '2026-10-16',
      startedAt: t0,
      mode: 'tabata',
      phase: 'trabajo',
      workStartedAt: t0.add(const Duration(minutes: 8)),
      worst: const {0: 11, 1: 9},
      exercises: const [
        'Flexiones',
        'Escaladores',
        'Sentadillas',
        'Hollow rocks'
      ],
    );
    final back = ActiveSession.fromJson(jsonDecode(jsonEncode(snap.toJson())))
        as TimerSnapshot;
    expect((back.mode, back.phase, back.startedAt, back.workStartedAt),
        ('tabata', 'trabajo', t0, snap.workStartedAt));
    expect(back.worst, {0: 11, 1: 9});
    expect(back.exercises, snap.exercises);
  });

  testWidgets('Cindy de prueba: calentamiento y checklist a la vista; la normal no los muestra', (tester) async {
    await show(tester, AmrapScreen(date: DateTime.now(), attempt: true));
    expect(find.text('Antes del intento'), findsOneWidget);
    expect(find.text('Reloj en modo entrenamiento'), findsOneWidget);
    expect(find.text('Empezar AMRAP'), findsOneWidget, reason: 'la tarjeta no bloquea empezar');
    await tester.pumpWidget(const SizedBox.shrink());
    await show(tester, AmrapScreen(date: DateTime.now()));
    expect(find.text('Antes del intento'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Cindy retomada sigue con sus rondas y su reloj', (tester) async {
    final now = DateTime.now();
    final snaps = <TimerSnapshot>[];
    await show(
      tester,
      AmrapScreen(
        date: now,
        resume: TimerSnapshot(
          date: '2026-10-16',
          startedAt: now.subtract(const Duration(minutes: 13)),
          mode: 'cindy',
          phase: 'trabajo',
          workStartedAt: now.subtract(const Duration(minutes: 5)),
          roundMarks: const [70, 140],
        ),
        onSnapshot: snaps.add,
      ),
    );
    expect(find.text('2 rondas'), findsOneWidget);
    expect(find.textContaining('15:0'), findsOneWidget,
        reason: 'quedan ~15 min de los 20');

    await tester.tap(find.text('+1 ronda'));
    await tester.pump();
    expect(snaps.last.roundMarks, hasLength(3),
        reason: 'cada ronda deja la foto al día');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Cindy que terminó con la app cerrada pide la ronda a medias',
      (tester) async {
    final now = DateTime.now();
    await show(
      tester,
      AmrapScreen(
        date: now,
        resume: TimerSnapshot(
          date: '2026-10-16',
          startedAt: now.subtract(const Duration(minutes: 30)),
          mode: 'cindy',
          phase: 'trabajo',
          workStartedAt: now.subtract(const Duration(minutes: 22)),
          roundMarks: const [70, 140, 210],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('¿cuántas reps de la ronda a medias?'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tabata retomado sigue en el bloque en que iba', (tester) async {
    final now = DateTime.now();
    await show(
      tester,
      TabataScreen(
        date: now,
        exercises: const [
          'Flexiones',
          'Escaladores',
          'Sentadillas',
          'Hollow rocks'
        ],
        resume: TimerSnapshot(
          date: '2026-10-16',
          startedAt: now.subtract(const Duration(minutes: 13)),
          mode: 'tabata',
          phase: 'trabajo',
          // Bloque 1 (230 s) + minuto entre bloques (60 s) + 5 s del bloque 2.
          workStartedAt: now.subtract(const Duration(seconds: 295)),
          worst: const {0: 12},
        ),
      ),
    );
    expect(find.textContaining('BLOQUE 2/4'), findsOneWidget);
    expect(find.textContaining('peor intervalo'), findsNothing,
        reason: 'el bloque 1 ya tenía su dato');
    await tester.pumpWidget(const SizedBox());
  });
}
