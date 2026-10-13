import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/leg_chain_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/leg_chain.dart';
import 'package:seguimiento/domain/report/report_builder.dart';

import '../support/sqlite_host.dart';

/// Plan 039: Hoy y el informe leen la misma cadena (un solo resolver), y la
/// tarjeta de Hoy lleva los motivos con sus días.
void main() {
  late AppDatabase db;
  late TrainingRepository training;
  late DashboardRepository dashboard;
  final mon = DateTime(2030, 3, 4);
  final wed = DateTime(2030, 3, 6);

  setUpAll(useHostSqlite);
  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    final plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, mon);
  });
  tearDown(() => db.close());

  test('el motivo de Hoy y la línea del informe salen de la misma cadena', () async {
    for (final d in [3, 4, 5]) {
      await training
          .saveFootball(FootballGamesCompanion.insert(date: dayKey(DateTime(2030, 3, d)), minutes: 90, intensity: const Value(8)));
    }
    await training.save(SessionDraft(date: DateTime(2030, 3, 2), type: SessionType.circuito, rpe: 8, totalSec: 600));

    final today = await dashboard.today(now: wed);
    expect(today.planB, isTrue);
    final reason = today.planBAdvice.reasons.singleWhere((r) => r.$1 == PlanBReason.legChain).$2;
    expect(reason, 'Piernas: 3 días intensos (dom 3 mar fútbol 90 min · lun 4 mar fútbol 90 min · mar 5 mar fútbol 90 min)');

    final chain = (await LegChainRepository(db).chains(wed)).legs;
    expect(chain.evidenceText, 'dom 3 mar fútbol 90 min · lun 4 mar fútbol 90 min · mar 5 mar fútbol 90 min');
    expect(chain.moderateDays, isEmpty,
        reason: 'el circuito de 10 min a RPE 8 es moderado, pero es anterior a la cadena: no está en medio');

    final input = await ReportRepository(db, NutritionRepository(db)).load(DateTime(2030, 3, 2), wed, today: wed);
    expect(input.legChains!.legs.evidenceText, chain.evidenceText);
    final md = buildReport(input);
    expect(md, contains('## Días intensos seguidos'));
    expect(md, contains('Piernas: 3 días intensos al cierre (dom 3 mar fútbol 90 min'));
    expect(md, contains('Pulso de la noche: no evaluable (sin fuente nocturna)'));
  });
}
