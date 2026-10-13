import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/ladder_prescription_proof.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  for (final complete in [true, false]) {
    test('dragon deload uses prescribed hollow30; companion complete=$complete',
        () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final ex = ExerciseRepository(db),
          plan = PlanRepository(db, ExerciseRepository(db));
      final training = TrainingRepository(db, ex),
          ladders = LadderRepository(db);
      await activatePlanV32(db, plan, DateTime(2030, 2, 4));
      for (final day in [4, 11, 18]) {
        final date = DateTime(2030, 3, day),
            view = (await plan.dayFor(DateTime(2030, 3, day)))!;
        final effective = await training.withV31Blocks(
            view.day, date, await training.blockDay(view, date),
            planche: false);
        final metadata = {...effective.coreEpochs};
        if (day == 11) {
          // Fixture contractual reusable en baseline sin APIs ausentes.
          metadata[LadderPrescriptionProof.key('dragon_flag')] = jsonEncode({
            'version': 2,
            'identity': '1:0',
            'prescriptionKind': 'deload',
            'scheme': 'v3.2',
            'blockStart': '2030-02-04',
            'week': 6,
            'sets': 2,
            'minimum': 8,
            'perSide': false,
            'physicalVariant': 'base:Encogimiento inverso',
            'companionGoals': {
              'Hollow body hold': {'sets': 2, 'minimum': 30, 'perSide': false}
            }
          });
        }
        await training.save(SessionDraft(
            date: date,
            type: SessionType.trenSuperior,
            techniqueOk: true,
            fullRange: true,
            recoveryOk: true,
            sideEvidenceAuthored: true,
            coreEpochs: jsonEncode(metadata),
            sets: [
              for (var i = 0; i < (day == 11 ? 2 : 3); i++)
                SetDraft(
                    exercise: 'Encogimiento inverso',
                    reps: day == 11 ? 8 : 12,
                    rir: 2),
              if (day != 11 || complete)
                for (var i = 0; i < (day == 11 ? 2 : 3); i++)
                  SetDraft(
                      exercise: 'Hollow body hold',
                      reps: day == 11 ? 30 : 40,
                      rir: 2)
            ]));
      }
      final advice =
          await ladders.advice(dragonFlagLadder, DateTime(2030, 3, 18));
      expect(advice.cleanInARow, complete ? 2 : 1);
      expect(advice.canStepUp, complete);
    });
  }
}
