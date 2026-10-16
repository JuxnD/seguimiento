import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/mobility_benchmark_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/plan_v3.dart';
import 'package:seguimiento/domain/plan_v32.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 055 (§16.30): respuesta del entrenador al manual de 1.27.1. El v3.2
/// se activa el lun 19 oct sobre el v3.1 del lun 12 y sigue su bloque; el
/// calendario de tests queda como lo aceptó el entrenador. Fechas del bloque
/// real, sin datos personales.
void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12), mon19 = DateTime(2026, 10, 19);
  final wed14 = DateTime(2026, 10, 14), wed21 = DateTime(2026, 10, 21);
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late ReadinessRepository readiness;

  setUp(() async {
    db = openInMemoryDatabase();
    await asExistingUser(db, since: mon);
    plan = PlanRepository(db, ExerciseRepository(db));
    training = TrainingRepository(db, ExerciseRepository(db));
    readiness = ReadinessRepository(db);
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, mon, now: mon);
  });
  tearDown(() => db.close());

  Future<V3Day?> block(DateTime d) async =>
      training.blockDay(await plan.dayFor(d), d);

  test('el v3.2 activado el lun 19 sigue el bloque del v3.1 (semana 2)',
      () async {
    await activatePlanV32(db, plan, mon19);
    final v3 = (await block(mon19))!;
    expect((v3.isV32, v3.week, v3.blockStart), (true, 2, mon));
    expect((await block(DateTime(2026, 11, 16)))!.reducedVolume, isTrue,
        reason: 'la descarga sigue siendo la semana del 16 nov');
    expect((await block(DateTime(2026, 10, 16)))!.isV32, isFalse,
        reason: 'los días anteriores conservan su plan');
  });

  test('7.000 pasos entre semana desde que rige el v3.2', () async {
    await activatePlanV32(db, plan, mon19);
    final h = await GoalRepository(db).history();
    expect(goalReferenceOn(h, GoalMetric.pasos, DateTime(2026, 10, 16)).value,
        isNot(7000));
    expect(goalReferenceOn(h, GoalMetric.pasos, mon19).value, 7000);
  });

  test('calendario de tests de §16.30.2', () {
    final dates = {
      for (var i = 0; i < 70; i++)
        if (scheduledTest(mon, mon.add(Duration(days: i))) case final t?)
          '${t.round}${t.part.name}': mon.add(Duration(days: i))
    };
    expect(dates['1torso'], mon);
    expect(dates['2torso'], DateTime(2026, 11, 16));
    expect(dates['2piernas'], DateTime(2026, 11, 18));
    expect(dates['3torso'], DateTime(2026, 12, 7), reason: 'no el vie 11');
    expect(dates['3piernas'], DateTime(2026, 12, 9));
  });

  test('viernes del v3.2: Cindy 23 oct, 20 nov y 11 dic; 10 rondas 6 nov y 4 dic',
      () {
    ({ResistanceMode? mode, bool cindyTest}) friday(DateTime d) {
      final v = v3Day(mon, d, scheme: v32Scheme)!;
      return (mode: v.resistance, cindyTest: v.cindyTest);
    }

    for (final d in [
      DateTime(2026, 10, 23),
      DateTime(2026, 11, 20),
      DateTime(2026, 12, 11)
    ]) {
      expect(friday(d), (mode: ResistanceMode.cindy, cindyTest: true),
          reason: '$d');
    }
    for (final d in [DateTime(2026, 11, 6), DateTime(2026, 12, 4)]) {
      expect(friday(d).mode, ResistanceMode.porTiempo, reason: '$d');
    }
    expect(friday(DateTime(2026, 10, 30)).mode, isNull,
        reason: 'los demás viernes, mantenimiento');
    expect([for (var w = 1; w <= 9; w++) maintenanceRounds(w)],
        [6, 6, 6, 10, 6, 6, 6, 10, 6]);
  });

  test('un test con una prueba pendiente (pino sin colchoneta) no sale vencido',
      () async {
    final tue = DateTime(2026, 10, 13);
    await FitnessTestRepository(db).save(
        date: tue,
        round: 1,
        part: TestPart.torso,
        protocol: TestProtocolId.v31_12,
        scheme: 'v3.1',
        blockStart: mon,
        totalSec: 0,
        results: const [TestResult(round: 1, item: 'pullup', value: 8)]);
    final overdue = await readiness.overdueTests(DateTime(2026, 10, 16),
        scheme: 'v3.1', blockStart: mon, protocol: TestProtocolId.v31_12);
    expect([for (final t in overdue) (t.round, t.part)],
        [(1, TestPart.piernas)],
        reason: 'el torso del 13 ya se hizo; piernas no');
    // Con el v3.2, el intento del v3.1 del mismo bloque también cuenta.
    final v32 = await readiness.overdueTests(DateTime(2026, 10, 19),
        scheme: v32Scheme, blockStart: mon, protocol: TestProtocolId.v32_13);
    expect(v32.where((t) => t.part == TestPart.torso), isEmpty);
  });

  test('el test movido con el v3.1 conserva su día con el v3.2', () async {
    await readiness.moveTest(
        start: mon,
        round: 1,
        part: TestPart.piernas,
        from: wed14,
        to: wed21,
        reasons: const ['Elegido por el owner'],
        now: DateTime(2026, 10, 16));
    await activatePlanV32(db, plan, mon19);
    final key = TestScheduleKey(
        scheme: v32Scheme,
        blockStart: mon,
        protocolId: TestProtocolId.v32_13,
        round: 1,
        part: TestPart.piernas);
    expect(await readiness.currentTestDate(mon, 1, TestPart.piernas, key: key),
        wed21);
  });

  test('los benchmarks van con cada test de piernas', () async {
    final takes = await MobilityBenchmarkRepository(db).schedule(
        scheme: 'v3.1',
        blockStart: mon,
        protocol: TestProtocolId.v31_12,
        from: mon,
        to: DateTime(2026, 12, 20));
    expect([for (final t in takes) t.date],
        [wed14, DateTime(2026, 11, 18), DateTime(2026, 12, 9)],
        reason: 'sin la toma del 11 nov');
  });

  test('semanas 1 y 2: RIR mínimo 2–3; el nórdico, 2 series al empezar',
      () async {
    Future<PlanDayDraft> day(DateTime d) async {
      final view = (await plan.dayFor(d))!;
      return training.withV31Blocks(
          view.day, d, await training.blockDay(view, d),
          planche: false);
    }

    final pull = (await day(mon19))
        .exercises
        .firstWhere((e) => e.name == 'Dominadas');
    expect((pull.rirMin, pull.rirMax), (2, 3));
    final week3 = (await day(DateTime(2026, 10, 26)))
        .exercises
        .firstWhere((e) => e.name == 'Dominadas');
    expect((week3.rirMin, week3.rirMax), (1, 2), reason: 'desde la semana 3');
    final nordic = (await day(DateTime(2026, 10, 28)))
        .exercises
        .singleWhere((e) => e.name == 'Nórdico (isquios)');
    expect(nordic.sets, 2, reason: 'sin registro, las 2 primeras semanas');
  });

  test('la víspera de un test avisa a las 20:00', () {
    final today = DateTime(2026, 10, 20, 9);
    final planned = planReminders(ReminderContext(
      now: today,
      days: [
        ReminderDay(
            date: DateTime(2026, 10, 20),
            type: DayType.trenSuperior,
            hasSession: false),
        ReminderDay(
            date: wed21,
            type: DayType.piernas,
            hasSession: false,
            test: const ReminderTest(title: 'Test 1 de piernas')),
      ],
      settings: {
        ReminderKind.visperaTest: const ReminderSetting(
            kind: ReminderKind.visperaTest, enabled: true, hour: 20, minute: 0),
      },
    ));
    final eve = planned.singleWhere((n) => n.kind == ReminderKind.visperaTest);
    expect(eve.when, DateTime(2026, 10, 20, 20));
    expect(eve.title, 'Mañana: Test 1 de piernas');
    expect(eve.body, contains('cena con carbohidrato y poca grasa'));
  });
}
