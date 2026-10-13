import 'dart:io';
import 'dart:convert';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/training/session_form_screen.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/domain/accessory_quality_proof.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/features/plan/plan_screen.dart';
import 'package:seguimiento/features/training/accessory_criteria_editor.dart';
import 'package:seguimiento/ui/widgets.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  Future<void> settle(WidgetTester t) async {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
      'direct v3.2 exposes real equipment switch; default unknown, true enables and false preserves level/history',
      (t) async {
    late AppDatabase db;
    late LocalFlags flags;
    final dir = Directory.systemTemp.createTempSync('plan034-equipment');
    await t.runAsync(() async {
      db = openInMemoryDatabase();
      flags = LocalFlags(File('${dir.path}/flags.json'));
      await activatePlanV32(
          db, PlanRepository(db, ExerciseRepository(db)), DateTime(2030, 2, 4));
      await LadderRepository(db)
          .setStep(ladderById('support_hold')!, 3, DateTime(2030, 2, 4));
    });
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
    });
    await t.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWithValue(db),
      localFlagsProvider.overrideWithValue(flags)
    ], child: const MaterialApp(home: PlanScreen())));
    await settle(t);
    final rings =
        find.widgetWithText(SwitchListTile, 'Tengo anillas disponibles');
    await t.scrollUntilVisible(rings, 200,
        scrollable: find.byType(Scrollable).first);
    expect(t.widget<SwitchListTile>(rings).value, isFalse);
    expect(flags.get<bool>(FlagKeys.hasRings), isNull);
    await t.tap(rings);
    await settle(t);
    expect(flags.get<bool>(FlagKeys.hasRings), isTrue);
    await t.tap(rings);
    await settle(t);
    expect(flags.get<bool>(FlagKeys.hasRings), isFalse);
    await t.runAsync(() async {
      expect(
          (await LadderRepository(db).state(ladderById('support_hold')!,
                  today: DateTime(2030, 2, 28)))
              .step,
          3);
      expect(await db.select(db.planVersions).get(), hasLength(1));
    });
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'soleus same-day offers no tomorrow confirmation; following morning captures dated explicit response',
      (t) => withClock(Clock.fixed(DateTime(2030, 2, 21)), () async {
            final values = <String, AccessoryQualityProof>{};
            Widget screen(DateTime day) => MaterialApp(
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: AccessoryCriteriaEditor(
                            epochs: const {'seated_soleus': '1:0'},
                            proofs: const {},
                            date: day,
                            allowAlarmRecording: true,
                            onChanged: (id, p) async {
                              values[id] = p;
                            }))));
            await t.pumpWidget(screen(DateTime(2030, 2, 21)));
            await t.pump();
            expect(find.text('Sin las señales concretas de esta guía'),
                findsNothing);
            expect(find.text('Registrar la señal concreta de esta guía'),
                findsNothing);
            await withClock(Clock.fixed(DateTime(2030, 2, 22)), () async {
              await t.pumpWidget(screen(DateTime(2030, 2, 21)));
              await t.pump();
              final toggle = find.widgetWithText(
                  TriToggle, 'Sin las señales concretas de esta guía');
              await t.ensureVisible(toggle);
              await t
                  .tap(find.descendant(of: toggle, matching: find.text('Sí')));
              await t.pump();
              expect(values['seated_soleus']!.achillesCheckedOn, '2030-02-22');
              expect(values['seated_soleus']!.alarmFree, isTrue);
            });
            expect(t.takeException(), isNull);
          }));
  testWidgets(
      'actual manual editor confirms alarm in draft then cancel preserves SQLite and no events',
      (t) => withClock(Clock.fixed(DateTime(2030, 2, 28)), () async {
            late AppDatabase db;
            late TrainingRepository training;
            late SessionDraft draft;
            late int id;
            late String original;
            await t.runAsync(() async {
              db = openInMemoryDatabase();
              training = TrainingRepository(db, ExerciseRepository(db));
              id = await training.save(SessionDraft(
                  date: DateTime(2030, 2, 21),
                  type: SessionType.piernas,
                  coreEpochs: jsonEncode({'seated_soleus': '1:0'}),
                  sets: [
                    SetDraft(exercise: 'Sóleo sentado con mochila', reps: 20)
                  ]));
              draft = await training.load(id);
              original = draft.coreEpochs!;
            });
            addTearDown(() async {
              await t.pumpWidget(const SizedBox());
              await t.runAsync(db.close);
            });
            await t.pumpWidget(ProviderScope(
                overrides: [databaseProvider.overrideWithValue(db)],
                child: MaterialApp(
                    home: Builder(
                        builder: (context) => Scaffold(
                            body: TextButton(
                                child: const Text('Abrir edición'),
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => SessionFormScreen(
                                            draft: draft,
                                            celebrate: false)))))))));
            await t.tap(find.text('Abrir edición'));
            await settle(t);
            final record =
                find.text('Registrar la señal concreta de esta guía');
            await t.scrollUntilVisible(record, 350,
                scrollable: find
                    .descendant(
                        of: find.byType(SessionFormScreen),
                        matching: find.byType(Scrollable))
                    .first,
                maxScrolls: 30);
            expect(record.hitTestable(), findsOneWidget);
            await t.tap(record);
            await t.pumpAndSettle();
            await t.tap(find.text('Confirmar'));
            await t.pumpAndSettle();
            expect(draft.accessoryCriteriaEdits, contains('seated_soleus'));
            await t.pageBack();
            await settle(t);
            await t.runAsync(() async {
              expect((await training.load(id)).coreEpochs, original);
              expect(await db.select(db.ladderEvents).get(), isEmpty);
              expect(await db.select(db.sessions).get(), hasLength(1));
            });
            expect(t.takeException(), isNull);
          }));
}
