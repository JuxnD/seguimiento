import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/accessory_quality_proof.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/series_side_proof.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  const cases = <String, (String, List<int>, List<String?>, int?)>{
    'copenhagen': ('Copenhague', [15, 15], ['I', 'D'], null),
    'seated_soleus': ('Sóleo sentado con mochila', [20, 20, 20], [], 1),
    'tibialis_wall': ('Tibial en la pared', [25, 25], [], null),
    'band_external_rotation': (
      'Rotación externa con banda',
      [20, 20],
      [],
      null
    ),
    'prone_y_t': ('Y-T prono', [12, 12], [], null),
    'support_hold': ('Support hold en paralelas', [30, 30, 30], [], null),
    'flying_sprint': ('Sprint lanzado', [1, 1, 1], [], null),
  };
  for (final entry in cases.entries) {
    test(
        '${entry.key}: actual known criterion twice and14days; unknown/partial latest breaks',
        () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final ladder = ladderById(entry.key)!;
      final ladders = LadderRepository(db),
          training = TrainingRepository(db, ExerciseRepository(db));
      final since = DateTime(2030, 2, 4), today = DateTime(2030, 2, 28);
      await ladders.setStep(ladder, 1, since);
      final state = await ladders.state(ladder, today: today);
      final data = entry.value;
      Future<void> save(int day,
          {bool known = true, bool partial = false}) async {
        final p = AccessoryQualityProof(
            achillesCheckedOn:
                entry.key == 'seated_soleus' && known ? '2030-02-28' : null,
            identity: state.identity,
            variantConfirmed: known ? true : null,
            alarmFree: known ? true : null,
            pause2Confirmed: known ? true : null,
            relaxed: known ? true : null);
        final values =
            partial ? data.$2.take(data.$2.length - 1).toList() : data.$2;
        await training.save(SessionDraft(
            date: DateTime(2030, 2, day),
            type: SessionType.trenSuperior,
            techniqueOk: true,
            fullRange: true,
            recoveryOk: true,
            sideEvidenceAuthored: true,
            coreEpochs: jsonEncode({
              ladder.id: state.identity,
              AccessoryQualityProof.key(ladder.id): p.encode(),
              if (data.$3.isNotEmpty)
                SeriesSideProof.key(data.$1): SeriesSideProof.encode(data.$3)
            }),
            sets: [
              for (final v in values)
                SetDraft(exercise: data.$1, reps: v, rir: data.$4)
            ]));
      }

      await save(18);
      await save(21);
      expect((await ladders.advice(ladder, today)).canStepUp, isTrue);
      await save(24, known: false);
      expect((await ladders.advice(ladder, today)).cleanInARow, 0);
      await save(25);
      await save(26);
      expect((await ladders.advice(ladder, today)).canStepUp, isTrue);
      await save(27, partial: true);
      expect((await ladders.advice(ladder, today)).cleanInARow, 0);
    });
  }
}
