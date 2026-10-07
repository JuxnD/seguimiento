// Execute against afaaf86 genuine schema19 source only.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/domain/fitness_test.dart';

import '../test/support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test('freeze genuine19 test clock, ladder and imported records', () async {
    final output = Platform.environment['SCHEMA19_OUTPUT'];
    if (output == null) throw StateError('SCHEMA19_OUTPUT is required');
    final file = File(output);
    if (file.existsSync()) throw StateError('Refuse to overwrite fixture');
    final db = AppDatabase(NativeDatabase(file));
    try {
      expect(db.schemaVersion, 19);
      await db.customStatement('SELECT 1');
      await ReminderRepository(db).ensureDefaults();
      await db.customStatement(
          "UPDATE profiles SET start_date='2026-09-28' WHERE id=1");
      await db.customStatement(
          "INSERT INTO exercises(id,name) VALUES(901,'Encogimiento inverso')");
      await db.customStatement(
          "INSERT INTO sessions(id,date,start_time,type,total_sec,warmup_sec,cooldown_sec,rest_sec,rpe,context,notes,technique_ok,full_range,recovery_ok) VALUES(902,'2026-10-19','07:20','bloques',1500,360,180,300,7,'QA schema19: core','Preservar todos los campos',1,1,1)");
      await db.customStatement(
          'INSERT INTO session_sets(id,session_id,exercise_id,set_index,reps,rir) VALUES(903,902,901,1,12,2)');
      await FitnessTestRepository(db).save(
        date: DateTime(2026, 10, 12),
        round: 1,
        part: TestPart.torso,
        results: const [
          TestResult(round: 1, item: 'pullup', value: 8),
          TestResult(round: 1, item: 'wall_handstand', value: 35, clean: false),
          TestResult(round: 1, item: 'one_arm_pushup', side: 'I', value: 3)
        ],
        totalSec: 3600,
      );
      await db.customStatement(
          "INSERT INTO ladder_states(ladder,step,since,lumbar_on) VALUES('dragon_flag',2,'2026-10-12','2026-10-19'),('v_up',3,'2026-10-15',NULL)");
      await db.customStatement(
          "INSERT INTO sessions(id,date,type,total_sec,rounds_done,mode,context,imported) VALUES(906,'2026-09-11','resistencia',960,7,'cindy','QA importado',1)");
      await db.customStatement(
          "INSERT INTO football_games(id,date,minutes,notes,imported) VALUES(907,'2026-09-13',0,'QA por confirmar',1)");
      expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          19);
    } finally {
      await db.close();
    }
    final reopened = AppDatabase(NativeDatabase(file));
    try {
      expect(await reopened.select(reopened.fitnessTests).get(), hasLength(3));
      final testSession = await reopened
          .customSelect("SELECT total_sec FROM sessions WHERE mode='test'")
          .getSingle();
      expect(testSession.data['total_sec'], 3600);
    } finally {
      await reopened.close();
    }
  });
}
