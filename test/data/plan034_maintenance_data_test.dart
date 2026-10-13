import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/ladder_prescription_proof.dart';
import 'package:seguimiento/domain/enums.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test(
      'only complete explicitly prescribed maintenance is neutral; edit invalidates proof',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final training = TrainingRepository(db, ExerciseRepository(db));
    final ladders = LadderRepository(db);
    final since = DateTime(2030, 2, 4), today = DateTime(2030, 2, 28);
    await ladders.setStep(reversePlankLadder, 1, since);
    final state = await ladders.state(reversePlankLadder, today: today);
    const exercise = 'Plancha inversa sobre antebrazos';
    Future<int> save(int day, int count,
            {bool maintenance = false, bool known = true}) =>
        training.save(SessionDraft(
            date: DateTime(2030, 2, day),
            type: SessionType.trenSuperior,
            techniqueOk: known ? true : null,
            fullRange: known ? true : null,
            recoveryOk: known ? true : null,
            sideEvidenceAuthored: true,
            coreEpochs: jsonEncode({
              reversePlankLadder.id: state.identity,
              if (maintenance)
                LadderPrescriptionProof.key(reversePlankLadder.id):
                    LadderPrescriptionProof.maintenance(
                        identity: state.identity,
                        sets: 2,
                        minimum: 20,
                        perSide: false)
            }),
            sets: [
              for (var i = 0; i < count; i++)
                SetDraft(exercise: exercise, reps: 45)
            ]));
    await save(18, 3);
    await save(21, 2, maintenance: true);
    await save(25, 3);
    expect((await ladders.advice(reversePlankLadder, today)).cleanInARow, 2);
    final id = await save(26, 2, maintenance: true);
    expect((await ladders.advice(reversePlankLadder, today)).cleanInARow, 2);
    final edited = await training.load(id);
    edited.sets.removeLast();
    await training.save(edited);
    final changed = (await ladders.sessions(state, asOf: today))
        .singleWhere((s) => s.sessionId == id);
    expect(changed.maintenance, isFalse);
    expect((await ladders.advice(reversePlankLadder, today)).cleanInARow, 0);
    await save(27, 2, maintenance: true, known: false);
    expect((await ladders.advice(reversePlankLadder, today)).cleanInARow, 0);
  });
}
