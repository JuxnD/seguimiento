import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/coach_repository.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late DashboardRepository dashboard;
  final day = DateTime(2026, 9, 12);
  setUp(() async {
    db = openInMemoryDatabase();
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
  });
  tearDown(() => db.close());
  Future<void> game(int minutes, int? rpe, {int format = 5, String date = '2026-09-12'}) async {
    await db.into(db.footballGames).insert(FootballGamesCompanion.insert(
      date: date, minutes: minutes, intensity: Value(rpe), format: Value(format)));
  }
  test('todos los partidos: acumulado coincide con carga core y reporte', () async {
    await game(60, 6);
    await game(30, 9, format: 7);
    final today = await dashboard.today(now: day);
    expect(today.gamesToday, hasLength(2));
    expect(today.footballToday!.minutes, 30, reason: 'hidratar no fusiona pesajes');
    expect(today.footballSummary.minutes, 90);
    expect(today.footballSummary.load, 630);
    expect(today.footballSummary.weightedRpe, 7);
    expect(today.footballSummary.estimated, isFalse);
    expect(today.footballSummary.formatsLabel, 'Formatos mixtos (5 y 7)');
    expect((await CoachRepository(db).load(day)).todayLoad, today.footballSummary.load);
    final report = await ReportRepository(db, NutritionRepository(db)).load(day, day, today: day, withPrevious: false);
    expect(report.football, hasLength(2));
    expect(report.football.fold<int>(0, (sum, g) => sum + g.minutes), 90);
  });
  test('RPE desconocido: carga estimada core y ponderado sólo conocido', () async {
    await game(60, null);
    await game(30, 9);
    final summary = (await dashboard.today(now: day)).footballSummary;
    expect(summary.estimated, isTrue);
    expect(summary.weightedRpe, 9);
    expect(summary.load, 630);
    expect((await CoachRepository(db).load(day)).todayLoad, summary.load);
  });
  test('cero minutos no divide por cero; sin partidos no hay actividad', () async {
    final empty = await dashboard.today(now: day);
    expect(empty.gamesToday, isEmpty);
    expect(empty.footballSummary.weightedRpe, isNull);
    expect(empty.trained, isFalse);
    await game(0, 7);
    final summary = (await dashboard.today(now: day)).footballSummary;
    expect(summary.minutes, 0);
    expect(summary.load, 0);
    expect(summary.weightedRpe, isNull);
  });
  test('ayer intenso conserva lector y no contamina acumulado de hoy', () async {
    await game(45, 8, date: '2026-09-11');
    await game(60, 6);
    expect(await dashboard.hardGameBefore(day), isTrue);
    final today = await dashboard.today(now: day);
    expect(today.hardFootballYesterday!.minutes, 45);
    expect(today.footballSummary.minutes, 60);
    expect(today.footballSummary.formatsLabel, 'Fútbol 5');
  });
}
