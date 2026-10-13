import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import 'package:seguimiento/domain/fitness_test.dart';

import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/mobility_benchmark_repository.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import '../support/ready_profile.dart';

// Independent synthetic collision oracle. Product source remains frozen.
void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open('winsqlite3.dll'));
    }
  });
  test('moving torso twice preserves both typed identities on the shared Wednesday', () async {
    final db = openInMemoryDatabase();
    try {
      final start = DateTime(2030, 3, 4);
      final readiness = ReadinessRepository(db);
      final key = TestScheduleKey(
          scheme: 'v3.2', blockStart: start, protocolId: TestProtocolId.v32_13, round: 1, part: TestPart.torso);
      var from = start;
      for (var i = 0; i < 2; i++) {
        from = (await readiness.moveTest(
            start: start,
            round: 1,
            part: TestPart.torso,
            from: from,
            reasons: const ['synthetic'],
            key: key,
            now: from))!;
      }
      final agenda =
          await readiness.testAgenda(scheme: 'v3.2', blockStart: start, protocol: TestProtocolId.v32_13, gates: false);
      expect(agenda, hasLength(6), reason: 'rescheduling never deletes a scheduled identity');
      final sameDay = agenda.where((t) => t.date == DateTime(2030, 3, 6)).toList();
      expect(sameDay.map((t) => t.part).toSet(), {TestPart.torso, TestPart.piernas});
      expect(sameDay.singleWhere((t) => t.part == TestPart.torso).moves, 2);
      expect(sameDay.singleWhere((t) => t.part == TestPart.piernas).moves, 0);
    } finally {
      await db.close();
    }
  });
  test('collision readers preserve both report entries, leg benchmark and daily priority without writes', () async {
    final db = await asExistingUser(openInMemoryDatabase(), since: DateTime(2030, 1, 1));
    try {
      final start = DateTime(2030, 3, 4), wed = DateTime(2030, 3, 6);
      final plan = PlanRepository(db, ExerciseRepository(db));
      await seedIfEmpty(db, plan);
      await activatePlanV32(db, plan, start);
      final readiness = ReadinessRepository(db);
      final key = TestScheduleKey(
          scheme: 'v3.2', blockStart: start, protocolId: TestProtocolId.v32_13, round: 1, part: TestPart.torso);
      var from = start;
      for (var i = 0; i < 2; i++) {
        from = (await readiness.moveTest(
            start: start,
            round: 1,
            part: TestPart.torso,
            from: from,
            reasons: const ['synthetic'],
            key: key,
            now: from))!;
      }
      final before = await db.select(db.coachProposals).get();
      final changesBefore = (await db.customSelect('SELECT total_changes() AS n').getSingle()).read<int>('n');
      final agenda = await readiness.testAgenda(scheme: 'v3.2', blockStart: start, protocol: TestProtocolId.v32_13);
      expect(agenda, hasLength(6));
      expect(agenda.map((t) => (t.round, t.part)).toSet(), {
        for (final r in [1, 2, 3])
          for (final p in TestPart.values) (r, p)
      });
      final legs = agenda.singleWhere((t) => t.round == 1 && t.part == TestPart.piernas);
      expect((legs.planned, legs.date, legs.moves, legs.gate!.status), (wed, wed, 0, TestDayStatus.stairsUnknown));
      final today =
          (await readiness.effectiveTestOn(wed, scheme: 'v3.2', blockStart: start, protocol: TestProtocolId.v32_13))!;
      expect((today.part, today.moves), (TestPart.torso, 2));
      expect(await readiness.effectiveScheduledTest(start, start), (round: 1, part: TestPart.torso, moves: 0),
          reason: 'legacy v3.1 identity stays separate');
      final benchmark = (await MobilityBenchmarkRepository(db)
          .dueOn(wed, scheme: 'v3.2', blockStart: start, protocol: TestProtocolId.v32_13))!;
      expect((benchmark.planned, benchmark.date, benchmark.withMovedLegTest, benchmark.status),
          (wed, wed, false, BenchmarkStatus.pending));
      final input = await ReportRepository(db, NutritionRepository(db))
          .load(start, DateTime(2030, 3, 10), today: DateTime(2030, 3, 10));
      expect(input.testAgenda.map((t) => t.part).toSet(), {TestPart.torso, TestPart.piernas});
      final report = buildReport(input);
      expect(report, contains('Test 1 de torso: previsto lun 4 mar → mié 6 mar (2 de 2 movimientos)'));
      expect(report, contains('Test 1 de piernas: mié 6 mar'));
      final cutoff = await ReportRepository(db, NutritionRepository(db)).load(start, start, today: start);
      expect(cutoff.testAgenda.map((t) => t.part), [TestPart.torso],
          reason: 'range keeps moved planned torso, not future legs');
      expect((await db.customSelect('SELECT total_changes() AS n').getSingle()).read<int>('n'), changesBefore,
          reason: 'all agenda/report/benchmark reads are pure; no automatic postponement');
      expect(
          await readiness.moveTest(
              start: start, round: 1, part: TestPart.torso, from: wed, reasons: const ['third'], key: key),
          isNull);
      final after = await db.select(db.coachProposals).get();
      expect(after.map((r) => (r.id, r.evidence, r.reviewAfter)), before.map((r) => (r.id, r.evidence, r.reviewAfter)));
    } finally {
      await db.close();
    }
  });
}
