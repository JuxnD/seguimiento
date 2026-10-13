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
  for (final variant in [
    'complete',
    'partial',
    'unknown',
    'wrongEpoch',
    'forgedDose',
    'bad',
    'corruptFullTarget',
    'overdose'
  ]) {
    test('declared complete deload neutral; $variant cannot hide failure',
        () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final ex = ExerciseRepository(db),
          plan = PlanRepository(db, ExerciseRepository(db));
      final training = TrainingRepository(db, ex),
          ladders = LadderRepository(db);
      await activatePlanV32(db, plan, DateTime(2030, 2, 4));
      for (final day in [7, 14, 21]) {
        final date = DateTime(2030, 3, day),
            view = (await plan.dayFor(DateTime(2030, 3, day)))!;
        final prescription = await training.withV31Blocks(
            view.day, date, await training.blockDay(view, date),
            planche: false);
        final metadata = {...prescription.coreEpochs};
        if (day == 14) {
          // Input contractual explícito para el rojo contra b2d4; no llamamos
          // una API ausente ni hacemos fallar el harness por una clave null.
          metadata.putIfAbsent(
              LadderPrescriptionProof.key('reverse_plank'),
              () => jsonEncode({
                    'version': 2,
                    'identity': '1:0',
                    'prescriptionKind': 'deload',
                    'scheme': 'v3.2',
                    'blockStart': '2030-02-04',
                    'week': 6,
                    'sets': 2,
                    'minimum': 20,
                    'perSide': false,
                    'physicalVariant': 'base:Plancha inversa sobre antebrazos',
                    'companionGoals': <String, Object?>{}
                  }));
        }
        if (day == 14 &&
            ['wrongEpoch', 'forgedDose', 'corruptFullTarget']
                .contains(variant)) {
          final key = LadderPrescriptionProof.key('reverse_plank');
          final raw =
              (jsonDecode(metadata[key]!) as Map).cast<String, Object?>();
          if (['wrongEpoch', 'corruptFullTarget'].contains(variant)) {
            raw['identity'] = '1:999';
          }
          if (variant == 'forgedDose') {
            raw['sets'] = 1;
            raw['minimum'] = 1;
          }
          metadata[key] = jsonEncode(raw);
        }
        final count = day == 14
            ? (['corruptFullTarget', 'overdose'].contains(variant)
                ? 3
                : ['partial', 'forgedDose'].contains(variant)
                    ? 1
                    : 2)
            : 3;
        await training.save(SessionDraft(
            date: date,
            type: SessionType.trenSuperior,
            techniqueOk: day == 14 && variant == 'unknown' ? null : true,
            fullRange: day == 14 && variant == 'bad' ? false : true,
            recoveryOk: true,
            sideEvidenceAuthored: true,
            coreEpochs: jsonEncode(metadata),
            sets: [
              for (var i = 0; i < count; i++)
                SetDraft(
                    exercise: 'Plancha inversa sobre antebrazos',
                    reps: day == 14 &&
                            !['corruptFullTarget', 'overdose'].contains(variant)
                        ? 20
                        : 45)
            ]));
      }
      final advice =
          await ladders.advice(reversePlankLadder, DateTime(2030, 3, 21));
      expect(advice.cleanInARow, variant == 'complete' ? 2 : 1);
      expect(advice.canStepUp, variant == 'complete');
      expect((await db.select(db.sessions).get()), hasLength(3));
    });
  }
}
