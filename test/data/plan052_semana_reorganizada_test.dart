import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 052 (§16.27, 14 oct): cuando el test de piernas se mueve, la semana
/// se reorganiza. Caso del gestor con datos ficticios: v3.2 desde el lunes
/// 12, torso movido al martes 13 y completo; piernas cae el jueves 15.
void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12), tue = DateTime(2026, 10, 13);
  final wed = DateTime(2026, 10, 14), thu = DateTime(2026, 10, 15);
  final fri = DateTime(2026, 10, 16);
  const protocol = TestProtocolId.v32_13;
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late DashboardRepository dashboard;

  TestScheduleKey key(TestPart part) => TestScheduleKey(
      scheme: 'v3.2', blockStart: mon, protocolId: protocol, round: 1, part: part);

  Future<void> torsoOn(DateTime day) => FitnessTestRepository(db).save(
      date: day,
      round: 1,
      part: TestPart.torso,
      protocol: protocol,
      scheme: 'v3.2',
      blockStart: mon,
      totalSec: 0,
      results: [
        for (final item in protocolItems(protocol, TestPart.torso))
          for (final side in item.perSide ? ['I', 'D'] : [null])
            TestResult(round: 1, item: item.id, side: side, value: 5)
      ]);

  setUp(() async {
    db = openInMemoryDatabase();
    await asExistingUser(db, since: mon);
    final ex = ExerciseRepository(db);
    plan = PlanRepository(db, ex);
    await seedIfEmpty(db, plan);
    await activatePlanV32(db, plan, mon);
    training = TrainingRepository(db, ex);
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
  });
  tearDown(() => db.close());

  Future<void> movedTorsoWeek() async {
    await ReadinessRepository(db).moveTest(
        start: mon,
        round: 1,
        part: TestPart.torso,
        from: mon,
        reasons: const ['carga del fin de semana'],
        now: mon,
        key: key(TestPart.torso));
    await torsoOn(tue);
  }

  List<String> names(TodayDashboard d) => d.mainExercises;

  test('semana del gestor: mié movilidad, jue test + piernas corta, vie Torso B sin pistol',
      () async {
    await movedTorsoWeek();
    final w = await dashboard.today(now: wed);
    expect(w.dayType, DayType.descanso, reason: 'mié: sólo movilidad');
    expect(w.weekReorganized, contains('pasa al jue'));

    final t = await dashboard.today(now: thu);
    expect(t.fitnessTest!.part, TestPart.piernas);
    final view = (await plan.dayFor(thu))!;
    final v3 = (await training.blockDay(view, thu))!;
    final day = await training.withV31Blocks(view.day, thu, v3, planche: false);
    final exercises = {for (final e in day.exercises) e.name: e};
    expect(exercises.keys.toSet().difference(TrainingRepository.testDayLegExercises), isEmpty,
        reason: 'sólo la sesión corta de piernas');
    expect(exercises.keys, contains('Sentadilla búlgara'));
    expect(exercises['Sentadilla búlgara']!.sets, 2);
    expect(exercises.keys.where((n) => n.contains('Salto') || n.contains('Sprint')), isEmpty);
    expect(day.notes, contains('test de piernas (4 pruebas) + benchmarks de movilidad (5)'));

    final f = await training.withV31Blocks((await plan.dayFor(fri))!.day, fri,
        (await training.blockDay(await plan.dayFor(fri), fri))!, planche: false);
    final thursdayTemplate = (await plan.dayFor(thu))!.day;
    expect(f.type, thursdayTemplate.type, reason: 'el viernes va el Torso B del jueves');
    expect(f.exercises.where((e) => e.name.toLowerCase().contains('pistol')), isEmpty);
    expect(f.notes, contains('desplazó el test de piernas'));
  });

  test('escaleras 3–4 el jueves: isométricos y benchmarks; piernas al mié 21 (no lun 19: 48 h del partido)',
      () async {
    await movedTorsoWeek();
    await db.into(db.morningChecks).insert(
        MorningChecksCompanion.insert(date: '2026-10-15', kneeStairs: const Value(3)));
    final view = (await plan.dayFor(thu))!;
    final day = await training.withV31Blocks(
        view.day, thu, (await training.blockDay(view, thu))!, planche: false);
    expect(day.exercises.single.name, 'Sentadilla isométrica en la pared');
    expect(day.notes, contains('pasa al mié 21'));
    final agenda = await ReadinessRepository(db)
        .testAgenda(scheme: 'v3.2', blockStart: mon, protocol: protocol, gates: false);
    expect(agenda.singleWhere((t) => t.round == 1 && t.part == TestPart.piernas).date,
        DateTime(2026, 10, 21));
  });

  test('semana nominal (torso el lunes): miércoles de piernas sin reorganizar', () async {
    await torsoOn(mon);
    final w = await dashboard.today(now: wed);
    expect(w.weekReorganized, isNull);
    expect(w.dayType, isNot(DayType.descanso));
    expect(names(w), isNotEmpty);
  });

  test('ningún test de piernas a menos de 48 h de un partido', () async {
    await torsoOn(mon);
    await training.saveFootball(FootballGamesCompanion.insert(
        date: '2026-10-13', minutes: 60, intensity: const Value(7)));
    final agenda = await ReadinessRepository(db)
        .testAgenda(scheme: 'v3.2', blockStart: mon, protocol: protocol, gates: false);
    expect(agenda.singleWhere((t) => t.round == 1 && t.part == TestPart.piernas).date,
        DateTime(2026, 10, 21));
    // El miércoles 14 sigue siendo su sesión de piernas (sólo se fue el
    // test); el martes 20, víspera, va sin carga de piernas; el 21 el test
    // va dentro de la sesión de piernas completa.
    expect((await dashboard.today(now: wed)).dayType, DayType.piernas);
    final tue20 = DateTime(2026, 10, 20);
    final eve = await training.withV31Blocks((await plan.dayFor(tue20))!.day, tue20,
        (await training.blockDay(await plan.dayFor(tue20), tue20))!, planche: false);
    expect(eve.notes, contains('sin carga de piernas'));
    final wed21 = DateTime(2026, 10, 21);
    final legsDay = await dashboard.today(now: wed21);
    expect((legsDay.dayType, legsDay.fitnessTest?.part), (DayType.piernas, TestPart.piernas));
  });

  test('día después del test de torso: sin series máximas de torso', () async {
    await movedTorsoWeek();
    // Torso el martes 13: el miércoles es movilidad; probamos un torso
    // nominal del lunes con un martes de empuje al día siguiente.
    await db.delete(db.fitnessTests).go();
    await db.delete(db.fitnessTestAttempts).go();
    await db.delete(db.coachProposals).go();
    await torsoOn(mon);
    final view = (await plan.dayFor(tue))!;
    final day = await training.withV31Blocks(
        view.day, tue, (await training.blockDay(view, tue))!, planche: false);
    expect(day.notes, contains('sin series máximas de torso'));
  });

  test('caso del teléfono: v3.1 activo, torso del martes sin el pino → mié movilidad, test el jueves',
      () async {
    final db31 = openInMemoryDatabase();
    addTearDown(db31.close);
    await asExistingUser(db31, since: mon);
    final ex = ExerciseRepository(db31);
    final plan31 = PlanRepository(db31, ex);
    await seedIfEmpty(db31, plan31);
    await activatePlanV31(db31, plan31, mon);
    final items = protocolItems(TestProtocolId.v31_12, TestPart.torso)
        .where((i) => i.id != 'wall_handstand');
    await FitnessTestRepository(db31).save(
        date: tue,
        round: 1,
        part: TestPart.torso,
        protocol: TestProtocolId.v31_12,
        scheme: 'v3.1',
        blockStart: mon,
        totalSec: 0,
        results: [
          for (final item in items)
            for (final side in item.perSide ? ['I', 'D'] : [null])
              TestResult(round: 1, item: item.id, side: side, value: 5)
        ]);
    final dash = DashboardRepository(db31, plan31, NutritionRepository(db31), ProfileRepository(db31));
    final w = await dash.today(now: wed);
    expect(w.fitnessTest, isNull, reason: 'el miércoles ya no es día de test');
    expect(w.dayType, DayType.descanso, reason: 'víspera del test: movilidad');
    expect(w.weekReorganized, contains('pasa al jue'));
    final t = await dash.today(now: thu);
    expect(t.fitnessTest!.part, TestPart.piernas);
  });
}
