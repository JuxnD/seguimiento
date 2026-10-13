import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/guided_plan_snapshot.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  for (final week in [5,6,7]) {
    for (final weekday in [DateTime.thursday, DateTime.friday]) {
      test('v32 week$week weekday$weekday composes then reduces exactly once across Home and frozen timer', () async {
        final db = openInMemoryDatabase();
        addTearDown(db.close);
        final ex = ExerciseRepository(db), plan = PlanRepository(db, ExerciseRepository(db));
        final training = TrainingRepository(db,ex);
        final start = DateTime(2030,2,4), date = DateTime(2030,2,4).add(Duration(days:(week-1)*7+weekday-1));
        await activatePlanV32(db, plan, start);
        final view = (await plan.dayFor(date))!;
        final effective = await training.withV31Blocks(view.day,date,await training.blockDay(view,date),planche:true);
        final reverse = effective.exercises.singleWhere((e)=>e.name=='Plancha inversa sobre antebrazos');
        final expected = weekday==DateTime.thursday ? (week==6 ? 2 : 3) : (week==6 ? 1 : 2);
        expect(reverse.sets,expected);
        expect(effective.coreEpochs['reverse_plank'], isNotNull);
        final snapshot = freezeGuidedDay(effective);
        final rows = (snapshot['exercises']! as List).cast<Map<String,Object?>>();
        expect(rows.singleWhere((e)=>e['name']==reverse.name)['sets'],expected);
        expect(snapshot['coreEpochs'], effective.coreEpochs);
        final dashboard = DashboardRepository(db,plan,NutritionRepository(db),ProfileRepository(db));
        final home = await dashboard.today(now:date,planche:true);
        final line = home.blockExercises.singleWhere((s)=>s.contains(reverse.name));
        expect(line, contains(expected == 1 ? '${reverse.name} 20–45s' : '${reverse.name} $expected×20–45s'));
      });
    }
  }
}

