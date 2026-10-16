import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 054 (§16.28.1–2): el 15 oct el owner hizo la sesión de piernas en
/// vez del test, desde el 16 la app ya no lo proponía y el entrenador lo
/// quiere el mié 21. El test se elige de día, se puede saltar una vez y, en
/// el día de piernas del test, después va la sesión corta.
void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12), wed = DateTime(2026, 10, 14);
  final fri = DateTime(2026, 10, 16), tue21 = DateTime(2026, 10, 20);
  final wed21 = DateTime(2026, 10, 21);
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late DashboardRepository dashboard;
  late ReadinessRepository readiness;

  setUp(() async {
    db = openInMemoryDatabase();
    await asExistingUser(db, since: mon);
    plan = PlanRepository(db, ExerciseRepository(db));
    training = TrainingRepository(db, ExerciseRepository(db));
    readiness = ReadinessRepository(db);
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, mon, now: mon);
    dashboard = DashboardRepository(
        db, plan, NutritionRepository(db), ProfileRepository(db));
  });
  tearDown(() => db.close());

  Future<Map<String, int?>> composed(DateTime d) async {
    final view = await plan.dayFor(d);
    final day = await training.withV31Blocks(
        view!.day, d, await training.blockDay(view, d),
        planche: false);
    return {for (final e in day.exercises) e.name: e.sets};
  }

  Future<List<EffectiveTest>> overdue(DateTime today) => readiness.overdueTests(
      today,
      scheme: 'v3.1',
      blockStart: mon,
      protocol: TestProtocolId.v31_12);

  bool isLegs1(EffectiveTest t) => t.round == 1 && t.part == TestPart.piernas;

  test('el test de piernas que pasó sin hacerse sale como pendiente', () async {
    expect((await overdue(wed)).where(isLegs1), isEmpty,
        reason: 'el mismo día todavía no está vencido');
    final legs = (await overdue(fri)).singleWhere(isLegs1);
    expect(legs.date, wed);
    final home = await dashboard.today(now: fri);
    expect(home.fitnessTest, isNull);
    expect(home.overdueTest, isNotNull,
        reason: 'Hoy ofrece elegir el día del test vencido');
  });

  test('elegir el mié 21: el test va ese día y no gasta los aplazamientos',
      () async {
    expect(
        () => readiness.moveTest(
            start: mon,
            round: 1,
            part: TestPart.piernas,
            from: wed,
            to: fri,
            reasons: const ['prueba'],
            now: fri),
        throwsArgumentError,
        reason: 'hoy no es un día posterior a hoy');
    final to = await readiness.moveTest(
        start: mon,
        round: 1,
        part: TestPart.piernas,
        from: wed,
        to: wed21,
        reasons: const ['Elegido por el owner'],
        now: fri);
    expect(to, wed21);
    expect(await readiness.currentTestDate(mon, 1, TestPart.piernas), wed21);
    expect((await overdue(fri)).where(isLegs1), isEmpty);
    final agenda = (await readiness.testAgenda(
            scheme: 'v3.1',
            blockStart: mon,
            protocol: TestProtocolId.v31_12,
            gates: false))
        .singleWhere(isLegs1);
    expect((agenda.date, agenda.moves), (wed21, 0));
    final moves = await readiness.moves(mon, 1, TestPart.piernas);
    expect(moves.single.manual, isTrue);

    final home = await dashboard.today(now: wed21);
    expect((home.fitnessTest?.round, home.fitnessTest?.part),
        (1, TestPart.piernas));
    expect(home.testSkipped, isFalse);

    // El día del test (de piernas): la sesión corta, sin saltos ni sprints.
    final short = await composed(wed21);
    expect(short.keys.where((n) => n.startsWith('Salto')), isEmpty);
    expect(short.keys, isNot(contains('Aceleración 10–20 m')));
    expect(short['Sentadilla búlgara'], 2);
    expect(short['Nórdico (isquios)'], 2);
    // La víspera, sin carga de piernas.
    expect((await composed(tue21)).keys,
        isNot(contains('Sentadilla búlgara')));
  });

  test('en la fecha nominal también va la sesión corta después del test',
      () async {
    final day = await composed(wed);
    expect(day.keys.where((n) => n.startsWith('Salto')), isEmpty);
    expect(day['Sentadilla búlgara'], 2);
  });

  test('saltar el test esta vez habilita la sesión completa', () async {
    final key = TestScheduleKey(
        scheme: 'v3.1',
        blockStart: mon,
        protocolId: TestProtocolId.v31_12,
        round: 1,
        part: TestPart.piernas);
    expect(await readiness.testSkipped(key, wed), isFalse);
    await readiness.skipTest(key, wed, now: wed);
    await readiness.skipTest(key, wed, now: wed);
    expect(await readiness.testSkipped(key, wed), isTrue);
    expect((await dashboard.today(now: wed)).testSkipped, isTrue);
    final day = await composed(wed);
    expect(day.keys, contains('Salto vertical'));
    expect(day['Sentadilla búlgara'], 4);
    // Saltado no es hecho: al día siguiente sale como pendiente.
    expect((await overdue(DateTime(2026, 10, 15))).where(isLegs1), isNotEmpty);
  });
}
