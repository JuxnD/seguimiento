import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/reminder_scheduler.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import '../support/sqlite_host.dart';
import '../support/ready_profile.dart';

class _Sink implements NotificationSink {
  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async {}
}

void main() {
  setUpAll(useHostSqlite);
  final start = DateTime(2026, 10, 12), tue = DateTime(2026, 10, 13);
  final wed = DateTime(2026, 10, 14), thu = DateTime(2026, 10, 15);
  late AppDatabase db;
  late ReadinessRepository repo;
  const protocol = TestProtocolId.v32_13;
  TestScheduleKey key(TestPart part) => TestScheduleKey(
      scheme: 'v3.2',
      blockStart: start,
      protocolId: protocol,
      round: 1,
      part: part);
  setUp(() {
    db = openInMemoryDatabase();
    repo = ReadinessRepository(db);
  });
  tearDown(() => db.close());
  Future<void> save(
      {TestPart part = TestPart.torso,
      DateTime? date,
      DateTime? block,
      int round = 1,
      TestProtocolId p = protocol,
      bool partial = false}) async {
    final items = protocolItems(p, part);
    await FitnessTestRepository(db).save(
        date: date ?? tue,
        round: round,
        part: part,
        protocol: p,
        scheme: p == protocol ? 'v3.2' : 'v3.1',
        blockStart: block ?? start,
        totalSec: 0,
        results: [
          for (final item in partial ? items.take(1) : items)
            for (final side in item.perSide ? ['I', 'D'] : [null])
              TestResult(round: round, item: item.id, side: side, value: 5)
        ]);
  }

  Future<EffectiveTest?> on(DateTime d) => repo.effectiveTestOn(d,
      scheme: 'v3.2', blockStart: start, protocol: protocol);
  test(
      'torso real martes desplaza piernas a jueves: agenda y selector comparten resolver sin escrituras',
      () async {
    await save();
    final before =
        (await db.customSelect('SELECT total_changes() AS n').getSingle())
            .read<int>('n');
    expect(await on(wed), isNull);
    expect((await on(thu))!.part, TestPart.piernas);
    expect(
        await repo.currentTestDate(start, 1, TestPart.piernas,
            key: key(TestPart.piernas)),
        thu);
    final agenda = await repo.testAgenda(
        scheme: 'v3.2', blockStart: start, protocol: protocol, gates: false);
    expect(agenda, hasLength(6));
    final legs =
        agenda.singleWhere((t) => t.round == 1 && t.part == TestPart.piernas);
    expect((legs.planned, legs.date, legs.moves), (wed, thu, 0));
    expect(
        (await db.customSelect('SELECT total_changes() AS n').getSingle())
            .read<int>('n'),
        before);
  });
  test('lunes conserva miércoles y un torso parcial no mueve piernas',
      () async {
    await save(date: start);
    expect((await on(wed))!.part, TestPart.piernas);
    await save(partial: true);
    expect((await on(wed))!.part, TestPart.piernas);
  });
  // Plan 052, reporte real del owner (torso completo el martes, piernas
  // seguía el miércoles): el descanso sigue al esfuerzo real aunque el torso
  // se guardara con otro bloque, otro protocolo o sin agenda. Sólo la fecha.
  for (final other in ['otro bloque', 'protocolo v3.1']) {
    test('torso completo martes con $other también deja piernas el jueves',
        () async {
      if (other == 'otro bloque') {
        await save(block: DateTime(2026, 9, 14));
      } else {
        await save(p: TestProtocolId.v31_12);
      }
      expect(await on(wed), isNull);
      expect((await on(thu))!.part, TestPart.piernas);
      expect(
          await FitnessTestRepository(db).done(1, TestPart.torso,
              protocol: protocol, key: key(TestPart.torso)),
          isFalse,
          reason: 'sólo mueve la fecha: no completa el torso de este bloque');
    });
  }
  // 1.26.1, caso real del owner: el torso del martes sin el pino (piso
  // resbaloso) y con su versión v3.1 activa seguía dejando piernas el
  // miércoles.
  for (final p in [TestProtocolId.v31_12, TestProtocolId.v32_13]) {
    test('torso del martes sin el pino (${p.name}) también deja piernas el jueves',
        () async {
      final items = protocolItems(p, TestPart.torso)
          .where((i) => i.id != 'wall_handstand');
      await FitnessTestRepository(db).save(
          date: tue,
          round: 1,
          part: TestPart.torso,
          protocol: p,
          scheme: p == protocol ? 'v3.2' : 'v3.1',
          blockStart: start,
          totalSec: 0,
          results: [
            for (final item in items)
              for (final side in item.perSide ? ['I', 'D'] : [null])
                TestResult(round: 1, item: item.id, side: side, value: 5)
          ]);
      expect(await on(wed), isNull);
      expect((await on(thu))!.part, TestPart.piernas);
    });
  }
  test('torso sin agenda (botón de Cuerpo) completo martes: piernas el jueves',
      () async {
    final items = protocolItems(TestProtocolId.v31_12, TestPart.torso);
    await FitnessTestRepository(db).save(
        date: tue,
        round: 1,
        part: TestPart.torso,
        totalSec: 0,
        results: [
          for (final item in items)
            for (final side in item.perSide ? ['I', 'D'] : [null])
              TestResult(round: 1, item: item.id, side: side, value: 5)
        ]);
    expect(await on(wed), isNull);
    expect((await on(thu))!.part, TestPart.piernas);
  });
  test('v3.1 martes a jueves también cruza Dashboard.today con plan existente',
      () async {
    await asExistingUser(db, since: start);
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    // Metas vigentes desde el lunes: la lectura no depende del reloj real.
    await activatePlanV31(db, plan, start, now: start);
    await save(p: TestProtocolId.v31_12);
    final dashboard = DashboardRepository(
        db, plan, NutritionRepository(db), ProfileRepository(db));
    expect((await dashboard.today(now: wed)).fitnessTest, isNull);
    final thursday = (await dashboard.today(now: thu)).fitnessTest!;
    expect((thursday.part, thursday.done), (TestPart.piernas, false));
    await ReminderRepository(db).ensureDefaults();
    final notices = await ReminderScheduler(
            db: db,
            plan: plan,
            reminders: ReminderRepository(db),
            nutrition: NutritionRepository(db),
            body: BodyRepository(db),
            profile: ProfileRepository(db),
            service: _Sink())
        .reschedule(now: DateTime(2026, 10, 14, 8), horizonDays: 3);
    final wedSession = notices
        .singleWhere((n) => n.kind == ReminderKind.sesion && n.when.day == 14);
    final thuSession = notices
        .singleWhere((n) => n.kind == ReminderKind.sesion && n.when.day == 15);
    expect(wedSession.title, isNot(contains('Test')));
    expect(thuSession.title, contains('Test 1 de piernas'));
    final input = await ReportRepository(db, NutritionRepository(db))
        .load(start, addDays(start, 6), today: thu);
    expect(
        input.testAgenda
            .singleWhere((t) => t.round == 1 && t.part == TestPart.piernas)
            .date,
        thu);
    expect(buildReport(input), contains('Test 1 de piernas: jue 15 oct'));
  });
  test('movimiento explícito posterior, rodilla y descanso siguen mandando',
      () async {
    await repo.moveTest(
        start: start,
        round: 1,
        part: TestPart.piernas,
        from: wed,
        reasons: ['manual'],
        key: key(TestPart.piernas));
    await repo.moveTest(
        start: start,
        round: 1,
        part: TestPart.piernas,
        from: thu,
        reasons: ['manual'],
        key: key(TestPart.piernas));
    await save();
    final fri = addDays(thu, 1);
    expect(await on(thu), isNull);
    // Plan 052 (§16.27): con escaleras 3–4 ese día, piernas pasa a la
    // siguiente sesión de piernas (miércoles 21); no espera bloqueado.
    await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(
        date: dayKey(fri), kneeStairs: const Value(3)));
    expect(await on(fri), isNull);
    final next = DateTime(2026, 10, 21);
    expect((await on(next))!.part, TestPart.piernas);
    expect((await on(next))!.gate!.status, TestDayStatus.stairsUnknown);
    await RecoveryRepository(db)
        .setReadinessAnswers(next, muscleSoreness: 0, ill: true);
    expect((await on(next))!.gate!.status, TestDayStatus.rest);
  });
  test('piernas ya completas no reaparecen jueves por reajuste', () async {
    await save();
    await save(part: TestPart.piernas, date: wed);
    expect(await on(thu), isNull);
    expect(
        await FitnessTestRepository(db).done(1, TestPart.piernas,
            protocol: protocol, key: key(TestPart.piernas)),
        isTrue);
  });
  test('legacy sin cabecera y fecha inválida no inventa identidad/completitud',
      () async {
    for (final item in torsoTests) {
      for (final side in item.perSide ? ['I', 'D'] : [null]) {
        await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
            date: 'sin-fecha',
            round: 1,
            item: item.id,
            side: Value(side),
            value: 5));
      }
    }
    expect((await on(wed))!.part, TestPart.piernas);
    expect(await repo.currentTestDate(start, 1, TestPart.piernas), wed);
  });
  test(
      'legacy23 completo martes, sin cabecera, con único bloque31 vigente reajusta por lectura',
      () async {
    await asExistingUser(db, since: start);
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    // Metas vigentes desde el lunes: la lectura no depende del reloj real.
    await activatePlanV31(db, plan, start, now: start);
    for (final item in torsoTests) {
      for (final side in item.perSide ? ['I', 'D'] : [null]) {
        await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
            date: dayKey(tue),
            round: 1,
            item: item.id,
            side: Value(side),
            value: 5));
      }
    }
    final before =
        (await db.customSelect('SELECT total_changes() AS n').getSingle())
            .read<int>('n');
    final dashboard = DashboardRepository(
        db, plan, NutritionRepository(db), ProfileRepository(db));
    expect((await dashboard.today(now: wed)).fitnessTest, isNull);
    expect(
        (await dashboard.today(now: thu)).fitnessTest!.part, TestPart.piernas);
    expect(await db.select(db.fitnessTestAttempts).get(), isEmpty,
        reason: 'no backfill inventado');
    expect(
        (await db.customSelect('SELECT total_changes() AS n').getSingle())
            .read<int>('n'),
        before);
    final otherBlock = addDays(start, 7);
    expect(await repo.currentTestDate(otherBlock, 1, TestPart.piernas),
        addDays(otherBlock, 2),
        reason: 'no se hereda a otro bloque');
    await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
        date: dayKey(start), round: 1, item: 'pullup', value: 5));
    // 1.26.2: la identidad sigue desconocida con fechas mixtas, pero el
    // torso real del martes (12 pruebas antiguas sin cabecera) separa piernas.
    expect(await repo.currentTestDate(start, 1, TestPart.piernas), thu,
        reason: 'el descanso sigue al esfuerzo real');
  });
  test('Test3 piernas miércoles precede torso viernes: conserva orden nominal',
      () async {
    final legDay = repo.plannedTestDate(start, 3, TestPart.piernas)!;
    final torsoDay = repo.plannedTestDate(start, 3, TestPart.torso)!;
    expect(torsoDay.isAfter(legDay), isTrue);
    await save(round: 3, date: torsoDay);
    final agenda = await repo.testAgenda(
        scheme: 'v3.2', blockStart: start, protocol: protocol, gates: false);
    expect(
        agenda
            .singleWhere((t) => t.round == 3 && t.part == TestPart.piernas)
            .date,
        legDay);
  });
  for (final legacy in [false, true]) {
    test(
        'transición31 a32 miércoles tras torso12 martes; calendario sólo, legacy=$legacy',
        () async {
      await asExistingUser(db, since: start);
      final plan = PlanRepository(db, ExerciseRepository(db));
      await seedIfEmpty(db, plan);
      // Metas vigentes desde el lunes: la lectura no depende del reloj real.
      await activatePlanV31(db, plan, start, now: start);
      if (legacy) {
        for (final item in torsoTests) {
          for (final side in item.perSide ? ['I', 'D'] : [null]) {
            await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
                date: dayKey(tue),
                round: 1,
                item: item.id,
                side: Value(side),
                value: 5));
          }
        }
      } else {
        await save(p: TestProtocolId.v31_12);
      }
      await activatePlanV32(db, plan, wed);
      final before =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      final dashboard = DashboardRepository(
          db, plan, NutritionRepository(db), ProfileRepository(db));
      expect((await dashboard.today(now: wed)).fitnessTest, isNull);
      expect((await dashboard.today(now: thu)).fitnessTest!.part,
          TestPart.piernas);
      expect(
          await FitnessTestRepository(db).done(1, TestPart.torso,
              protocol: protocol, key: key(TestPart.torso)),
          isFalse,
          reason: 'no inventa 13 pruebas ni marcas del32');
      expect((await db.select(db.fitnessTestAttempts).get()).length,
          legacy ? 0 : 1);
      expect(
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n'),
          before);
    });
  }
  for (final scenario in [
    'activationSameDay',
    'activationOtherWeek',
    'originOtherBlock',
    'torsoAfterActivation'
  ]) {
    // Plan 052: la transición sigue sin heredar identidad ni marcas, pero el
    // torso real del martes deja piernas el jueves; sólo un torso posterior
    // a piernas no la mueve.
    test('transición rechazada: $scenario', () async {
      final plan = PlanRepository(db, ExerciseRepository(db));
      await seedIfEmpty(db, plan);
      await activatePlanV31(db, plan,
          scenario == 'originOtherBlock' ? addDays(start, -7) : start,
          now: start);
      await save(p: TestProtocolId.v31_12,
          date: scenario == 'torsoAfterActivation' ? thu : tue);
      await activatePlanV32(
          db,
          plan,
          scenario == 'activationSameDay'
              ? tue
              : scenario == 'activationOtherWeek'
                  ? addDays(start, 7)
                  : wed);
      final agenda = await repo.testAgenda(
          scheme: 'v3.2', blockStart: start, protocol: protocol, gates: false);
      expect(
          agenda
              .singleWhere((t) => t.round == 1 && t.part == TestPart.piernas)
              .date,
          scenario == 'torsoAfterActivation' ? wed : thu);
      expect(
          await FitnessTestRepository(db).done(1, TestPart.torso,
              protocol: protocol, key: key(TestPart.torso)),
          isFalse);
    });
  }
}
