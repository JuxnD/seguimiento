import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/features/training/test_mode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/features/home/home_screen.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  testWidgets(
      'Home collision keeps both identities and opens each actual typed test route',
      (t) async {
    Future<void> barrier(String phase, Future<void> Function() action) async {
      debugPrint('H1_PHASE_START:$phase');
      var done = false;
      Object? error;
      StackTrace? stack;
      await t.runAsync(() async {
        unawaited(action().then<void>((_) {
          done = true;
        }, onError: (Object e, StackTrace st) {
          error = e;
          stack = st;
          done = true;
        }));
      });
      final deadline = Stopwatch()..start();
      while (!done && deadline.elapsed < const Duration(seconds: 2)) {
        await t.pump(const Duration(milliseconds: 10));
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      expect(done, isTrue, reason: 'Observable native/fake barrier: $phase');
      if (error != null) Error.throwWithStackTrace(error!, stack!);
      debugPrint('H1_PHASE_END:$phase');
    }

    late AppDatabase db;
    late ProviderContainer container;
    await barrier('setup', () async {
      db = openInMemoryDatabase();
      final monday = DateTime(2030, 3, 4);
      await activatePlanV32(
          db, PlanRepository(db, ExerciseRepository(db)), monday);
      await db.customStatement(
          "INSERT INTO morning_checks(date,knee_stairs) VALUES('2030-03-06',0)");
      final repo = ReadinessRepository(db);
      final key = TestScheduleKey(
          scheme: 'v3.2',
          blockStart: monday,
          protocolId: TestProtocolId.v32_13,
          round: 1,
          part: TestPart.torso);
      var from = monday;
      for (var i = 0; i < 2; i++) {
        from = (await repo.moveTest(
            start: monday,
            round: 1,
            part: TestPart.torso,
            from: from,
            reasons: ['synthetic'],
            key: key,
            now: from))!;
      }
      container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)]);
    });
    try {
      debugPrint('H1_PHASE:pumpWidget');
      await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home: Scaffold(
                  body: CollidingTestAgenda(date: DateTime(2030, 3, 6))))));
      Future<void> settle() async {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      await settle();
      debugPrint('H1_PHASE:positive');
      expect(find.text('Tests que coinciden hoy'), findsOneWidget);
      for (final part in TestPart.values) {
        final name = part == TestPart.torso ? 'torso' : 'piernas';
        final button =
            find.widgetWithText(OutlinedButton, 'Abrir test 1 de $name');
        expect(button, findsOneWidget);
        expect(t.widget<OutlinedButton>(button).onPressed, isNotNull);
        await t.tap(button);
        await t.pump(const Duration(milliseconds: 400));
        await settle();
        final screen = t.widget<TestModeScreen>(find.byType(TestModeScreen));
        expect((screen.round, screen.part, screen.date),
            (1, part, DateTime(2030, 3, 6)));
        expect((
          screen.scheduleKey!.scheme,
          screen.scheduleKey!.blockStart,
          screen.scheduleKey!.protocolId,
          screen.scheduleKey!.part
        ), (
          'v3.2',
          DateTime(2030, 3, 4),
          TestProtocolId.v32_13,
          part
        ));
        Navigator.of(t.element(find.byType(TestModeScreen))).pop();
        await t.pump(const Duration(milliseconds: 400));
        await settle();
      }
      await barrier('unknown-stairs', () async {
        await (db.update(db.morningChecks)
              ..where((r) => r.date.equals('2030-03-06')))
            .write(const MorningChecksCompanion(kneeStairs: Value(null)));
        expect((await db.select(db.coachProposals).get()).length, 2,
            reason: 'Opening both routes never moves or deletes a test');
      });
      await settle();
      expect(find.text('Tests que coinciden hoy'), findsOneWidget);
      expect(
          t
              .widget<OutlinedButton>(find.widgetWithText(
                  OutlinedButton, 'Abrir test 1 de piernas'))
              .onPressed,
          isNull);
      expect(
          t
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Abrir test 1 de torso'))
              .onPressed,
          isNotNull);
    } finally {
      debugPrint('H1_PHASE:cleanup');
      await t.pumpWidget(const SizedBox());
      await barrier('cleanup', () async {
        container.dispose();
        await db.close();
      });
      await t.pump();
    }
  });
}
