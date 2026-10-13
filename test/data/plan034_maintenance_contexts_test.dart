import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/ladder_prescription_proof.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test(
      'only four explicit accessory contexts freeze maintenance; primary targets stay targets',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final ex = ExerciseRepository(db),
        plan = PlanRepository(db, ExerciseRepository(db));
    final training = TrainingRepository(db, ex);
    final start = DateTime(2030, 2, 4);
    await activatePlanV32(db, plan, start);
    Future<Map<String, String>> on(int day) async {
      final date = DateTime(2030, 2, day),
          view = (await plan.dayFor(DateTime(2030, 2, day)))!;
      return (await training.withV31Blocks(
              view.day, date, await training.blockDay(view, date),
              planche: true))
          .coreEpochs;
    }

    final thu = await on(7),
        fri = await on(8),
        tue = await on(5),
        wed = await on(6),
        mon = await on(4);
    for (final (metadata, id, sets, minimum) in [
      (thu, 'support_hold', 2, 30),
      (thu, 'band_external_rotation', 2, 15),
      (fri, 'seated_soleus', 2, 15),
      (fri, 'tibialis_wall', 2, 20),
    ]) {
      final p = LadderPrescriptionProof.decode(
          metadata[LadderPrescriptionProof.key(id)], metadata[id]!);
      expect(p, (sets: sets, minimum: minimum, perSide: false));
    }
    expect(tue[LadderPrescriptionProof.key('support_hold')], isNull);
    expect(wed[LadderPrescriptionProof.key('seated_soleus')], isNull);
    expect(mon[LadderPrescriptionProof.key('band_external_rotation')], isNull);
    expect(tue[LadderPrescriptionProof.key('tibialis_wall')], isNull);
    expect(coreLadders, hasLength(3));
    expect(v32AccessoryLadders, hasLength(7));
    expect((await LadderRepository(db).activeLadders(start)), hasLength(10));
  });
}
