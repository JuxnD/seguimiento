import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/mobility_benchmark_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_protocol.dart';

import '../support/sqlite_host.dart';

/// Plan 043: lectores nuevos de la agenda (si el test se puede hacer ese día)
/// y de los benchmarks (cada 28 días, siguiendo al test de piernas movido).
/// Fechas ficticias: bloque v3.2 desde el lunes 4 de marzo de 2030.
void main() {
  setUpAll(useHostSqlite);

  final start = DateTime(2030, 3, 4);
  final wed = DateTime(2030, 3, 6), thu = DateTime(2030, 3, 7);
  const scheme = 'v3.2', protocol = TestProtocolId.v32_13;
  final legs = TestScheduleKey(
      scheme: scheme, blockStart: start, protocolId: protocol, round: 1, part: TestPart.piernas);

  late AppDatabase db;
  late ReadinessRepository readiness;
  late MobilityBenchmarkRepository benchmarks;
  setUp(() {
    db = openInMemoryDatabase();
    readiness = ReadinessRepository(db);
    benchmarks = MobilityBenchmarkRepository(db);
  });
  tearDown(() => db.close());

  Future<EffectiveTest?> on(DateTime d) =>
      readiness.effectiveTestOn(d, scheme: scheme, blockStart: start, protocol: protocol);
  Future<void> stairs(DateTime d, int value) => db
      .into(db.morningChecks)
      .insert(MorningChecksCompanion.insert(date: dayKey(d), kneeStairs: Value(value)));

  group('agenda: si el test se hace ese día', () {
    test('piernas sin escaleras anotadas: se dice, no se supone 0', () async {
      final t = (await on(wed))!;
      expect((t.round, t.part, t.moves, t.gate!.status), (1, TestPart.piernas, 0, TestDayStatus.stairsUnknown));
      expect(t.gate!.kneeStairs, isNull);
    });

    test('escaleras 2 se hace; 3 no', () async {
      await stairs(wed, 2);
      expect((await on(wed))!.gate!.status, TestDayStatus.ready);
      await stairs(thu, 3);
      await readiness.moveTest(start: start, round: 1, part: TestPart.piernas, from: wed, reasons: const ['x'], key: legs);
      // Plan 052 (§16.27): con escaleras 3–4 ese día, piernas pasa a la
      // siguiente sesión de piernas en vez de quedar bloqueado.
      expect(await on(thu), isNull);
      final next = DateTime(wed.year, wed.month, wed.day + 7);
      final moved = (await on(next))!;
      expect((moved.planned, moved.date, moved.moved), (wed, next, true));
      expect(moved.gate!.status, TestDayStatus.stairsUnknown);
      expect(await on(wed), isNull, reason: 'el miércoles ya no tiene test');
    });

    test('el descanso de 032 manda también sobre el torso', () async {
      await RecoveryRepository(db).setReadinessAnswers(start, muscleSoreness: 0, ill: true);
      expect((await on(start))!.gate!.status, TestDayStatus.rest);
    });

    test('la agenda lista los seis tests del bloque con su día previsto', () async {
      final agenda = await readiness.testAgenda(scheme: scheme, blockStart: start, protocol: protocol, gates: false);
      expect(agenda.map((t) => (t.round, t.part)).toSet(), {
        for (final r in [1, 2, 3])
          for (final p in TestPart.values) (r, p)
      });
      expect(agenda.every((t) => t.gate == null && t.moves == 0 && t.date == t.planned), isTrue);
    });
  });

  group('benchmarks', () {
    // Plan 055 (§16.30.2): con cada test de piernas (semanas 1, 6 y 9), ya no
    // cada 28 días.
    test('con cada test de piernas; siguen al test de piernas movido', () async {
      var due = await benchmarks.schedule(
          scheme: scheme, blockStart: start, protocol: protocol, from: start, to: DateTime(2030, 4, 30));
      expect(due.map((m) => m.date), [wed, DateTime(2030, 4, 10)]);
      expect(due.every((m) => m.status == BenchmarkStatus.pending), isTrue);
      await readiness.moveTest(start: start, round: 1, part: TestPart.piernas, from: wed, reasons: const ['x'], key: legs);
      due = await benchmarks.schedule(
          scheme: scheme, blockStart: start, protocol: protocol, from: start, to: DateTime(2030, 4, 30));
      expect(due.first.date, thu);
      expect(due.first.withMovedLegTest, isTrue);
      expect(await benchmarks.dueOn(wed, scheme: scheme, blockStart: start, protocol: protocol), isNull,
          reason: 'no queda un miércoles fijo falso');
      expect((await benchmarks.dueOn(thu, scheme: scheme, blockStart: start, protocol: protocol))!.planned, wed);
    });

    test('estado: parcial con lo que falta, completo con las cinco y los dos lados; pike negativo vale', () async {
      await readiness.moveTest(start: start, round: 1, part: TestPart.piernas, from: wed, reasons: const ['x'], key: legs);
      await benchmarks.save(date: thu, item: 'knee_to_wall', side: 'I', value: 9, blockStart: start);
      await benchmarks.save(date: thu, item: 'seated_pike', value: -8, blockStart: start);
      var m = (await benchmarks.dueOn(thu, scheme: scheme, blockStart: start, protocol: protocol))!;
      expect(m.status, BenchmarkStatus.partial);
      expect(m.missing, ['knee_to_wall (D)', 'pancake', 'shoulder_wall', 'deep_squat']);
      await benchmarks.save(date: thu, item: 'knee_to_wall', side: 'D', value: 10, blockStart: start);
      await benchmarks.save(date: thu, item: 'pancake', value: 0, blockStart: start);
      await benchmarks.save(date: thu, item: 'shoulder_wall', touches: false, blockStart: start);
      await benchmarks.save(date: thu, item: 'deep_squat', value: 35, blockStart: start);
      m = (await benchmarks.dueOn(thu, scheme: scheme, blockStart: start, protocol: protocol))!;
      expect(m.status, BenchmarkStatus.complete);
      expect(m.missing, isEmpty);
      final rows = await db.select(db.mobilityBenchmarks).get();
      expect(rows.singleWhere((r) => r.item == 'seated_pike').value, -8, reason: 'el valor firmado se conserva');
      expect(rows.singleWhere((r) => r.item == 'shoulder_wall').touches, isFalse);
    });

    test('corte asOf: lo medido después no completa una consulta anterior', () async {
      final later = DateTime(2030, 3, 16);
      for (final (item, side) in [
        ('knee_to_wall', 'I'),
        ('knee_to_wall', 'D'),
        ('seated_pike', null),
        ('pancake', null),
        ('deep_squat', null)
      ]) {
        await benchmarks.save(date: later, item: item, side: side, value: 5, blockStart: start);
      }
      await benchmarks.save(date: later, item: 'shoulder_wall', touches: true, blockStart: start);
      Future<BenchmarkStatus> asOf(DateTime d) async =>
          (await benchmarks.dueOn(wed, scheme: scheme, blockStart: start, protocol: protocol, asOf: d))!.status;
      expect(await asOf(wed), BenchmarkStatus.pending, reason: 'el día de la toma todavía no se midió');
      expect(await asOf(DateTime(2030, 3, 15)), BenchmarkStatus.pending);
      expect(await asOf(later), BenchmarkStatus.complete, reason: 'cuenta desde el día en que se midió');
      expect((await db.select(db.mobilityBenchmarks).get()).map((r) => r.date).toSet(), {'2030-03-16'},
          reason: 'la fecha real de la medición se conserva');
    });

    test('mediciones de otro bloque no completan esta toma', () async {
      for (final (item, side) in [
        ('knee_to_wall', 'I'),
        ('knee_to_wall', 'D'),
        ('seated_pike', null),
        ('pancake', null),
        ('deep_squat', null)
      ]) {
        await benchmarks.save(date: wed, item: item, side: side, value: 5, blockStart: DateTime(2030, 1, 7));
      }
      expect((await benchmarks.dueOn(wed, scheme: scheme, blockStart: start, protocol: protocol))!.status,
          BenchmarkStatus.pending);
    });
  });
}
