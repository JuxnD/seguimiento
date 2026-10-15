import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/home/roll_day_row.dart';

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 053: el botón «Rodar 1 día» de Hoy sobre SQLite real, con el lunes
/// 12 oct del v3.1 (la semana del reporte del owner).
void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12);

  /// Avanza la zona de la prueba y la real por turnos (drift 2.21 espera
  /// Timer.run de la zona falsa), como coherence_today_test.
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
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  testWidgets('rodar desde Hoy avisa lo que se pierde, guarda y se deshace',
      (tester) => withClock(Clock.fixed(DateTime(2026, 10, 12, 8)), () async {
            final db = await drive(tester, () async {
              final db = openInMemoryDatabase();
              await asExistingUser(db, since: mon);
              final plan = PlanRepository(db, ExerciseRepository(db));
              await seedIfEmpty(db, plan);
              await activatePlanV31(db, plan, mon);
              return db;
            });
            final plan = PlanRepository(db, ExerciseRepository(db));
            await tester.pumpWidget(ProviderScope(
              overrides: [databaseProvider.overrideWithValue(db)],
              child: MaterialApp(
                  home: Scaffold(body: RollDayRow(date: mon, trained: false))),
            ));
            await settle(tester);

            await tester.tap(find.text('Rodar 1 día'));
            await settle(tester);
            expect(find.text('¿Rodar la programación un día?'), findsOneWidget);
            expect(find.textContaining('se pierde la sesión del vie 16'),
                findsOneWidget,
                reason: 'el v3.1 no tiene descanso entre semana');
            expect(find.textContaining('Puedes deshacerlo desde Hoy'),
                findsOneWidget);
            await tester.tap(find.widgetWithText(FilledButton, 'Rodar 1 día'));
            await settle(tester);

            expect((await drive(tester, () => plan.dayFor(mon)))!.vacated,
                isTrue);
            expect(find.textContaining('hoy queda libre'), findsOneWidget);
            await tester.tap(find.text('Deshacer: volver a lo de hoy'));
            await settle(tester);
            expect((await drive(tester, () => plan.dayFor(mon)))!.vacated,
                isFalse);
            expect(find.text('Rodar 1 día'), findsOneWidget);

            // Con la sesión de hoy hecha ya no se ofrece rodar.
            await tester.pumpWidget(ProviderScope(
              overrides: [databaseProvider.overrideWithValue(db)],
              child: MaterialApp(
                  home: Scaffold(body: RollDayRow(date: mon, trained: true))),
            ));
            await settle(tester);
            expect(find.text('Rodar 1 día'), findsNothing);
            await drive(tester, db.close);
          }));

  testWidgets(
      'caso del owner: el jueves registra que la semana ya iba corrida desde el lunes',
      (tester) => withClock(Clock.fixed(DateTime(2026, 10, 15, 8)), () async {
            final thu = DateTime(2026, 10, 15);
            final db = await drive(tester, () async {
              final db = openInMemoryDatabase();
              await asExistingUser(db, since: mon);
              final plan = PlanRepository(db, ExerciseRepository(db));
              await seedIfEmpty(db, plan);
              await activatePlanV31(db, plan, mon);
              return db;
            });
            final plan = PlanRepository(db, ExerciseRepository(db));
            expect((await drive(tester, () => plan.dayFor(thu)))!.day.type,
                DayType.trenSuperior);
            await tester.pumpWidget(ProviderScope(
              overrides: [databaseProvider.overrideWithValue(db)],
              child: MaterialApp(
                  home: Scaffold(body: RollDayRow(date: thu, trained: false))),
            ));
            await settle(tester);
            await tester.tap(find.text('Rodar 1 día'));
            await settle(tester);
            expect(find.text('¿Desde qué día?'), findsOneWidget);
            for (final chip in ['lun 12 oct', 'mar 13 oct', 'mié 14 oct', 'Hoy']) {
              expect(find.widgetWithText(ChoiceChip, chip), findsOneWidget,
                  reason: chip);
            }
            await tester.tap(find.widgetWithText(ChoiceChip, 'lun 12 oct'));
            await settle(tester);
            expect(find.textContaining('El lun 12 oct cuenta como libre'),
                findsOneWidget);
            await tester.tap(find.widgetWithText(FilledButton, 'Rodar 1 día'));
            await settle(tester);

            final today = (await drive(tester, () => plan.dayFor(thu)))!;
            expect((today.day.type, today.nominalDate),
                (DayType.piernas, DateTime(2026, 10, 14)),
                reason: 'el jueves vuelve a ser piernas con su test');
            expect(find.text('Programación rodada 1 día: desde el lun 12 oct.'),
                findsOneWidget);
            await tester.tap(find.text('Deshacer el del lun 12 oct'));
            await settle(tester);
            expect((await drive(tester, () => plan.dayFor(thu)))!.day.type,
                DayType.trenSuperior);
            await drive(tester, db.close);
          }));
}
