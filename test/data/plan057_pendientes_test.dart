import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/mobility_benchmark_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import 'package:seguimiento/ui/widgets.dart';
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 057: lo que quedó pendiente de §16.30 y de la auditoría 053. Bloque
/// v3.1 desde el lun 12 oct 2026 con el v3.2 desde el lun 19; sin datos
/// personales.
void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12), mon19 = DateTime(2026, 10, 19);
  final tue13 = DateTime(2026, 10, 13);
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;

  setUp(() async {
    db = openInMemoryDatabase();
    await asExistingUser(db, since: mon);
    plan = PlanRepository(db, ExerciseRepository(db));
    training = TrainingRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, mon, now: mon);
  });
  tearDown(() => db.close());

  Future<PlanDayDraft> day(DateTime d) async {
    final view = (await plan.dayFor(d))!;
    return training.withV31Blocks(
        view.day, d, await training.blockDay(view, d),
        planche: false);
  }

  Future<void> torsoTest(Map<String, double> values) =>
      FitnessTestRepository(db).save(
          date: tue13,
          round: 1,
          part: TestPart.torso,
          protocol: TestProtocolId.v31_12,
          scheme: 'v3.1',
          blockStart: mon,
          totalSec: 0,
          // Sin condiciones no hay dosis (el test real siempre lleva la
          // variante).
          conditions: {
            for (final id in values.keys)
              id: {
                'variant': 'estricta',
                if (['pullup', 'dead_hang', 'hanging_leg_raise'].contains(id))
                  'grip': 'prona',
              }
          },
          results: [
            for (final e in values.entries)
              TestResult(round: 1, item: e.key, value: e.value)
          ]);

  test('con el v3.2, la dosis del test del v3.1 cambia la sesión', () async {
    await torsoTest({'pullup': 10, 'dead_hang': 40, 'pike_pushup': 20});
    await activatePlanV32(db, plan, mon19);
    final monday = await day(mon19);
    final pull = monday.exercises
        .firstWhere((e) => e.name == 'Dominadas' && e.grip == 'prona');
    expect((pull.repsMin, pull.repsMax), (7, 8),
        reason: '70–75 % de 10, dentro del tope de 8');
    expect(pull.notes, contains('Dosis del test'));
    final pike = monday.exercises.firstWhere((e) => e.name == 'Pike push-up');
    expect((pike.repsMin, pike.repsMax), (10, 10),
        reason: '75 % de 20 = 15 supera el tope de 10: se queda en el tope');
    expect(pike.notes, contains('pike con pies elevados'));
    final tuesday = await day(DateTime(2026, 10, 20));
    final hang = tuesday.exercises
        .singleWhere((e) => e.name == 'Colgarse de la barra');
    expect((hang.holdSecMin, hang.holdSecMax), (30, 30),
        reason: 'el máximo del v3.1 (40 s) sirve en el v3.2: menos 10 s');
  });

  test('sin test, el v3.2 deja la prescripción del plan', () async {
    await activatePlanV32(db, plan, mon19);
    final pull = (await day(mon19))
        .exercises
        .firstWhere((e) => e.name == 'Dominadas' && e.grip == 'prona');
    expect((pull.repsMin, pull.repsMax), (5, 8));
  });

  test('rodilla a la pared: cada 2 semanas mientras pase de 2 cm', () async {
    final repo = MobilityBenchmarkRepository(db);
    final wed21 = DateTime(2026, 10, 21);
    expect(await repo.kneeWallDue(DateTime(2026, 11, 4)), isNull,
        reason: 'sin medición no se inventa');
    await repo.save(date: wed21, item: 'knee_to_wall', side: 'I', value: 10);
    await repo.save(date: wed21, item: 'knee_to_wall', side: 'D', value: 6.5);
    expect(await repo.kneeWallDue(DateTime(2026, 11, 3)), isNull);
    final due = await repo.kneeWallDue(DateTime(2026, 11, 4));
    expect(due?.diff, 3.5);
    final nov4 = DateTime(2026, 11, 4);
    await repo.save(date: nov4, item: 'knee_to_wall', side: 'I', value: 10);
    await repo.save(date: nov4, item: 'knee_to_wall', side: 'D', value: 9);
    expect(await repo.kneeWallDue(DateTime(2026, 11, 18)), isNull,
        reason: 'con 1 cm de diferencia ya no se repite');
  });

  test('informe: un día cargado como un solo total va en «Otro»', () {
    final total = MealEntry(
        date: tue13,
        slot: MealSlot.cena,
        items: const [
          MealItemEntry(label: 'Total oct13', macros: Macros(kcal: 2100))
        ]);
    final dinner = MealEntry(
        date: tue13,
        slot: MealSlot.cena,
        items: const [
          MealItemEntry(label: 'Arroz', macros: Macros(kcal: 400))
        ]);
    expect(total.reportSlot, MealSlot.otro);
    expect(dinner.reportSlot, MealSlot.cena);
  });

  test('un doble toque no repite la acción', () async {
    final once = SingleFlight();
    var runs = 0;
    Future<void> slow() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    await Future.wait([once.run(slow), once.run(slow)]);
    expect(runs, 1);
    await once.run(slow);
    expect(runs, 2, reason: 'terminada, se puede volver a guardar');
  });
}
