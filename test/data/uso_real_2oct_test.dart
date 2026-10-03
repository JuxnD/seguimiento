import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

/// Defectos del uso real al viernes 2 oct 2026 (traspaso §16.9).
void main() {
  late AppDatabase db;
  late TrainingRepository training;
  late DashboardRepository dashboard;

  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    final plan = PlanRepository(db, exercises);
    training = TrainingRepository(db, exercises);
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    await ProfileRepository(db).save(const ProfilesCompanion(startDate: Value('2026-08-26')));

    // Plan con el viernes de progresión fijado en 8: el número del plan no
    // se mueve solo.
    final v = PlanDraft.empty(d(8, 26));
    const types = [
      DayType.circuito,
      DayType.bloques,
      DayType.circuitoLigero,
      DayType.bloques,
      DayType.progresion,
      DayType.futbol,
      DayType.futbol,
    ];
    for (var i = 0; i < 7; i++) {
      v.days[i].type = types[i];
    }
    v.days[4].targetRounds = 8;
    await plan.saveAsNewVersion(v);
  });

  tearDown(() => db.close());

  group('§16.9 la meta del viernes avanza', () {
    test('sin anotar cómo fue, se mantiene y dice qué falta anotar', () async {
      await training.save(SessionDraft(date: d(9, 25), type: SessionType.progresion, roundsDone: 8, plannedRounds: 8));

      final friday = await dashboard.today(now: d(10, 2));
      expect(friday.targetRounds, 8);
      expect(friday.proposal!.blockedOnlyByMissing, isTrue);
      expect(friday.proposal!.unmet, contains('técnica sin registrar'));
    });

    test('con técnica, rango y recuperación en sí, Hoy propone 9', () async {
      final id =
          await training.save(SessionDraft(date: d(9, 25), type: SessionType.progresion, roundsDone: 8, plannedRounds: 8));
      await training.setProgressionCriteria(id, techniqueOk: true, fullRange: true, recoveryOk: true);

      final friday = await dashboard.today(now: d(10, 2));
      expect(friday.targetRounds, 9, reason: 'la meta sale de la regla, no del 8 fijo del plan');
      expect(friday.proposal!.canProgress, isTrue);
    });

    test('un criterio en "no" mantiene la meta aunque los demás estén bien', () async {
      final id =
          await training.save(SessionDraft(date: d(9, 25), type: SessionType.progresion, roundsDone: 8, plannedRounds: 8));
      await training.setProgressionCriteria(id, techniqueOk: true, fullRange: true, recoveryOk: false);

      final friday = await dashboard.today(now: d(10, 2));
      expect(friday.targetRounds, 8);
      expect(friday.proposal!.blockedOnlyByMissing, isFalse);
    });

    test('un día que no es de progresión sigue con la meta del plan', () async {
      await training.save(SessionDraft(date: d(9, 25), type: SessionType.progresion, roundsDone: 8, plannedRounds: 8));
      final monday = await dashboard.today(now: d(9, 28));
      expect(monday.proposal, isNull);
    });

    test('una progresión cortada en la ronda 1 de 8 no baja la meta a 1', () async {
      final id = await training
          .save(SessionDraft(date: d(10, 2), type: SessionType.progresion, roundsDone: 1, plannedRounds: 8, incomplete: true));
      await training.setProgressionCriteria(id, techniqueOk: true, fullRange: true, recoveryOk: true);
      final friday = await dashboard.today(now: d(10, 9));
      expect(friday.targetRounds, 8);
    });
  });
}
