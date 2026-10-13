import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late TrainingRepository training;
  late DashboardRepository dashboard;
  final before = DateTime(2026, 9, 4), attempt = DateTime(2026, 9, 11);
  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    final plan = PlanRepository(db, exercises);
    await seedIfEmpty(db, plan);
    training = TrainingRepository(db, exercises);
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
  });
  tearDown(() => db.close());
  SessionDraft draft(DateTime date, {int? rounds = 9, bool? quality = true,
      bool fail = false, bool incomplete = false, int planned = 9}) => SessionDraft(
    date: date, type: SessionType.progresion, roundsDone: rounds, plannedRounds: planned,
    rpe: 7, techniqueOk: quality, fullRange: quality, recoveryOk: quality,
    incomplete: incomplete, sets: [SetDraft(exercise: 'Flexiones', reps: 5, toFailure: fail)]);
  Future<String> report({DateTime? from}) async => buildReport(await ReportRepository(db, NutritionRepository(db))
      .load(from ?? attempt, attempt, today: attempt, withPrevious: false));

  test('Hoy autoriza desde anterior limpia; fallo actual no inventa infracción', () async {
    await training.save(draft(before));
    expect((await dashboard.today(now: attempt)).proposal!.rounds, 10);
    await training.save(draft(attempt, rounds: 10, planned: 10, fail: true));
    expect(await report(), isNot(contains('Subiste de 9 a 10')));
  });
  test('anterior fallida bloquea Hoy y reporte aunque actual salga limpia', () async {
    await training.save(draft(before, fail: true));
    expect((await dashboard.today(now: attempt)).proposal!.canProgress, isFalse);
    await training.save(draft(attempt, rounds: 10, planned: 10));
    final md = await report();
    expect(md, contains('Subiste de 9 a 10'));
    expect(md, contains('fallo temprano'));
  });
  for (final missing in [null, false]) {
    test('calidad anterior $missing no desaparece fuera del rango', () async {
      await training.save(draft(before, quality: missing));
      expect((await dashboard.today(now: attempt)).proposal!.canProgress, isFalse);
      await training.save(draft(attempt, rounds: 10, planned: 10));
      expect(await report(), contains('Subiste de 9 a 10'));
      if (missing == null) expect(await report(), contains('sin registrar'));
    });
  }
  test('incompleta anterior y meta pendiente no autorizan aumento', () async {
    await training.save(draft(before, incomplete: true, planned: 10));
    await training.save(draft(attempt, rounds: 10, planned: 10));
    expect(await report(), contains('no completó la meta'));
  });
  test('sin rondas en última anterior se explicita evidencia no evaluable', () async {
    await training.save(draft(DateTime(2026, 8, 28)));
    await training.save(draft(before, rounds: null));
    expect((await dashboard.today(now: attempt)).proposal, isNull);
    await training.save(draft(attempt, rounds: 10, planned: 10));
    expect(await report(), contains('Regla de progresión no evaluable'));
    expect(await report(), isNot(contains('Subiste de 9 a 10')));
  });
  test('salto mayor al incremento permitido no se justifica por calidad', () async {
    await training.save(draft(before));
    await training.save(draft(attempt, rounds: 11, planned: 11));
    expect(await report(), contains('Subiste de 9 a 11'));
  });
  test('sin precedente y registro futuro no inventan permiso', () async {
    await training.save(draft(DateTime(2026, 9, 18), rounds: 12));
    await training.save(draft(attempt, rounds: 10));
    expect(await report(), contains('Regla de progresión no evaluable'));
  });
  test('precedente dentro de rango y dos filas del mismo día usan último ID como Hoy', () async {
    await training.save(draft(before)..startTime = '20:00');
    await training.save(draft(before, fail: true)..startTime = '08:00');
    expect((await dashboard.today(now: attempt)).proposal!.canProgress, isFalse);
    await training.save(draft(attempt, rounds: 10, planned: 10));
    expect(await report(from: before), contains('Subiste de 9 a 10'));
    expect(await report(from: before), contains('fallo temprano'));
  });
  test('no usar sesión del mismo día ni otro tipo para autorizar el intento', () async {
    await training.save(draft(before));
    await training.save(SessionDraft(date: before, type: SessionType.circuito,
      roundsDone: 15, techniqueOk: false));
    await training.save(draft(attempt, fail: true));
    await training.save(draft(attempt, rounds: 10, planned: 10));
    expect((await dashboard.today(now: attempt)).proposal!.rounds, 10);
    expect(await report(), isNot(contains('Subiste de 9 a 10')));
  });
  for (final field in ['técnica', 'rango completo', 'recuperación']) {
    test('ausencia individual de $field anterior sigue siendo bloqueo explícito', () async {
      final prior = draft(before);
      if (field == 'técnica') prior.techniqueOk = null;
      if (field == 'rango completo') prior.fullRange = null;
      if (field == 'recuperación') prior.recoveryOk = null;
      await training.save(prior);
      expect((await dashboard.today(now: attempt)).proposal!.unmet, ['$field sin registrar']);
      await training.save(draft(attempt, rounds: 10, planned: 10));
      expect(await report(), contains('$field sin registrar'));
    });
  }
  for (final estimated in [false, true]) {
    test('precedente ${estimated ? 'estimado' : 'importado'} no acredita permiso', () async {
      final prior = draft(before)
        ..roundsEstimated = estimated
        ..imported = !estimated;
      await training.save(prior);
      expect((await dashboard.today(now: attempt)).proposal, isNull);
      await training.save(draft(attempt, rounds: 10, planned: 10));
      expect(await report(), contains('Regla de progresión no evaluable'));
    });
  }
}
