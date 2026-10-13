import 'dart:async';
import 'package:drift/drift.dart' show Value;
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
      'Home stairs alert reads three SQLite days and clears for null or zero',
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
      await db.customStatement(
          "INSERT INTO morning_checks(date,knee_stairs) VALUES('2030-03-03',3),('2030-03-04',4),('2030-03-05',3)");
      container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)]);
    });
    try {
      debugPrint('H1_PHASE:pumpWidget');
      await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home: Scaffold(
                  body: KneeStairsAlert(date: DateTime(2030, 3, 5))))));
      Future<void> settle() async {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      await settle();
      debugPrint('H1_PHASE:positive');
      expect(find.text('Rodilla: tres días seguidos'), findsOneWidget);
      expect(find.textContaining('Aplaza sesión de piernas o test.'),
          findsOneWidget);
      for (final value in ['NULL', '0']) {
        await barrier('update-$value', () async {
          await (db.update(db.morningChecks)
                ..where((row) => row.date.equals('2030-03-04')))
              .write(MorningChecksCompanion(
                  kneeStairs: Value(value == 'NULL' ? null : 0)));
          expect(
              (await db
                      .customSelect(
                          "SELECT knee_stairs FROM morning_checks WHERE date='2030-03-04'")
                      .getSingle())
                  .data['knee_stairs'],
              value == 'NULL' ? null : 0);
        });
        await settle();
        expect(find.text('Rodilla: tres días seguidos'), findsNothing);
      }
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
