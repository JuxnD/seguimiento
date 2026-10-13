import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/ladder_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/enums.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late TrainingRepository training;
  late LadderRepository ladders;
  final since = DateTime(2030, 2, 4);
  final today = DateTime(2030, 2, 28);
  setUp(() {
    db = openInMemoryDatabase();
    training = TrainingRepository(db, ExerciseRepository(db));
    ladders = LadderRepository(db);
  });
  tearDown(() => db.close());
  Future<int> save(DateTime date, List<SetDraft> sets,
          {bool known = true, String? epoch}) =>
      training.save(SessionDraft(
          date: date,
          type: SessionType.trenSuperior,
          sets: sets,
          techniqueOk: known ? true : null,
          fullRange: known ? true : null,
          recoveryOk: known ? true : null,
          coreEpochs: epoch));
  List<SetDraft> vela({int? invalid, bool failure = false}) => [
        for (var i = 0; i < 4; i++)
          SetDraft(
              exercise: 'Vela',
              reps: 20,
              split: i == invalid && !failure,
              toFailure: i == invalid && failure)
      ];
  Future<void> twoVela() async {
    await ladders.setStep(dragonFlagLadder, 2, since);
    await save(DateTime(2030, 2, 18), vela());
    await save(DateTime(2030, 2, 21), vela());
    expect((await ladders.advice(dragonFlagLadder, today)).canStepUp, isTrue);
  }

  test('latest unknown technique/range/recovery breaks previous clean targets',
      () async {
    await twoVela();
    await save(DateTime(2030, 2, 25), vela(), known: false);
    expect((await ladders.advice(dragonFlagLadder, today)).cleanInARow, 0);
  });
  for (final failure in [false, true]) {
    for (final position in [0, 1, 3]) {
      test(
          'any ${failure ? 'failure' : 'split'} row at $position invalidates whole latest target',
          () async {
        await twoVela();
        await save(
            DateTime(2030, 2, 25), vela(invalid: position, failure: failure));
        expect((await ladders.advice(dragonFlagLadder, today)).cleanInARow, 0);
      });
    }
  }
  test(
      'prescribed goals-only latest target breaks older complete targets; unrelated hollow does not',
      () async {
    await ladders.setStep(vUpLadder, 1, since);
    final state = await ladders.state(vUpLadder, today: today);
    final complete = [
      for (var i = 0; i < 3; i++) SetDraft(exercise: 'Tuck-up', reps: 12),
      for (var i = 0; i < 3; i++) SetDraft(exercise: hollowHold, reps: 30)
    ];
    await save(DateTime(2030, 2, 18), complete);
    await save(DateTime(2030, 2, 21), complete);
    final onlyHollow = [
      for (var i = 0; i < 3; i++) SetDraft(exercise: hollowHold, reps: 30)
    ];
    await save(DateTime(2030, 2, 24), onlyHollow);
    expect((await ladders.advice(vUpLadder, today)).canStepUp, isTrue);
    await save(DateTime(2030, 2, 25), onlyHollow,
        epoch: jsonEncode({vUpLadder.id: state.identity}));
    expect((await ladders.advice(vUpLadder, today)).cleanInARow, 0);
  });
}
