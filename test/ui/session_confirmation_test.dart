import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/coach_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/training/session_form_screen.dart';
import '../support/sqlite_host.dart';

class _Notifications extends NotificationService {
  _Notifications() : super(FlutterLocalNotificationsPlugin());
  @override
  Future<void> cancelReviewReminder() async {}
}
class _PendingPlan extends PlanRepository {
  _PendingPlan(super.db, super.exercises);
  final gate = Completer<void>();
  int calls = 0;
  @override
  Future<PlanDayView?> dayFor(DateTime date) async {
    calls++;
    await gate.future;
    return null;
  }
}
class _TrackedTraining extends TrainingRepository {
  _TrackedTraining(super.db, super.exercises);
  final writes = <Completer<void>>[];
  @override
  Future<int> save(SessionDraft d) {
    final done = Completer<void>();
    writes.add(done);
    final result = super.save(d);
    result.then((_) => done.complete(), onError: (Object error, StackTrace stack) => done.complete());
    return result;
  }
}
class _PendingSave extends _TrackedTraining {
  _PendingSave(super.db, super.exercises);
  Completer<void> gate = Completer<void>();
  bool fail = true;
  final results = <Future<int>>[];
  final finished = <bool>[];
  @override
  Future<int> save(SessionDraft d) {
    final result = _save(d);
    final index = finished.length;
    finished.add(false);
    result.then((_) => finished[index] = true, onError: (Object error, StackTrace stack) => finished[index] = true);
    results.add(result);
    return result;
  }
  Future<int> _save(SessionDraft d) async {
    await gate.future;
    if (fail) throw StateError('I/O sintético');
    return super.save(d);
  }
}
void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late _TrackedTraining repo;
  setUp(() {
    db = openInMemoryDatabase();
    repo = _TrackedTraining(db, ExerciseRepository(db));
  });
  Future<void> inWidgetZone(WidgetTester t, Future<void> Function() body) async {
    try {
      await body();
    } finally {
      await t.pumpWidget(const SizedBox());
      var closed = false;
      final closing = db.close().then((_) => closed = true);
      for (var i = 0; i < 20 && !closed; i++) {
        await t.pump(const Duration(milliseconds: 20));
        await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 10)); });
      }
      expect(closed, isTrue, reason: 'close debe avanzar los timers de Drift en zona widget');
      await closing;
    }
  }
  SessionDraft draft(DateTime date) => SessionDraft(date: date,
      type: SessionType.trenSuperior, rpe: 7,
      sets: [SetDraft(exercise: 'Flexiones', reps: 8), SetDraft(exercise: 'Flexiones', reps: 7)]);
  Future<void> mount(WidgetTester t, SessionDraft d, {PlanRepository? plan, bool celebrate = false}) async {
    await t.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWithValue(db),
      trainingRepositoryProvider.overrideWithValue(repo),
      planRepositoryProvider.overrideWithValue(plan ?? PlanRepository(db, ExerciseRepository(db))),
      notificationServiceProvider.overrideWithValue(_Notifications()),
    ], child: MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
        SessionFormScreen(draft: d, celebrate: celebrate))), child: const Text('Abrir')))))));
    await t.tap(find.text('Abrir'));
    await t.pumpAndSettle();
  }
  Future<void> awaitWrite(WidgetTester t, int before) async {
    for (var i = 0; i < 40 && (repo.writes.length <= before || !repo.writes.last.isCompleted); i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 10)); });
    }
    expect(repo.writes.length, greaterThan(before), reason: 'UI debe llegar al repositorio real');
    expect(repo.writes.last.isCompleted, isTrue, reason: 'no leer/disponer antes de terminar escritura');
    await t.pumpAndSettle();
  }
  Future<void> pumpUntil(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 40 && !ready(); i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 10)); });
    }
    expect(ready(), isTrue, reason: 'esperar frontera real; no asumir commit por milisegundos');
  }
  testWidgets('guard inicia antes de consultar plan: dos taps sólo una consulta y una fila', (t) => inWidgetZone(t, () async {
    final plan = _PendingPlan(db, ExerciseRepository(db));
    await mount(t, draft(DateTime(2026, 9, 11)), plan: plan);
    final button = t.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    button.onPressed!();
    button.onPressed!();
    await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 50)); });
    await pumpUntil(t, () => plan.calls > 0);
    try {
      expect(plan.calls, 1);
    } finally {
      plan.gate.complete();
      await awaitWrite(t, 0);
    }
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(1));
  }));
  testWidgets('duplicado completo pide confirmación; corregir no escribe y aceptar una fila', (t) => inWidgetZone(t, () async {
    await t.runAsync(() => repo.save(draft(DateTime(2026, 9, 4))));
    await mount(t, draft(DateTime(2026, 9, 11)));
    await t.runAsync(() async { await t.tap(find.byType(FloatingActionButton));
      await Future<void>.delayed(const Duration(milliseconds: 80)); });
    await pumpUntil(t, () => find.text('Mismos números que la última sesión').evaluate().isNotEmpty);
    await t.pumpAndSettle();
    expect(find.text('Mismos números que la última sesión'), findsOneWidget);
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(1));
    await t.tap(find.text('Corregir'));
    await t.pumpAndSettle();
    await pumpUntil(t, () => t.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed != null);
    expect(find.byType(SessionFormScreen), findsOneWidget);
    await t.runAsync(() async { await t.tap(find.byType(FloatingActionButton));
      await Future<void>.delayed(const Duration(milliseconds: 80)); });
    await pumpUntil(t, () => find.text('Mismos números que la última sesión').evaluate().isNotEmpty);
    await t.pumpAndSettle();
    // Atrás del sistema: el botón del appbar está debajo del diálogo.
    // tap(pageBack) tocaba la barrera y no acreditaba esta ruta de cancelación.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await pumpUntil(t, () => t.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed != null);
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(1));
    await t.tap(find.byType(FloatingActionButton));
    await pumpUntil(t, () => find.text('Mismos números que la última sesión').evaluate().isNotEmpty);
    await t.pumpAndSettle();
    await t.runAsync(() async { await t.tap(find.text('Guardar igual'));
      await Future<void>.delayed(const Duration(milliseconds: 80)); });
    await awaitWrite(t, 1);
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(2));
  }));
  testWidgets('primera progresión limpia de diez acredita hito tras guardar sin activar plan', (t) => inWidgetZone(t, () async {
    await t.runAsync(() => repo.save(SessionDraft(date: DateTime(2026, 9, 4),
        type: SessionType.progresion, roundsDone: 9, plannedRounds: 9,
        techniqueOk: true, fullRange: true, recoveryOk: true, rpe: 7)));
    final ten = SessionDraft(date: DateTime(2026, 9, 11), type: SessionType.progresion,
      roundsDone: 10, plannedRounds: 10, rpe: 8,
      techniqueOk: true, fullRange: true, recoveryOk: true);
    await t.runAsync(() async {
      final plan = PlanDraft.empty(DateTime(2026, 9, 1));
      plan.days[4].type = DayType.progresion;
      await PlanRepository(db, ExerciseRepository(db)).saveAsNewVersion(plan);
    });
    await mount(t, ten, celebrate: true);
    await t.runAsync(() async { await t.tap(find.byType(FloatingActionButton));
      await Future<void>.delayed(const Duration(milliseconds: 120)); });
    await awaitWrite(t, 1);
    await t.pumpAndSettle();
    expect(find.text('Meta del Plan v2 cumplida'), findsOneWidget);
    expect(await t.runAsync(() => repo.bestRounds()), 10);
    expect(await t.runAsync(() => db.select(db.planVersions).get()), hasLength(1), reason: 'sin activar otra versión');
    expect(find.textContaining('Activar'), findsNothing);
    await t.tap(find.text('Seguir así'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await mount(t, ten);
    await t.tap(find.byType(FloatingActionButton));
    await awaitWrite(t, 2);
    expect(find.text('Meta del Plan v2 cumplida'), findsNothing);
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(2));
  }));
  testWidgets('una sola serie distinta no confirma y editar propio id no duplica', (t) => inWidgetZone(t, () async {
    final old = draft(DateTime(2026, 9, 4));
    await t.runAsync(() => repo.save(old));
    final changed = draft(DateTime(2026, 9, 11));
    changed.sets.last.reps = 6;
    await mount(t, changed);
    await t.runAsync(() async { await t.tap(find.byType(FloatingActionButton));
      await Future<void>.delayed(const Duration(milliseconds: 80)); });
    await awaitWrite(t, 1);
    expect(find.text('Mismos números que la última sesión'), findsNothing);
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(2));
    await t.pumpWidget(const SizedBox());
    await mount(t, changed);
    await t.runAsync(() async { await t.tap(find.byType(FloatingActionButton));
      await Future<void>.delayed(const Duration(milliseconds: 80)); });
    await awaitWrite(t, 2);
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(2));
  }));
  testWidgets('busy quita foco; fallo conserva formulario y retry guarda exactamente una fila', (t) => inWidgetZone(t, () async {
    final pending = _PendingSave(db, ExerciseRepository(db));
    repo = pending;
    await mount(t, SessionDraft(date: DateTime(2026, 9, 11), type: SessionType.trenSuperior, rpe: 7));
    await t.tap(find.byType(TextField).first);
    await t.pump();
    expect(t.testTextInput.hasAnyClients, isTrue);
    await t.runAsync(() async {
      await t.tap(find.byType(FloatingActionButton));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await t.pump();
    await pumpUntil(t, () => pending.results.isNotEmpty);
    try {
      expect(t.testTextInput.hasAnyClients, isFalse);
      expect(t.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);
    } finally {
      pending.gate.complete();
      await pumpUntil(t, () => pending.finished.every((done) => done));
      await t.runAsync(() async {
        for (final future in pending.results) {
          try { await future; } on StateError { /* UI informa el error. */ }
        }
      });
    }
    await t.pump();
    expect(find.byType(SessionFormScreen), findsOneWidget);
    expect(find.textContaining('No se pudo guardar'), findsOneWidget);
    expect(await t.runAsync(() => db.select(db.sessions).get()), isEmpty);
    pending.fail = false;
    pending.gate = Completer<void>();
    final beforeRetry = pending.results.length;
    await t.tap(find.byType(FloatingActionButton));
    await pumpUntil(t, () => pending.results.length > beforeRetry);
    pending.gate.complete();
    await pumpUntil(t, () => pending.finished.last);
    await awaitWrite(t, 0);
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(1));
  }));
  testWidgets('review desvinculada conserva procedencia tras DB error y retry no acredita hito', (t) => inWidgetZone(t, () async {
    final reviewed = SessionDraft(date: DateTime(2026, 9, 11), type: SessionType.progresion,
      pendingReview: true, roundsDone: 10, plannedRounds: 10, rpe: 7);
    await t.runAsync(() async {
      final plan = PlanDraft.empty(DateTime(2026, 9, 1));
      plan.days[4].type = DayType.progresion;
      await PlanRepository(db, ExerciseRepository(db)).saveAsNewVersion(plan);
      await repo.save(reviewed);
    });
    reviewed.techniqueOk = reviewed.fullRange = reviewed.recoveryOk = true;
    final pending = _PendingSave(db, ExerciseRepository(db));
    repo = pending;
    await mount(t, reviewed);
    await t.tap(find.byType(FloatingActionButton));
    await pumpUntil(t, () => pending.results.isNotEmpty);
    pending.gate.complete();
    await pumpUntil(t, () => pending.finished.last);
    await pumpUntil(t, () => t.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed != null);
    expect(reviewed.pendingReview, isTrue, reason: 'fallar DB no convierte una revisión guiada en alta manual');
    final old = await t.runAsync(() => db.select(db.sessions).getSingle());
    expect(old!.pendingReview, isTrue);
    expect(old.techniqueOk, isNull);
    expect(find.text('Meta del Plan v2 cumplida'), findsNothing);
    pending.fail = false;
    pending.gate = Completer<void>();
    await t.tap(find.byType(FloatingActionButton));
    await pumpUntil(t, () => pending.results.length == 2);
    pending.gate.complete();
    await awaitWrite(t, 0);
    expect(await t.runAsync(() => db.select(db.sessions).get()), hasLength(1));
    expect((await t.runAsync(() => db.select(db.sessions).getSingle()))!.pendingReview, isFalse);
    expect(find.text('Meta del Plan v2 cumplida'), findsNothing, reason: 'plan actual no restablece vínculo perdido');
    expect(find.text('Abrir'), findsOneWidget);
  }));
  testWidgets('borrado existente elimina registro y carga/informe se recalculan', (t) => inWidgetZone(t, () async {
    final day = DateTime(2026, 9, 11);
    final recorded = draft(day)..totalSec = 1200;
    await t.runAsync(() => repo.save(recorded));
    expect((await t.runAsync(() => CoachRepository(db).load(day)))!.todayLoad, 140);
    await mount(t, recorded);
    await t.tap(find.byTooltip('Borrar'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Borrar'));
    await pumpUntil(t, () => find.text('Abrir').hitTestable().evaluate().isNotEmpty);
    expect(await t.runAsync(() => db.select(db.sessions).get()), isEmpty);
    expect((await t.runAsync(() => CoachRepository(db).load(day)))!.todayLoad, 0);
    final input = await t.runAsync(() => ReportRepository(db, NutritionRepository(db))
      .load(day, day, today: day, withPrevious: false));
    expect(input!.sessions, isEmpty);
  }));
}
