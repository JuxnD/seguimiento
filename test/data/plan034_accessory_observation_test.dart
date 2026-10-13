import 'dart:convert';
import 'package:seguimiento/data/database.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/accessory_quality_proof.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/active_session.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test(
      'legacy7 stays byte-identical unknown; optional date is strict and preserved',
      () {
    const legacy =
        '{"version":1,"identity":"1:0","variantConfirmed":true,"pause2Confirmed":null,"relaxed":null,"alarmFree":true,"alarm":null}';
    final old = AccessoryQualityProof.decode(legacy)!;
    expect(old.achillesCheckedOn, isNull);
    expect(old.encode(), legacy);
    final current = const AccessoryQualityProof(
            identity: '1:0',
            variantConfirmed: true,
            alarmFree: true,
            achillesCheckedOn: '2030-02-28')
        .encode();
    expect(AccessoryQualityProof.decode(current)!.encode(), current);
    for (final day in ['2030-02-30', '2030-02-28T00:00:00', '2030-2-28']) {
      expect(
          AccessoryQualityProof.decode(
              AccessoryQualityProof(identity: '1:0', achillesCheckedOn: day)
                  .encode()),
          isNull);
    }
  });
  test(
      'soleus legacy/date-future cannot qualify; explicit checked date crosses writer and advisor',
      () => withClock(Clock.fixed(DateTime(2030, 2, 28)), () async {
            final db = openInMemoryDatabase();
            addTearDown(db.close);
            final training = TrainingRepository(db, ExerciseRepository(db)),
                ladders = LadderRepository(db);
            final ladder = ladderById('seated_soleus')!;
            await ladders.setStep(ladder, 1, DateTime(2030, 2, 4));
            final state =
                await ladders.state(ladder, today: DateTime(2030, 2, 28));
            final ids = <int>[];
            for (final day in [18, 21]) {
              ids.add(await training.save(SessionDraft(
                  date: DateTime(2030, 2, day),
                  type: SessionType.piernas,
                  techniqueOk: true,
                  fullRange: true,
                  recoveryOk: true,
                  sideEvidenceAuthored: true,
                  coreEpochs: jsonEncode({
                    ladder.id: state.identity,
                    AccessoryQualityProof.key(ladder.id): AccessoryQualityProof(
                            identity: state.identity,
                            variantConfirmed: true,
                            alarmFree: true)
                        .encode()
                  }),
                  sets: [
                    for (var i = 0; i < 3; i++)
                      SetDraft(
                          exercise: 'Sóleo sentado con mochila',
                          reps: 20,
                          rir: 1)
                  ])));
            }
            expect(
                (await ladders.advice(ladder, DateTime(2030, 2, 28)))
                    .cleanInARow,
                0);
            final proof = AccessoryQualityProof(
                    identity: state.identity,
                    variantConfirmed: true,
                    alarmFree: true,
                    achillesCheckedOn: '2030-02-28')
                .encode();
            for (final id in ids) {
              await training.setAccessoryProofs(id, {ladder.id: proof});
            }
            expect(
                (await ladders.advice(ladder, DateTime(2030, 2, 27)))
                    .cleanInARow,
                0);
            expect(
                (await ladders.advice(ladder, DateTime(2030, 2, 28))).canStepUp,
                isTrue);
            await expectLater(
                training.setAccessoryProofs(ids.first, {
                  ladder.id: AccessoryQualityProof(
                          identity: state.identity,
                          variantConfirmed: true,
                          alarmFree: true,
                          achillesCheckedOn: '2030-03-01')
                      .encode()
                }),
                throwsFormatException);
          }));
  test(
      'manual alarm writes only on save, atomically, once across replays and later dates; cannot erase',
      () => withClock(Clock.fixed(DateTime(2030, 2, 28)), () async {
            final db = openInMemoryDatabase();
            addTearDown(db.close);
            final training = TrainingRepository(db, ExerciseRepository(db)),
                ladders = LadderRepository(db);
            final ladder = ladderById('seated_soleus')!;
            await ladders.setStep(ladder, 1, DateTime(2030, 2, 4));
            final state =
                await ladders.state(ladder, today: DateTime(2030, 2, 28));
            final id = await training.save(SessionDraft(
                date: DateTime(2030, 2, 21),
                type: SessionType.piernas,
                coreEpochs: jsonEncode({ladder.id: state.identity}),
                sets: [
                  SetDraft(exercise: 'Sóleo sentado con mochila', reps: 20)
                ]));
            final draft = await training.load(id);
            draft.accessoryCriteriaEdits[ladder.id] = AccessoryQualityProof(
                    identity: state.identity,
                    alarmFree: false,
                    alarm: 'achilles_next_morning',
                    achillesCheckedOn: '2030-02-28')
                .encode();
            expect(await db.select(db.ladderEvents).get(), isEmpty,
                reason: 'editing memory/cancel never writes');
            await training.save(draft);
            expect(await db.select(db.ladderEvents).get(), hasLength(1));
            await withClock(
                Clock.fixed(DateTime(2030, 3, 1)), () => training.save(draft));
            expect(await db.select(db.ladderEvents).get(), hasLength(1));
            await expectLater(
                training.setAccessoryProofs(id, {
                  ladder.id: AccessoryQualityProof(
                          identity: state.identity,
                          alarmFree: true,
                          achillesCheckedOn: '2030-02-28')
                      .encode()
                }),
                throwsFormatException);
            final row = await training.load(id);
            final stored = (jsonDecode(row.coreEpochs!) as Map<String,
                Object?>)[AccessoryQualityProof.key(ladder.id)] as String;
            expect(AccessoryQualityProof.decode(stored)!.alarm,
                'achilles_next_morning');
          }));
  test(
      'linked/unlinked snapshots retain legacy7 and dated8 payload bytes without backfill',
      () {
    for (final proof in [
      const AccessoryQualityProof(
              identity: '1:0', variantConfirmed: true, alarmFree: true)
          .encode(),
      const AccessoryQualityProof(
              identity: '1:0',
              variantConfirmed: true,
              alarmFree: true,
              achillesCheckedOn: '2030-02-28')
          .encode(),
    ]) {
      final original = GuidedSnapshot(
          date: '2030-02-21',
          startedAt: DateTime(2030, 2, 21, 12),
          planDayId: 12,
          phase: GuidedPhase.trabajo,
          index: 0,
          accessoryProofs: {'seated_soleus': proof});
      final reopened =
          ActiveSession.fromJson(jsonDecode(jsonEncode(original.toJson())))
              as GuidedSnapshot;
      expect(reopened.accessoryProofs['seated_soleus'], proof);
      final unlinked = reopened.unlinkedAfterRestore();
      expect(unlinked.planDayId, -1);
      expect(unlinked.accessoryProofs['seated_soleus'], proof);
      expect(jsonEncode(unlinked.unlinkedAfterRestore().toJson()),
          jsonEncode(unlinked.toJson()));
    }
  });
}
