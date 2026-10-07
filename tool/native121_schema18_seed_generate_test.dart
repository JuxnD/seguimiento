// QA only: run against genuine source410da05/schema18, never the candidate.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart';
import '../test/support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test('freeze native upgrade schema18 and genuine legacy guided snapshot', () async {
    final input = File(Platform.environment['NATIVE121_SEED_INPUT']!);
    final dir = Directory(Platform.environment['NATIVE121_SEED_OUTPUT']!);
    if (dir.existsSync()) throw StateError('Refuse overwrite QA directory');
    dir.createSync(recursive: true);
    final file = input.copySync('${dir.path}/seguimiento.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    try {
      expect(db.schemaVersion, 18);
      final plan = PlanRepository(db, ExerciseRepository(db));
      final training = TrainingRepository(db, ExerciseRepository(db));
      await seedIfEmpty(db, plan);
      await seedFoodsIfEmpty(db);
      await activatePlanV31(db, plan, DateTime(2026, 10, 12));
      final date = DateTime(2026, 10, 19);
      final view = (await plan.dayFor(date))!;
      final day = await training.withPlanche(view.day, date, await training.blockDay(view, date), enabled: false);
      final script = buildScript(scriptDayFrom(day));
      final index = script.lastIndexWhere((s) => s is WorkStep);
      final snapshot = GuidedSnapshot(
          date: '2026-10-19',
          startedAt: DateTime.now().toUtc(),
          planDayId: view.dayId,
          phase: GuidedPhase.trabajo,
          index: index,
          workStartedAt: DateTime.now().toUtc(),
          done: const [DoneStep('Dominadas', 8, false, loadKg: 4.5, rir: 2)]);
      final snapJson = snapshot.toJson();
      expect(snapJson.containsKey('effectiveDay'), isFalse, reason: 'real1.20 serialization');
      final snapFile = File('${dir.path}/sesion-en-curso.json');
      await snapFile.writeAsString(jsonEncode(snapJson), flush: true);
      final steps = [
        for (final s in script)
          switch (s) {
            final WorkStep w => {
                'kind': 'work',
                'exercise': w.exercise,
                'targetLabel': w.targetLabel,
                'targetReps': w.targetReps,
                'holdSec': w.holdSec,
                'holdSecMax': w.holdSecMax,
                'position': w.position,
                'total': w.total,
                'isRound': w.isRound,
                'blockName': w.blockName,
                'grip': w.grip,
                'side': w.side
              },
            final RestStep r => {'kind': 'rest', 'seconds': r.seconds, 'maxSec': r.maxSec, 'nextLabel': r.nextLabel}
          }
      ];
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.close();
      await File('${dir.path}/manifest.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'syntheticOnly': true,
            'sourceCommit': '410da05d341d8ea88915fe8a197d3df6eee54283',
            'schema': 18,
            'databaseSha256': sha256.convert(file.readAsBytesSync()).toString(),
            'snapshotSha256': sha256.convert(snapFile.readAsBytesSync()).toString(),
            'index': index,
            'expectedStep': steps[index],
            'steps': steps,
            'legacySnapshot': snapJson,
          }),
          flush: true);
    } catch (_) {
      await db.close();
      rethrow;
    }
  });
}
