import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/reminder_scheduler.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/test_protocol.dart';

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

class _Sink implements NotificationSink {
  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async {}
}

/// Plan 043: lectores de la agenda de tests, los recordatorios, el informe y
/// los benchmarks del v3.2, contra SQLite real y las fronteras existentes
/// (`ReadinessRepository`, `ReminderScheduler.reschedule`,
/// `ReportRepository.load` + `buildReport`). Fechas ficticias: el bloque
/// empieza el lunes 4 de marzo de 2030; el test de piernas toca el miércoles 6.
void main() {
  setUpAll(useHostSqlite);

  final start = DateTime(2030, 3, 4);
  final wed = DateTime(2030, 3, 6), thu = DateTime(2030, 3, 7);
  TestScheduleKey key(String scheme, TestProtocolId protocol, int round, TestPart part) =>
      TestScheduleKey(scheme: scheme, blockStart: start, protocolId: protocol, round: round, part: part);

  late AppDatabase db;
  late PlanRepository plan;
  late ReadinessRepository readiness;

  setUp(() async {
    db = await asExistingUser(openInMemoryDatabase(), since: DateTime(2030, 1, 1));
    plan = PlanRepository(db, ExerciseRepository(db));
    readiness = ReadinessRepository(db);
    await seedIfEmpty(db, plan);
    await ReminderRepository(db).ensureDefaults();
  });
  tearDown(() => db.close());

  group('agenda: identidad tipada', () {
    test('un movimiento v3.1 con clave tipada es el mismo que lee la agenda v3.1', () async {
      final to = await readiness.moveTest(
          start: start,
          round: 1,
          part: TestPart.torso,
          from: start,
          reasons: const ['Carga 48 h: 1.410'],
          key: key('v3.1', TestProtocolId.v31_12, 1, TestPart.torso));
      expect(to, DateTime(2030, 3, 5));
      expect(await readiness.effectiveScheduledTest(start, DateTime(2030, 3, 5)),
          (round: 1, part: TestPart.torso, moves: 1),
          reason: 'la agenda v3.1 ve el movimiento hecho con su clave tipada');
      expect(await readiness.effectiveScheduledTest(start, start), isNull,
          reason: 'el lunes ya no tiene el test');
      expect(await readiness.moves(start, 1, TestPart.torso), hasLength(1));
    });

    test('v3.1 y v3.2 con el mismo inicio no comparten movimientos', () async {
      await readiness.moveTest(
          start: start,
          round: 1,
          part: TestPart.torso,
          from: start,
          reasons: const ['amarillo'],
          key: key('v3.2', TestProtocolId.v32_13, 1, TestPart.torso));
      expect(await readiness.effectiveScheduledTest(start, start),
          (round: 1, part: TestPart.torso, moves: 0),
          reason: 'el test de 12 del v3.1 sigue el lunes');
      expect(
          await readiness.effectiveScheduledTest(start, DateTime(2030, 3, 5),
              scheme: 'v3.2', protocol: TestProtocolId.v32_13),
          (round: 1, part: TestPart.torso, moves: 1));
    });

    test('el tercer movimiento no escribe nada', () async {
      final k = key('v3.2', TestProtocolId.v32_13, 1, TestPart.piernas);
      var from = wed;
      for (var i = 0; i < 2; i++) {
        from = (await readiness.moveTest(
            start: start, round: 1, part: TestPart.piernas, from: from, reasons: const ['x'], key: k))!;
      }
      final before = await db.select(db.coachProposals).get();
      expect(
          await readiness.moveTest(
              start: start, round: 1, part: TestPart.piernas, from: from, reasons: const ['x'], key: k),
          isNull);
      expect((await db.select(db.coachProposals).get()).length, before.length);
    });
  });

  group('recordatorios con la agenda efectiva', () {
    test('el test de piernas movido al jueves se anuncia el jueves, con escaleras y benchmarks', () async {
      await activatePlanV32(db, plan, start);
      await readiness.moveTest(
          start: start,
          round: 1,
          part: TestPart.piernas,
          from: wed,
          reasons: const ['amarillo'],
          key: key('v3.2', TestProtocolId.v32_13, 1, TestPart.piernas));
      final planned = await ReminderScheduler(
        db: db,
        plan: plan,
        reminders: ReminderRepository(db),
        nutrition: NutritionRepository(db),
        body: BodyRepository(db),
        profile: ProfileRepository(db),
        service: _Sink(),
      ).reschedule(now: DateTime(2030, 3, 4, 9), horizonDays: 7);
      PlannedNotification session(DateTime d) =>
          planned.singleWhere((n) => n.kind == ReminderKind.sesion && n.when.day == d.day);
      final thursday = session(thu);
      expect(thursday.title, contains('Test 1 de piernas'));
      expect(thursday.body, contains('Movido desde el mié 6 mar'));
      expect(thursday.body, contains('escaleras'), reason: 'el día de mañana todavía no tiene escaleras: se dice');
      expect(thursday.body, contains('Benchmarks de movilidad'));
      expect(session(wed).title, isNot(contains('Test')), reason: 'el miércoles ya no es día de test');
      expect(session(wed).body, isNot(contains('Benchmarks')));
      expect(await db.select(db.reminders).get(), hasLength(14), reason: 'sin tipos nuevos de recordatorio');
    });
  });

  group('informe', () {
    Future<String> report(DateTime from, DateTime to) async =>
        buildReport(await ReportRepository(db, NutritionRepository(db)).load(from, to, today: to));

    test('agenda movida, escaleras altas y benchmark pendiente en la semana', () async {
      await activatePlanV32(db, plan, start);
      await readiness.moveTest(
          start: start,
          round: 1,
          part: TestPart.piernas,
          from: wed,
          reasons: const ['amarillo'],
          key: key('v3.2', TestProtocolId.v32_13, 1, TestPart.piernas));
      await db.into(db.morningChecks).insert(MorningChecksCompanion.insert(date: '2030-03-07', kneeStairs: const Value(3)));
      final text = await report(start, DateTime(2030, 3, 10));
      // Plan 052 (§16.27): escaleras 3 el jueves corre piernas al miércoles
      // siguiente; los benchmarks se quedan el jueves.
      expect(text, contains('Test 1 de piernas: previsto mié 6 mar → mié 13 mar (1 de 2 movimientos)'));
      expect(text, contains('escaleras 3/10 el jue 7 mar: pasó a la siguiente sesión de piernas'));
      expect(text, contains('Benchmarks de movilidad: jue 7 mar, con el test de piernas movido · pendiente'));
    });

    test('intentos: mismas condiciones se comparan, distintas abren línea base, lo de antes no se compara', () async {
      await activatePlanV32(db, plan, start);
      final tests = FitnessTestRepository(db);
      Future<int> attempt(DateTime date, int round, double value, String grip) => tests.save(
          date: date,
          round: round,
          part: TestPart.torso,
          results: [TestResult(round: round, item: 'pullup', value: value)],
          totalSec: 0,
          protocol: TestProtocolId.v32_13,
          scheme: 'v3.2',
          blockStart: start,
          conditions: {
            'pullup': {'grip': grip}
          });
      final first = await attempt(DateTime(2030, 3, 5), 1, 8, 'prona');
      final second = await attempt(DateTime(2030, 4, 8), 2, 10, 'prona');
      final third = await attempt(DateTime(2030, 4, 8), 2, 9, 'neutro');
      await db.customStatement(
          "INSERT INTO fitness_tests(date, round, item, value, clean) VALUES('2030-04-09', 2, 'dips', 12, 1)");
      final text = await report(DateTime(2030, 4, 8), DateTime(2030, 4, 14));
      expect(text, contains('Intento #$second'));
      expect(text, contains('Dominadas pronas estrictas: 10 reps · Agarre: prona · +25 % frente al #$first (mismas condiciones)'));
      expect(text, contains('Intento #$third'));
      expect(text, contains('Dominadas pronas estrictas: 9 reps · Agarre: neutro · línea base nueva (condiciones distintas)'));
      expect(text, contains('Fondos en paralelas: 12 reps · sin intento ni condiciones: no se compara'));
      expect(text, isNot(contains('frente al #$second')), reason: 'el agarre neutro no se compara con el prono');
    });

    test('aguantes de las escaleras accesorias van en segundos aunque no estén en el plan', () async {
      await TrainingRepository(db, ExerciseRepository(db)).save(SessionDraft(
          date: DateTime(2030, 3, 5),
          type: SessionType.bloques,
          totalSec: 1200,
          sets: [
            SetDraft(exercise: 'Support hold en paralelas', reps: 25),
            SetDraft(exercise: 'Support hold en paralelas', reps: 30),
          ]));
      final text = await report(start, DateTime(2030, 3, 10));
      expect(text, contains('- Support hold en paralelas: 25 s · 30 s'));
    });
  });
}
