import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/plan_v32.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test(
      'activation today preserves yesterday and shares Monday anchor after edits',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final repo = PlanRepository(db, ExerciseRepository(db));
    final monday = DateTime(2030, 3, 4), today = DateTime(2030, 3, 5);
    final old = await repo.saveAsNewVersion(planV31(monday));
    final yesterday = await repo.dayFor(monday);
    final before = await db.customSelect('SELECT * FROM plan_versions').get();
    final id = await activatePlanV32(db, repo, today);
    expect((await repo.activeVersion(monday))!.id, old);
    expect((await repo.dayFor(monday))!.dayId, yesterday!.dayId);
    final row = (await repo.versions()).singleWhere((v) => v.id == id);
    expect(row.validFrom, '2030-03-05');
    expect(row.scheme, v32Scheme);
    final view = (await repo.dayFor(today))!;
    expect(view.validFrom, monday);
    expect((await repo.dayById(view.dayId))!.validFrom, monday);
    final training = TrainingRepository(db, ExerciseRepository(db));
    expect((await training.blockDay(view, today))!.blockStart, monday);
    expect(
        (await training.blockDay(await repo.dayFor(DateTime(2030, 3, 11)),
                DateTime(2030, 3, 11)))!
            .week,
        2);
    final edited = await repo.load(id);
    edited.validFrom = DateTime(2030, 3, 7);
    final editId = await repo.saveAsNewVersion(edited);
    expect(
        await repo.schemeStart(
            (await repo.versions()).singleWhere((v) => v.id == editId)),
        monday);
    final oldAfter = await db.customSelect('SELECT * FROM plan_versions').get();
    expect(oldAfter.first.data, before.first.data);
  });
}
