import '../domain/dates.dart';
import '../domain/enums.dart';
import '../domain/nutrition.dart';
import '../domain/progress.dart';
import '../domain/reminders.dart';
import 'database.dart';
import 'notification_service.dart';
import 'repositories/body_repository.dart';
import 'repositories/nutrition_repository.dart';
import 'repositories/plan_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/reminder_repository.dart';

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
    final settings = await reminders.settings();
    final p = await profile.get();

    final days = <ReminderDay>[];
    for (var i = 0; i < horizonDays; i++) {
      final date = addDays(today, i);
      final view = await plan.dayFor(date);
      final type = view?.day.type ?? DayType.descanso;
      days.add(ReminderDay(
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
    final proteinToday = Macros.sum(meals.map((m) => m.macros)).protein;

    final lastMeasurement = await body.lastCheckInBefore(addDays(today, 1));
    final planned = planReminders(ReminderContext(
      now: moment,
      days: days,
      settings: settings,
      proteinToday: proteinToday,
      proteinMin: p.proteinMin,
      lastMeasurement: lastMeasurement,
      measureIntervalDays: p.measureIntervalDays,
      // Una fecha acordada ya cumplida no debe seguir avisando.
      nextMeasurementDate: effectiveAgreedDate(
        agreed: p.nextMeasurementDate == null ? null : parseDay(p.nextMeasurementDate!),
        lastMeasurement: lastMeasurement,
      ),
    ));

    await service.applySchedule(planned);
    return planned;
  }

  Future<bool> _hasSession(DateTime date) async {
    final row = await (db.select(db.sessions)
          ..where((t) => t.date.equals(dayKey(date)))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }
}
