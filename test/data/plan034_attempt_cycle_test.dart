import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test(
      'edit second exact attempt preserves first; delete auxiliary unlinks only second',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final repo = FitnessTestRepository(db);
    final training = TrainingRepository(db, ExerciseRepository(db));
    final day = DateTime(2030, 2, 4);
    Future<int> save(double value, {int? id}) => repo.save(
        date: day,
        round: 1,
        part: TestPart.torso,
        protocol: TestProtocolId.v32_13,
        scheme: 'v3.2',
        blockStart: day,
        attemptId: id,
        conditions: {
          'pullup': {'grip': 'prona'}
        },
        results: [TestResult(round: 1, item: 'pullup', value: value)],
        totalSec: 0);
    final first = await save(5), second = await save(8);
    final original = await db.select(db.sessions).get();
    final firstSession = original.first;
    expect(await save(9, id: second), second);
    expect(
        (await repo.all()).where((r) => r.attemptId == first).single.value, 5);
    expect((await db.select(db.sessions).get()).first, firstSession);
    final header = (await repo.attempts()).singleWhere((a) => a.id == second);
    await training.delete(header.sessionId!);
    expect(await db.select(db.sessions).get(), [firstSession]);
    final after = await repo.attempts();
    expect(after, hasLength(2));
    expect(after.singleWhere((a) => a.id == second).sessionId, isNull);
    expect(after.singleWhere((a) => a.id == first).sessionId, firstSession.id);
    expect((await repo.all()).map((r) => r.value), [5, 9]);
  });
  test(
      'changing conditions on edit appends another baseline and keeps old session detail',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final repo = FitnessTestRepository(db);
    final day = DateTime(2030, 2, 4);
    Future<int> save(String grip, {int? id}) => repo.save(
        date: day,
        round: 1,
        part: TestPart.torso,
        conditions: {
          'pullup': {'grip': grip}
        },
        attemptId: id,
        results: [const TestResult(round: 1, item: 'pullup', value: 5)],
        totalSec: 0);
    final first = await save('prona');
    final session = (await db.select(db.sessions).get()).single;
    final second = await save('supina', id: first);
    expect(second, isNot(first));
    expect((await db.select(db.sessions).get()).first, session);
    expect((await repo.all()).map((r) => r.baselineKey).toSet(), hasLength(2));
  });
}
