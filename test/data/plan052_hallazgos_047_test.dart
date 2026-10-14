import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/plan_v32.dart';
import '../support/sqlite_host.dart';

/// Plan 052: hallazgos 2–5 de la auditoría 047 con las decisiones del owner
/// del 14 oct. Se aplican al componer el día, así que también llegan a un
/// plan v3.2 ya activado. Fechas ficticias: bloque desde el lunes 4 feb 2030.
void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  final start = DateTime(2030, 2, 4);

  setUp(() async {
    db = openInMemoryDatabase();
    final ex = ExerciseRepository(db);
    plan = PlanRepository(db, ex);
    training = TrainingRepository(db, ex);
    await activatePlanV32(db, plan, start);
  });
  tearDown(() => db.close());

  Future<PlanDayDraft> day(DateTime date) async {
    final view = (await plan.dayFor(date))!;
    return training.withV31Blocks(view.day, date, await training.blockDay(view, date), planche: false);
  }

  List<String> names(PlanDayDraft d) => [for (final e in d.exercises) e.name];

  test('hallazgo 3: el lunes calienta muñecas 2 min tras las scap pull-ups', () async {
    final monday = await day(DateTime(2030, 2, 4));
    final wrists = monday.exercises.singleWhere((e) => e.name == 'Muñecas (planche)');
    expect(wrists.holdSecMin, 120);
    expect(names(monday).indexOf('Muñecas (planche)'), names(monday).indexOf('Scap pull-up') + 1);
  });

  test('hallazgo 4: el aterrizaje progresa por semana y va tras el FIFA 11+', () async {
    Future<String?> variant(DateTime date) async =>
        (await day(date)).exercises.singleWhere((e) => e.name == 'Aterrizaje clavado').physicalVariantKey;
    expect(await variant(DateTime(2030, 2, 6)), landingBilateral, reason: 'semana 1');
    expect(await variant(DateTime(2030, 2, 20)), landingUnilateral, reason: 'semana 3');
    expect(await variant(DateTime(2030, 3, 6)), landingUnilateral, reason: 'semana 5');
    expect(await variant(DateTime(2030, 3, 13)), landingBilateral, reason: 'descarga');
    expect(await variant(DateTime(2030, 3, 20)), landingLateral, reason: 'semana 7');
    final wednesday = names(await day(DateTime(2030, 2, 6)));
    final fifa = wednesday.indexOf('Calentamiento tipo FIFA 11+');
    if (fifa >= 0) {
      expect(wednesday.indexOf('Aterrizaje clavado'), fifa + 1);
    } else {
      expect(wednesday.indexOf('Aterrizaje clavado'), lessThan(wednesday.indexOf('Sprint lanzado')));
    }
  });

  Future<String?> blocked(DateTime date) async {
    final view = (await plan.dayFor(date))!;
    return training.intervals1515Blocked(date, (await training.blockDay(view, date))!);
  }

  test('hallazgo 2: el temporizador 15/15 (045) se ofrece desde la semana 5 y no en la descarga',
      () async {
    expect(await blocked(DateTime(2030, 2, 26)), isNotNull, reason: 'semana 4');
    expect(await blocked(DateTime(2030, 3, 5)), isNull, reason: 'semana 5');
    expect(await blocked(DateTime(2030, 3, 12)), 'Intervalos 15/15: no van en la descarga.');
    expect(await blocked(DateTime(2030, 3, 19)), isNull, reason: 'semana 7');
    final week5 = await day(DateTime(2030, 3, 5));
    expect(names(week5), isNot(contains(intervals1515)),
        reason: 'no duplica el temporizador dentro de la fuerza');
    expect(week5.notes, contains('al empezar puedes elegirlos'));
    expect((await day(DateTime(2030, 3, 12))).notes, contains('no van en la descarga'));
  });

  test('hallazgo 2: con fútbol entre semana no se ofrecen y el día dice por qué', () async {
    await training.saveFootball(FootballGamesCompanion.insert(
        date: '2030-03-04', minutes: 60, intensity: const Value(6)));
    expect(await blocked(DateTime(2030, 3, 5)), contains('fútbol entre semana el 2030-03-04'));
    expect((await day(DateTime(2030, 3, 5))).notes, contains('fútbol entre semana el 2030-03-04'));
  });

  test('hallazgo 5: el bloque 2 no tiene viernes de 10 rondas (decisión del owner)', () {
    expect([for (var w = 1; w <= 9; w++) maintenanceRounds(w)], [6, 6, 6, 10, 6, 6, 6, 6, 6]);
  });
}
