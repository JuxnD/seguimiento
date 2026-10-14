import 'dart:io';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/features/training/football_form_screen.dart';
import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

class _Today extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 9, 12);
}
void main() {
  setUpAll(useHostSqlite);
  for (final scale in [1.0, 2.0]) {
    testWidgets('Hoy suma dos partidos y abre detalle real, texto $scale', (t) =>
      withClock(Clock.fixed(DateTime(2026, 9, 12, 16)), () async {
        late AppDatabase db;
        final dir = Directory.systemTemp.createTempSync('coherence-today');
        late DashboardRepository dashboard;
        late TodayDashboard data;
        await t.runAsync(() async {
          db = openInMemoryDatabase();
          debugPrint('033 HARNESS: database created');
          final plan = PlanRepository(db, ExerciseRepository(db));
          await seedIfEmpty(db, plan);
          debugPrint('033 HARNESS: seed complete');
          dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
          for (final entry in [(60, 6, 5), (30, 9, 7)]) {
            await db.into(db.footballGames).insert(FootballGamesCompanion.insert(
              date: '2026-09-12', minutes: entry.$1, intensity: Value(entry.$2), format: Value(entry.$3)));
          }
          data = await dashboard.today(now: DateTime(2026, 9, 12));
          debugPrint('033 HARNESS: real dashboard loaded');
        });
        await loadTestFonts(t);
        debugPrint('033 HARNESS: fonts loaded');
        t.view.physicalSize = const Size(360, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(ProviderScope(overrides: [
          databaseProvider.overrideWithValue(db),
          localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
          todayProvider.overrideWith(_Today.new),
          dashboardProvider.overrideWith((ref) => data),
          activeSessionProvider.overrideWith((ref) => null),
          updateCheckProvider.overrideWith((ref) => const UpdateCheck(currentVersion: '1.23.0')),
          morningDoneProvider.overrideWith((ref, _) => false),
        ], child: MaterialApp(builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: const HomeScreen())));
        debugPrint('033 HARNESS: home mounted');
        await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
        // Home tiene lectores/timers externos: montaje acotado como experience_test.
        for (var i = 0; i < 12; i++) { await t.pump(const Duration(milliseconds: 50)); }
        debugPrint('033 HARNESS: home pumped');
        try {
          await t.scrollUntilVisible(find.text('Fútbol'), 160, scrollable: find.byType(Scrollable).first);
          debugPrint('033 HARNESS: football anchor visible');
          expect(t.takeException(), isNull, reason: 'Hoy con anillos montados no debe desbordar');
          expect(find.text("90'"), findsOneWidget);
          expect(find.text('2 sesiones'), findsOneWidget);
          await Scrollable.ensureVisible(t.element(find.text('Fútbol')), alignment: 0.5);
          await t.pump();
          expect(find.text('Fútbol').hitTestable(), findsOneWidget, reason: 'el ancla debe recibir el toque real bajo la cabecera');
          await t.tap(find.text('Fútbol').hitTestable());
          for (var i = 0; i < 12; i++) { await t.pump(const Duration(milliseconds: 50)); }
          expect(find.byType(BottomSheet), findsOneWidget, reason: 'el toque debe abrir el detalle');
          expect(find.textContaining('Carga total: 630'), findsOneWidget);
          expect(find.textContaining('RPE ponderado: 7'), findsOneWidget);
          expect(find.textContaining('Formatos mixtos'), findsOneWidget);
          expect(find.textContaining('60 min · RPE 6'), findsOneWidget);
          expect(find.textContaining('30 min · RPE 9'), findsOneWidget);
          expect(t.takeException(), isNull, reason: 'detalle de partidos no debe desbordar');
          await t.ensureVisible(find.textContaining('30 min · RPE 9'));
          await t.tap(find.textContaining('30 min · RPE 9'));
          for (var i = 0; i < 12; i++) { await t.pump(const Duration(milliseconds: 50)); }
          final editor = t.widget<FootballFormScreen>(find.byType(FootballFormScreen));
          expect(editor.existing!.id, data.gamesToday.last.id);
          expect(editor.existing!.minutes, 30);
          await t.pageBack();
          for (var i = 0; i < 12; i++) { await t.pump(const Duration(milliseconds: 50)); }
          expect(t.takeException(), isNull);
        } finally {
          debugPrint('033 HARNESS: disposing widget');
          await t.pumpWidget(const SizedBox());
          debugPrint('033 HARNESS: widget disposed; closing database');
          // Drift2.21 StreamQueryStore.close waits pending Timer.run futures.
          // Start closing in the widget zone and advance it before awaiting:
          // runAsync alone leaves its fake-zone timers unable to fire.
          var closed = false;
          final closing = db.close().then((_) => closed = true);
          for (var i = 0; i < 20 && !closed; i++) {
            await t.pump(const Duration(milliseconds: 20));
            await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 10)); });
          }
          expect(closed, isTrue, reason: 'harness debe cerrar SQLite sin esperar timers en zona inmóvil');
          await closing;
          debugPrint('033 HARNESS: database closed');
          dir.deleteSync(recursive: true);
        }
      }));
  }
}
