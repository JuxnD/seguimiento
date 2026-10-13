import 'package:drift/drift.dart' show BooleanExpressionOperators;

import '../domain/dates.dart';
import '../domain/enums.dart';
import '../domain/fitness_test.dart' show TestPart;
import '../domain/plan_v3.dart' show V3Day;
import '../domain/test_protocol.dart';
import 'repositories/exercise_repository.dart';
import 'repositories/mobility_benchmark_repository.dart';
import 'repositories/training_repository.dart';
import '../domain/nutrition.dart';
import '../domain/progress.dart';
import '../domain/reminders.dart';
import 'database.dart';
import 'notification_service.dart';
import 'repositories/body_repository.dart';
import 'repositories/custom_reminder_repository.dart';
import 'repositories/nutrition_repository.dart';
import 'repositories/plan_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/reminder_repository.dart';
import 'repositories/coach_repository.dart';
import 'repositories/goal_repository.dart';
import 'repositories/readiness_repository.dart';
import '../domain/goal_history.dart';

/// Junta lo que hay en la base con las reglas de `domain/reminders.dart` y
/// deja programados los avisos de los próximos días.
class ReminderScheduler {
  ReminderScheduler({
    required this.db,
    required this.plan,
    required this.reminders,
    required this.nutrition,
    required this.body,
    required this.profile,
    required this.service,
  });

  final AppDatabase db;
  final PlanRepository plan;
  final ReminderRepository reminders;
  final NutritionRepository nutrition;
  final BodyRepository body;
  final ProfileRepository profile;
  final NotificationSink service;

  /// Vuelve a programar todo. Se llama al abrir la app y cada vez que cambia
  /// algo que puede alterar un aviso (sesión, comida, medida, ajustes).
  Future<List<PlannedNotification>> reschedule({int horizonDays = 7, DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final today = dateOnly(moment);
    // Lo que ya rige hoy pasa al perfil antes de leerlo (plan 009).
    await GoalRepository(db).projectDueGoals(today);
    final settings = await reminders.settings();
    final p = await profile.get();
    final history = await GoalRepository(db).history();
    final protein = goalReferenceOn(history, GoalMetric.proteinaMin, today);
    final kcal = kcalGoalReferenceOn(history, today);
    final stepsGoal = goalReferenceOn(history, GoalMetric.pasos, today);

    final days = <ReminderDay>[];
    final training = TrainingRepository(db, ExerciseRepository(db));
    for (var i = 0; i < horizonDays; i++) {
      final date = addDays(today, i);
      final view = await plan.dayFor(date);
      final type = view?.day.type ?? DayType.descanso;
      final block =
          await _testDay(date, await training.blockDay(view, date), today);
      days.add(ReminderDay(
        test: block.test,
        benchmarks: block.benchmarks,
        date: date,
        type: type,
        planSummary: view == null
            ? null
            : planSummaryFor(
                type,
                view.day.targetRounds,
                view.day.main.map((e) => '${e.name} ${e.targetLabel}'.trim()).toList(),
              ),
        hasSession: await _hasSession(date),
      ));
    }

    final meals = await nutrition.range(today, today);
    final totals = Macros.sum(meals.map((m) => m.macros));
    final slots = {for (final m in meals) m.meal.slot};
    final closed = isDayClosed(slots,
        manuallyClosed: await nutrition.isClosed(today), mealCount: meals.length, kcal: totals.kcal);
    final missing = closed ? const <MealSlot>[] : missingMainMeals(slots);

    final lastMeasurement = await body.lastCheckInBefore(addDays(today, 1));
    final steps = await (db.select(db.dailySteps)..where((t) => t.date.equals(dayKey(today)))).getSingleOrNull();
    final planned = planReminders(ReminderContext(
      now: moment,
      days: days,
      settings: settings,
      proteinToday: totals.protein,
      proteinMin: protein.comparable ? protein.value!.round() : null,
      kcalToday: totals.kcal,
      kcalTarget: kcal.comparable ? kcal.value!.round() : null,
      missingMealsToday: missing,
      stepsToday: steps?.steps,
      stepsTarget: stepsGoal.comparable ? stepsGoal.value!.round() : null,
      stepsRecoveryFirst: (await CoachRepository(db).stepsReading(today)).recoveryFirst,
      custom: await CustomReminderRepository(db).all(),
      lastMeasurement: lastMeasurement,
      measureIntervalDays: p.measureIntervalDays,
      // Una fecha acordada ya cumplida no debe seguir avisando.
      nextMeasurementDate: effectiveAgreedDate(
        agreed: p.nextMeasurementDate == null ? null : parseDay(p.nextMeasurementDate!),
        lastMeasurement: lastMeasurement,
      ),
      recoveryNoticeTonight: await ReadinessRepository(db).eveningNotice(today),
      routinesDoneToday: await ReadinessRepository(db).routinesOn(today),
    ));

    await service.applySchedule(planned);
    return planned;
  }

  /// El test y los benchmarks de ese día según la agenda efectiva del bloque
  /// (§19.17: un test movido se anuncia el día nuevo, no el previsto).
  Future<({ReminderTest? test, bool benchmarks})> _testDay(
      DateTime date, V3Day? v3, DateTime today) async {
    if (v3 == null || !v3.isV31) return (test: null, benchmarks: false);
    final start = addDays(date, -(date.weekday - 1) - (v3.week - 1) * 7);
    final protocol = v3.isV32 ? TestProtocolId.v32_13 : TestProtocolId.v31_12;
    final t = await ReadinessRepository(db).effectiveTestOn(date,
        scheme: v3.scheme, blockStart: start, protocol: protocol);
    final benchmarks = v3.isV32 &&
        await MobilityBenchmarkRepository(db).dueOn(date,
                scheme: v3.scheme,
                blockStart: start,
                protocol: protocol,
                asOf: today) !=
            null;
    if (t == null) return (test: null, benchmarks: benchmarks);
    final gate = t.gate!;
    return (
      test: ReminderTest(
        title:
            'Test ${t.round} de ${t.part == TestPart.torso ? 'torso' : 'piernas'}',
        movedFrom: t.moved ? t.planned : null,
        condition: switch (gate.label) {
          final label? => 'Ojo: $label.',
          null => null,
        },
      ),
      benchmarks: benchmarks,
    );
  }

  Future<bool> _hasSession(DateTime date) async {
    final row = await (db.select(db.sessions)
          ..where((t) => t.date.equals(dayKey(date)) & db.trainingSessions)
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }
}
