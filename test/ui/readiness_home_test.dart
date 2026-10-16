import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/features/home/readiness_card.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/sqlite_host.dart';

/// Hoy con la recuperación activa (§19.17). Fechas ficticias: el lunes 4 de
/// marzo de 2030 viene de sábado y domingo con tres partidos.
///
/// La base se crea y se usa en la misma zona que la pantalla (`drive`). La
/// lectura de la recuperación se calcula sobre SQLite real con las mismas
/// consultas que `readinessViewProvider` y se inyecta; después de cada toque
/// que escribe se desmonta Hoy, se relee la base y se vuelve a montar. Esto
/// prueba toques, decisiones y lo guardado, no la actualización reactiva de la
/// misma pantalla: esa la cubre `readiness_partial_test` con los providers
/// reales.
class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2030, 3, 4);
}

void main() {
  setUpAll(useHostSqlite);

  final sat = DateTime(2030, 3, 2);
  final sun = DateTime(2030, 3, 3);
  final mon = DateTime(2030, 3, 4);

  late Directory dir;
  setUp(
      () => dir = Directory.systemTemp.createTempSync('seguimiento_032_home'));

  /// Una operación con la base, iniciada en la zona de la pantalla y
  /// avanzada hasta que termina. Con un tope: si no termina, la prueba falla
  /// en vez de colgarse (antes, `await runAsync(op)` tras desmontar dejaba
  /// inmóviles los timers de drift en la zona falsa).
  Future<T> drive<T>(WidgetTester tester, Future<T> Function() op) async {
    T? value;
    Object? error;
    var done = false;
    unawaited(op().then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    }));
    // Como el cierre de 033 (coherence_today_test): drift 2.21 espera
    // Timer.run de la zona falsa, así que se avanzan las dos zonas por turnos.
    for (var i = 0; i < 200 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    if (!done) fail('operación con la base sin terminar tras 200 turnos');
    if (error != null) throw error!;
    return value as T;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<AppDatabase> open(WidgetTester tester, {bool weekend = true}) =>
      drive(tester, () async {
        final db = openInMemoryDatabase();
        if (weekend) {
          for (final (d, min, effort) in [
            (sat, 60, 5),
            (sun, 90, 7),
            (sun, 60, 8)
          ]) {
            await db.into(db.footballGames).insert(
                FootballGamesCompanion.insert(
                    date: dayKey(d), minutes: min, intensity: Value(effort)));
          }
        }
        return db;
      });

  /// Lo mismo que `readinessViewProvider`, leído fuera de la pantalla.
  Future<ReadinessView> view(WidgetTester tester, AppDatabase db,
          {bool test = false}) =>
      drive(tester, () async {
        final repo = ReadinessRepository(db);
        return ReadinessView(
          advice: await repo.readinessOn(mon, testOrAttemptToday: test),
          trainedAnyway: await repo.trainedAnyway(mon),
          recoveryDone: await repo.recoveryDone(mon),
          routines: await repo.routinesOn(mon),
          mobilityStreak: await repo.mobilityStreak(mon),
        );
      });

  TodayDashboard dashboard({({int round, TestPart part, bool done})? test}) =>
      TodayDashboard(
        date: mon,
        weekIndex: 1,
        dayType: DayType.trenSuperior,
        planVersion: 3,
        planSummary: null,
        mainExercises: const ['Dominadas 3×8'],
        blockExercises: const [],
        targetRounds: null,
        roundsDone: null,
        sessionsToday: 0,
        streak: 3,
        macros: const Macros(),
        proteinMin: 130,
        proteinMax: 160,
        kcalTarget: 2400,
        roundsRecord: null,
        measurement: null,
        fitnessTest: test,
        fitnessTestStart: test == null ? null : mon,
      );

  Future<void> mount(WidgetTester tester, AppDatabase db, ReadinessView v,
      {({int round, TestPart part, bool done})? test}) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localFlagsProvider
            .overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
        todayProvider.overrideWith(_FixedToday.new),
        dashboardProvider.overrideWith((ref) => dashboard(test: test)),
        readinessViewProvider.overrideWith((ref, _) => v),
        activeSessionProvider.overrideWith((ref) => null),
        updateCheckProvider
            .overrideWith((ref) => const UpdateCheck(currentVersion: '1.23.0')),
        morningDoneProvider.overrideWith((ref, _) => false),
      ],
      child: MaterialApp(theme: buildGymTheme(), home: const HomeScreen()),
    ));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  Future<void> close(WidgetTester tester, AppDatabase db) async {
    await unmount(tester);
    await drive(tester, db.close);
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  testWidgets(
      'amarillo: la recuperación reemplaza la sesión; cancelar no decide, confirmar sí',
      (tester) async {
    final db = await open(tester);
    await mount(tester, db, await view(tester, db));
    expect(find.text('Hoy: recuperación activa'), findsOneWidget);
    expect(
        find.text(
            '• Carga de anteayer y ayer: 1.410 (sáb 300 · dom 630 · dom 480)'),
        findsOneWidget);
    expect(find.text('Empezar recuperación (30 min)'), findsOneWidget);
    expect(find.text('Empezar tren superior'), findsNothing);
    expect(find.text('Mover test a mañana'), findsNothing,
        reason: 'hoy no hay test');

    await tester.tap(find.text('Entrenar igual'));
    await settle(tester);
    expect(find.text('¿Entrenar igual?'), findsOneWidget);
    await tester.tap(inDialog('Mejor recupero'));
    await settle(tester);
    expect(find.text('Hoy: recuperación activa'), findsOneWidget);
    await unmount(tester);
    expect(
        await drive(tester, () => db.select(db.coachProposals).get()), isEmpty,
        reason: 'cancelar no guarda nada');

    await mount(tester, db, await view(tester, db));
    await tester.tap(find.text('Entrenar igual'));
    await settle(tester);
    await tester.tap(inDialog('Entrenar igual'));
    await settle(tester);
    await unmount(tester);
    final row =
        await drive(tester, () => db.select(db.coachProposals).getSingle());
    expect((row.kind, row.status, row.createdOn),
        (readinessProposalKind, 'rechazada', '2030-03-04'));

    // Con la decisión guardada, Hoy vuelve a la sesión del día.
    await mount(tester, db, await view(tester, db));
    expect(find.text('Hoy: recuperación activa'), findsNothing);
    expect(find.text('Empezar tren superior'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester, db);
  });

  testWidgets('rojo: solo descanso, sin la activación del amarillo',
      (tester) async {
    final db = await open(tester, weekend: false);
    await drive(
        tester, () => RecoveryRepository(db).setSoreness(mon, {'Rodilla': 6}));
    await mount(tester, db, await view(tester, db));
    expect(find.text('Hoy: solo descanso'), findsOneWidget);
    expect(find.text('• Dolor anotado en Rodilla 6/10'), findsOneWidget);
    expect(find.textContaining('Rodilla en escaleras'), findsNothing,
        reason: 'Generic soreness never invents an unrecorded stairs value');
    expect(find.text('Movilidad suave (Suelta)'), findsOneWidget);
    expect(find.text('Empezar recuperación (30 min)'), findsNothing);
    expect(find.text('Entrenar igual'), findsOneWidget,
        reason: 'la decisión sigue siendo de la persona');
    await close(tester, db);
  });

  testWidgets(
      'día de test amarillo: "Mover test a mañana" lo mueve y queda trazado',
      (tester) async {
    final db = await open(tester);
    const test = (round: 1, part: TestPart.torso, done: false);
    await mount(tester, db, await view(tester, db, test: true), test: test);
    expect(find.text('Hoy: recuperación activa'), findsOneWidget);
    await tester.tap(find.text('Mover test a mañana'));
    await settle(tester);
    expect(find.text('Test movido al martes 5 mar'), findsOneWidget);
    await unmount(tester);
    final moves = await drive(
        tester, () => ReadinessRepository(db).moves(mon, 1, TestPart.torso));
    expect([for (final m in moves) (dayKey(m.from), dayKey(m.to))],
        [('2030-03-04', '2030-03-05')]);
    await close(tester, db);
  });

  testWidgets('a medias no es hecho: sin ✓ ni "Día completo"; terminada sí',
      (tester) async {
    final db = await open(tester);
    final training = TrainingRepository(db, ExerciseRepository(db));
    Future<void> save(String mode, {required bool complete}) => drive(
        tester,
        () => training.save(SessionDraft(
            date: mon,
            type: SessionType.movilidad,
            mode: mode,
            totalSec: complete ? 1800 : 30,
            incomplete: !complete)));
    await save(recoveryActiveId, complete: false);
    await save(morningActivaId, complete: false);
    await mount(tester, db, await view(tester, db));
    expect(find.text('Hoy: recuperación activa'), findsOneWidget,
        reason: 'la parcial no acepta la recuperación');
    expect(find.text('Día completo'), findsNothing);
    expect(find.text('Mañana'), findsOneWidget);
    expect(find.text('Mañana ✓'), findsNothing);
    await unmount(tester);

    await save(morningActivaId, complete: true);
    await save(recoveryActiveId, complete: true);
    await mount(tester, db, await view(tester, db));
    expect(find.text('Mañana ✓'), findsOneWidget);
    expect(find.text('Día completo'), findsOneWidget);
    expect(find.text('Hoy: recuperación activa'), findsNothing);
    await close(tester, db);
  });
}
