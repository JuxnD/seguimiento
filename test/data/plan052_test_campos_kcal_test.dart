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
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/habits.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 052 (§16.27.3, §16.27.7 y §16.26.5): límite y pendientes del test,
/// dosis con variante más difícil, kcal por tipo de día y reponer con rango.
/// Valores ficticios.
void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12), tue = DateTime(2026, 10, 13);
  const protocol = TestProtocolId.v32_13;
  late AppDatabase db;
  late FitnessTestRepository tests;

  setUp(() {
    db = openInMemoryDatabase();
    tests = FitnessTestRepository(db);
  });
  tearDown(() => db.close());

  Future<int> torso(DateTime day, {required List<TestResult> results, List<TestPendingItem> pending = const []}) =>
      tests.save(
          date: day,
          round: 1,
          part: TestPart.torso,
          protocol: protocol,
          scheme: 'v3.2',
          blockStart: mon,
          totalSec: 0,
          results: results,
          pending: pending);

  test('piel en el colgado: no es un máximo real; el pino sin colchoneta queda pendiente', () async {
    final id = await torso(tue, results: [
      const TestResult(round: 1, item: 'dead_hang', value: 65, limitedBy: 'piel'),
      const TestResult(round: 1, item: 'pullup', value: 18, limitedBy: 'fuerza'),
    ], pending: const [
      TestPendingItem(item: 'wall_handstand', reason: 'Piso resbaloso', requires: ['mat']),
    ]);
    final rows = await tests.all();
    expect(rows.singleWhere((r) => r.item == 'dead_hang').notRealMax, isTrue);
    expect(rows.singleWhere((r) => r.item == 'pullup').notRealMax, isFalse);
    final pending = await tests.pendingFor(id);
    expect((pending.single.item, pending.single.reason, pending.single.requires),
        ('wall_handstand', 'Piso resbaloso', 'mat'));
    expect(rows.where((r) => r.item == 'wall_handstand'), isEmpty, reason: 'no inventa valor');
    expect(await tests.openPending(), hasLength(1));
    // Medido después en otro intento: deja de estar pendiente.
    await tests.save(
        date: DateTime(2026, 10, 20),
        round: 1,
        part: TestPart.torso,
        protocol: protocol,
        scheme: 'v3.2',
        blockStart: mon,
        totalSec: 0,
        results: const [TestResult(round: 1, item: 'wall_handstand', value: 40)]);
    expect(await tests.openPending(), isEmpty);
  });

  test('un intento sólo con pendientes se guarda; medirlo en el mismo intento lo quita', () async {
    final id = await torso(tue, results: const [], pending: const [
      TestPendingItem(item: 'wall_handstand', reason: 'Sin colchoneta', requires: ['mat']),
    ]);
    expect(await tests.pendingFor(id), hasLength(1));
    await tests.save(
        date: tue,
        round: 1,
        part: TestPart.torso,
        protocol: protocol,
        scheme: 'v3.2',
        blockStart: mon,
        totalSec: 0,
        attemptId: id,
        results: const [TestResult(round: 1, item: 'wall_handstand', value: 30)],
        pending: const [TestPendingItem(item: 'wall_handstand', reason: 'Sin colchoneta')]);
    expect(await tests.pendingFor(id), isEmpty);
  });

  test('dosis que supera el tope del plan propone la variante más difícil', () {
    TestItem item(String id) => testItem(id)!;
    expect(harderVariantAdvice(item('pike_pushup'), 19), contains('pies elevados'));
    expect(harderVariantAdvice(item('pullup'), 18), contains('mochila'));
    expect(harderVariantAdvice(item('dips'), 20), contains('mochila'));
    expect(harderVariantAdvice(item('tuck_up'), 20), contains('peldaño 2'));
    expect(harderVariantAdvice(item('hanging_leg_raise'), 15), isNull, reason: '3 × 10–11 cabe en 6–12');
    expect(harderVariantAdvice(item('hollow_hold'), 46), isNull, reason: '25–28 s cabe en 20–30 s');
    expect(harderVariantAdvice(item('one_arm_pushup'), 4), isNull);
  });

  test('reponer tras el partido: 1,25–1,5 L por kg con algo de sal', () {
    final s = sweatReading(beforeKg: 79.8, afterKg: 78.6, fluidMl: 0, minutes: 90, weightsComparable: true)!;
    expect(s.replaceText, '1,5–1,8 L con algo de sal');
  });

  group('kcal por tipo de día', () {
    late DashboardRepository dashboard;
    late TrainingRepository training;
    setUp(() async {
      await db.customStatement('UPDATE profiles SET kcal_target = 2100, kcal_target_football = 2400');
      await asExistingUser(db, since: mon);
      final ex = ExerciseRepository(db);
      final plan = PlanRepository(db, ex);
      await seedIfEmpty(db, plan);
      await activatePlanV32(db, plan, mon);
      training = TrainingRepository(db, ex);
      dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    });

    test('un martes normal: 2.100–2.200; con partido entre semana: 2.400–2.500 · fútbol', () async {
      final normal = await dashboard.today(now: tue);
      expect((normal.kcalTarget, normal.kcalMax, normal.kcalDay), (2100, 2200, null));
      await training.saveFootball(FootballGamesCompanion.insert(
          date: '2026-10-13', minutes: 60, intensity: const Value(7)));
      final game = await dashboard.today(now: tue);
      expect((game.kcalTarget, game.kcalMax, game.kcalDay), (2400, 2500, 'fútbol'));
    });
  });
}
