import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/domain/adaptive_coach.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/features/home/coach_card.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

/// Plan 009 en pantalla: la propuesta se acepta con la cifra que la persona
/// elija, o se pospone; nada se aplica solo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);

  DateTime d(int month, int day) => DateTime(2026, month, day);
  const p = StepsProposal(from: 5000, to: 6000, average: 6490, daysAtGoal: 10);
  final reading = CoachReading(
    evaluatedOn: d(11, 2),
    state: CoachState.propuesta,
    reason: 'Cumpliste la meta 10 de 10 días con un promedio de 6.490. Podrías subirla a 6.000; tú decides.',
    evidence: const ['10 de 10 días entre semana con pasos', 'promedio 6.490'],
    proposal: p,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }
  }

  Future<AppDatabase> pump(WidgetTester tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CoachCard(reading: reading)))),
    ));
    await settle(tester);
    return db;
  }

  testWidgets('aceptar con otra cifra: rige desde mañana con lo elegido', (tester) async {
    final db = await pump(tester);
    expect(find.text('Acompañamiento · Propuesta'), findsOneWidget);
    expect(find.textContaining('promedio 6.490'), findsWidgets);
    await tester.tap(find.text('Subir a 6.000…'));
    await settle(tester);
    expect(find.text('Nueva meta de pasos'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '5800');
    await tester.tap(find.text('Aceptar'));
    await settle(tester);

    final h = (await tester.runAsync(() => GoalRepository(db).history()))!;
    expect(h.on(GoalMetric.pasos, d(11, 2))!.value, 5000, reason: 'hoy no cambia');
    expect(h.on(GoalMetric.pasos, d(11, 3))!.value, 5800);
    final rec = (await tester.runAsync(() => GoalRepository(db).proposal(p.id)))!;
    expect(rec.status, ProposalStatus.aceptada);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  });

  testWidgets('una cifra fuera de rango no se acepta', (tester) async {
    final db = await pump(tester);
    await tester.tap(find.text('Subir a 6.000…'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '90');
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    expect(find.text('Entre 1.000 y 30.000 pasos'), findsOneWidget);
    expect(await tester.runAsync(() => GoalRepository(db).proposal(p.id)), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  });

  testWidgets('posponer guarda la revisión en 7 días y no toca la meta', (tester) async {
    final db = await pump(tester);
    await tester.tap(find.text('En 7 días'));
    await settle(tester);
    final rec = (await tester.runAsync(() => GoalRepository(db).proposal(p.id)))!;
    expect((rec.status, rec.reviewAfter), (ProposalStatus.pospuesta, d(11, 9)));
    final profile = (await tester.runAsync(() => db.select(db.profiles).getSingle()))!;
    expect(profile.stepsTarget, 5000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  });
}
