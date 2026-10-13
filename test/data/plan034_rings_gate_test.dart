import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/accessory_quality_proof.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/enums.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test(
      'without rings criterion keeps protraction; confirmed rings permits3; disabled again preserves history',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final ex = ExerciseRepository(db),
        plan = PlanRepository(db, ExerciseRepository(db));
    final training = TrainingRepository(db, ex), ladders = LadderRepository(db);
    final start = DateTime(2030, 2, 4), today = DateTime(2030, 2, 26);
    await activatePlanV32(db, plan, start);
    final ladder = ladderById('support_hold')!;
    await ladders.setStep(ladder, 2, start);
    final state = await ladders.state(ladder, today: today);
    for (final day in [18, 21]) {
      await training.save(SessionDraft(
          date: DateTime(2030, 2, day),
          type: SessionType.trenSuperior,
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
              SetDraft(exercise: 'Support hold en paralelas', reps: 30)
          ]));
    }
    final unknown = await ladders.advice(ladder, today);
    expect(unknown.canStepUp, isFalse);
    expect(unknown.status, contains('mantén protracción'));
    expect(await ladders.acceptStepUp(ladder, today), 2);
    expect(
        (await ladders.advice(ladder, today, ringsAvailable: true)).canStepUp,
        isTrue);
    expect(await ladders.acceptStepUp(ladder, today, ringsAvailable: true), 3);
    Future<PlanDayDraft> day(bool rings) async {
      final view = (await plan.dayFor(today))!;
      return training.withV31Blocks(
          view.day, today, await training.blockDay(view, today),
          planche: true, rings: rings);
    }

    final enabled = await day(true);
    expect(
        enabled.exercises
            .singleWhere((e) => e.name == 'Support hold en paralelas')
            .physicalVariantKey,
        'support_rings');
    final disabled = await day(false);
    expect(disabled.exercises.any((e) => e.name == 'Support hold en paralelas'),
        isFalse);
    expect(disabled.notes, contains('equipo no confirmado'));
    expect((await ladders.state(ladder, today: today)).step, 3);
    expect(await db.select(db.sessions).get(), hasLength(2));
  });
  test('Achilles clearance cannot be written before the following morning',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final training = TrainingRepository(db, ExerciseRepository(db));
    final today = DateTime.now();
    final id = await training.save(SessionDraft(
        date: today,
        type: SessionType.trenSuperior,
        sideEvidenceAuthored: true,
        coreEpochs: jsonEncode({'seated_soleus': '1:0'}),
        sets: [SetDraft(exercise: 'Sóleo sentado con mochila', reps: 20)]));
    final proof = const AccessoryQualityProof(
            identity: '1:0', variantConfirmed: true, alarmFree: true)
        .encode();
    await expectLater(training.setAccessoryProofs(id, {'seated_soleus': proof}),
        throwsFormatException);
    final stored = await training.load(id);
    expect(
        (jsonDecode(stored.coreEpochs!) as Map<String, Object?>)[
            AccessoryQualityProof.key('seated_soleus')],
        isNull);
  });
}
