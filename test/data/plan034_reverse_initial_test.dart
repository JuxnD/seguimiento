import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  for(final sample in [(value:100.0, known:false, expected:1), (value:100.0, known:true, expected:2), (value:80.0,known:true,expected:1), (value:0.0,known:true,expected:1)]) {
    test('reverse initialization requires known attempt conditions $sample', () async {
      final db=openInMemoryDatabase(); addTearDown(db.close);
      final plan=PlanRepository(db,ExerciseRepository(db)), start=DateTime(2030,2,4);
      await activatePlanV32(db,plan,start);
      final repo=FitnessTestRepository(db);
      await repo.save(date:start,round:1,part:TestPart.torso,protocol:TestProtocolId.v32_13,scheme:'v3.2',blockStart:start,totalSec:0,results:[TestResult(round:1,item:'reverse_plank_forearm',value:sample.value)],conditions:sample.known ? {'reverse_plank_forearm':{'variant':'antebrazos','support':'suelo'}} : {});
      expect((await LadderRepository(db).state(reversePlankLadder,today:start)).step,sample.expected);
    });
  }
}
