import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/recovery.dart';
import 'package:seguimiento/domain/technique_session.dart';

import '../support/sqlite_host.dart';

/// Sesión técnica (§16.21): cuándo se ofrece en Hoy y qué trae.
void main() {
  late AppDatabase db;
  late DashboardRepository dashboard;

  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    final plan = PlanRepository(db, ExerciseRepository(db));
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, d(10, 12));
  });

  tearDown(() => db.close());

  test('plantilla del handoff: 8 ejercicios, lo de reps a RIR 4', () {
    expect(techniqueTemplate, hasLength(8));
    expect(techniqueTemplate.map((e) => e.$1), containsAll(['Dominadas', 'Flexión a una mano', 'Colgarse de la barra']));
    expect(techniqueTemplate.where((e) => e.$3 != null), hasLength(6));
  });

  test('se ofrece la víspera de cada test y de las pruebas, y en la descarga', () async {
    Future<bool> on(DateTime day) async => (await dashboard.today(now: day)).techniqueSuggested;
    expect(await on(d(10, 11)), isTrue, reason: 'domingo antes del Test 1, aunque el v3.1 empieza mañana');
    expect(await on(d(10, 13)), isTrue, reason: 'martes antes de las pruebas de piernas del 14');
    expect(await on(d(11, 17)), isTrue, reason: 'semana 6: descarga');
    expect(await on(d(12, 10)), isTrue, reason: 'jueves antes de las pruebas del 11 dic');
    expect(await on(d(10, 15)), isFalse, reason: 'jueves normal, sin plan B');
    expect(await on(d(10, 20)), isFalse);
  });

  test('una sesión técnica a RPE 4 no cuenta como intensa para la racha', () {
    final reading = loadReading([LoadItem(date: d(10, 13), minutes: 30, effort: 4)], d(10, 13));
    expect(reading.intenseStreak, 0);
  });
}
