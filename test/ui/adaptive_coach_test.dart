import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/coach_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/domain/adaptive_coach.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/features/home/coach_card.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

/// Plan 009 en pantalla: la propuesta se acepta con la cifra que la persona
/// elija, o se pospone; nada se aplica solo. La lectura sale de SQLite y la
/// decisión usa el día real del reloj (R2: cruce de medianoche).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);

  DateTime d(int month, int day) => DateTime(2026, month, day);
  final monday = d(11, 2);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }
  }

  /// Meta conocida de 5.000 desde septiembre, diez días entre semana holgados
  /// y "bien" al despertar el domingo.
  Future<AppDatabase> seed() async {
    final db = openInMemoryDatabase();
    await db.delete(db.goalVersions).go();
    await db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
        metric: GoalMetric.pasos.name,
        value: const Value(5000),
        effectiveFrom: const Value('2026-09-01'),
        acceptedAt: '2026-09-01',
        origin: GoalOrigin.inicio));
    final w = coachWindow(monday);
    for (var i = 0; i < w.length; i++) {
      // Constante: la ventana del martes da la misma propuesta que la del lunes.
      await StepsRepository(db).setSteps(w[i], 6400);
    }
    await RecoveryRepository(db).setFeeling(addDays(monday, -1), 2);
    return db;
  }

  /// La tarjeta con la lectura del lunes y el reloj en `clock`.
  Future<(AppDatabase, CoachReading)> pump(WidgetTester tester, {required DateTime clock}) async {
    await loadTestFonts(tester);
    final db = (await tester.runAsync(seed))!;
    final reading = (await tester.runAsync(() => CoachRepository(db).stepsReading(monday)))!;
    expect(reading.state, CoachState.propuesta);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        decisionClockProvider.overrideWithValue(() => clock),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CoachCard(reading: reading)))),
    ));
    await settle(tester);
    return (db, reading);
  }

  Future<void> close(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  }

  testWidgets('aceptar con otra cifra: rige desde mañana con lo elegido', (tester) async {
    final (db, reading) = await pump(tester, clock: DateTime(2026, 11, 2, 20));
    final p = reading.proposal!;
    expect(p.id, 'pasos:5000>6000:2026-09-01:p1');
    expect(find.text('Acompañamiento · Propuesta'), findsOneWidget);
    await tester.tap(find.text('Subir a 6.000…'));
    await settle(tester);
    expect(find.text('Nueva meta de pasos'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '5800');
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    expect(find.text('Meta de 5.800 pasos desde mañana (3 nov). Se revisa en $coachReviewDays días.'), findsOneWidget);

    final h = (await tester.runAsync(() => GoalRepository(db).history()))!;
    expect(h.on(GoalMetric.pasos, d(11, 2))!.value, 5000, reason: 'hoy no cambia');
    expect(h.on(GoalMetric.pasos, d(11, 3))!.value, 5800);
    final rec = (await tester.runAsync(() => GoalRepository(db).proposal(p.id)))!;
    expect((rec.status, rec.decidedOn), (ProposalStatus.aceptada, d(11, 2)));
    await close(tester, db);
  });

  testWidgets('diálogo abierto el lunes, aceptado el martes 00:05: rige el miércoles, como dice el texto',
      (tester) async {
    final (db, reading) = await pump(tester, clock: DateTime(2026, 11, 3, 0, 5));
    final p = reading.proposal!;
    await tester.tap(find.text('Subir a 6.000…'));
    await settle(tester);
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    expect(find.text('Meta de 6.000 pasos desde mañana (4 nov). Se revisa en $coachReviewDays días.'), findsOneWidget);
    final h = (await tester.runAsync(() => GoalRepository(db).history()))!;
    expect(h.on(GoalMetric.pasos, d(11, 3))!.value, 5000, reason: 'el martes, día real de la aceptación, no cambia');
    expect(h.on(GoalMetric.pasos, d(11, 4))!.value, 6000);
    expect(h.current(GoalMetric.pasos, d(11, 4))!.effectiveFrom, d(11, 4));
    final rec = (await tester.runAsync(() => GoalRepository(db).proposal(p.id)))!;
    expect(rec.decidedOn, d(11, 3), reason: 'la decisión persistida lleva el día real');
    await close(tester, db);
  });

  testWidgets('cruza medianoche y la lectura del día nuevo ya no la ofrece: no se guarda nada', (tester) async {
    final (db, reading) = await pump(tester, clock: DateTime(2026, 11, 3, 0, 5));
    // El martes amaneció cansado: la lectura del martes pone la recuperación primero.
    await tester.runAsync(() => RecoveryRepository(db).setFeeling(d(11, 3), 3));
    await tester.tap(find.text('Subir a 6.000…'));
    await settle(tester);
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    expect(find.textContaining('La revisión cambió desde que la abriste'), findsOneWidget);
    expect(await tester.runAsync(() => GoalRepository(db).proposal(reading.proposal!.id)), isNull);
    final h = (await tester.runAsync(() => GoalRepository(db).history()))!;
    expect(h.of(GoalMetric.pasos).map((v) => v.value), [5000], reason: 'sin vigencia nueva');
    await close(tester, db);
  });

  testWidgets('una cifra fuera de rango no se acepta', (tester) async {
    final (db, reading) = await pump(tester, clock: DateTime(2026, 11, 2, 20));
    await tester.tap(find.text('Subir a 6.000…'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '90');
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    expect(find.text('Entre 1.000 y 30.000 pasos'), findsOneWidget);
    expect(await tester.runAsync(() => GoalRepository(db).proposal(reading.proposal!.id)), isNull);
    await close(tester, db);
  });

  testWidgets('posponer guarda la revisión en 7 días y no toca la meta', (tester) async {
    final (db, reading) = await pump(tester, clock: DateTime(2026, 11, 2, 20));
    await tester.tap(find.text('En 7 días'));
    await settle(tester);
    final rec = (await tester.runAsync(() => GoalRepository(db).proposal(reading.proposal!.id)))!;
    expect((rec.status, rec.reviewAfter), (ProposalStatus.pospuesta, d(11, 9)));
    final profile = (await tester.runAsync(() => db.select(db.profiles).getSingle()))!;
    expect(profile.stepsTarget, 5000);
    await close(tester, db);
  });
}
